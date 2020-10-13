r"""
Fast sparse graphs

For an overview of graph data structures in sage, see
:mod:`~sage.graphs.base.overview`.

Usage Introduction
------------------

::

    sage: from sage.graphs.base.sparse_graph import SparseGraph

Sparse graphs are initialized as follows::

    sage: S = SparseGraph(nverts = 10, expected_degree = 3, extra_vertices = 10)

This example initializes a sparse graph with room for twenty vertices, the first
ten of which are in the graph. In general, the first ``nverts`` are "active."
For example, see that 9 is already in the graph::

    sage: S.verts()
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    sage: S.add_vertex(9)
    9
    sage: S.verts()
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

But 10 is not, until we add it::

    sage: S.add_vertex(10)
    10
    sage: S.verts()
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

You can begin working with unlabeled arcs right away as follows::

    sage: S.add_arc(0,1)
    sage: S.add_arc(1,2)
    sage: S.add_arc(1,0)
    sage: S.has_arc(7,3)
    False
    sage: S.has_arc(0,1)
    True
    sage: S.in_neighbors(1)
    [0]
    sage: S.out_neighbors(1)
    [0, 2]
    sage: S.del_all_arcs(0,1)
    sage: S.all_arcs(0,1)
    []
    sage: S.all_arcs(1,2)
    [0]
    sage: S.del_vertex(7)
    sage: S.all_arcs(7,3)
    Traceback (most recent call last):
    ...
    LookupError: vertex (7) is not a vertex of the graph

Sparse graphs support multiple edges and labeled edges, but requires that the
labels be positive integers (the case label = 0 is treated as no label).

::

    sage: S.add_arc_label(0,1,-1)
    Traceback (most recent call last):
    ...
    ValueError: Label (-1) must be a nonnegative integer.
    sage: S.add_arc(0,1)
    sage: S.arc_label(0,1)
    0

Note that ``arc_label`` only returns the first edge label found in the specified
place, and this can be in any order (if you want all arc labels, use
``all_arcs``)::

    sage: S.add_arc_label(0,1,1)
    sage: S.arc_label(0,1)
    1
    sage: S.all_arcs(0,1)
    [0, 1]

Zero specifies only that there is no labeled arc::

    sage: S.arc_label(1,2)
    0

So do not be fooled::

    sage: S.all_arcs(1,2)
    [0]
    sage: S.add_arc(1,2)
    sage: S.arc_label(1,2)
    0

Instead, if you work with unlabeled edges, be sure to use the right functions::

    sage: T = SparseGraph(nverts = 3, expected_degree = 2)
    sage: T.add_arc(0,1)
    sage: T.add_arc(1,2)
    sage: T.add_arc(2,0)
    sage: T.has_arc(0,1)
    True

Sparse graphs are by their nature directed. As of this writing, you need to do
operations in pairs to treat the undirected case (or use a backend or a Sage
graph)::

    sage: T.has_arc(1,0)
    False

Multiple unlabeled edges are also possible::

    sage: for _ in range(10): S.add_arc(5,4)
    sage: S.all_arcs(5,4)
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

The curious developer is encouraged to check out the ``unsafe`` functions,
which do not check input but which run in pure C.

Underlying Data Structure
-------------------------

The class ``SparseGraph`` contains the following variables which are inherited
from ``CGraph`` (for explanation, refer to the documentation there)::

        cdef int num_verts
        cdef int num_arcs
        cdef int *in_degrees
        cdef int *out_degrees
        cdef bitset_t active_vertices

It also contains the following variables::

        cdef int hash_length
        cdef int hash_mask
        cdef SparseGraphBTNode **vertices

For each vertex ``u``, a hash table of length ``hash_length`` is instantiated.
An arc ``(u, v)`` is stored at ``u * hash_length + hash(v)`` of the array
``vertices``, where ``hash`` should be thought of as an arbitrary but fixed hash
function which takes values in ``0 <= hash < hash_length``. Each address may
represent different arcs, say ``(u, v1)`` and ``(u, v2)`` where
``hash(v1) == hash(v2)``. Thus, a binary tree structure is used at this step to
speed access to individual arcs, whose nodes (each of which represents a pair
``(u,v)``) are instances of the following type::

    cdef struct SparseGraphBTNode:
        int vertex
        int number
        SparseGraphLLNode *labels
        SparseGraphBTNode *left
        SparseGraphBTNode *right

Which range of the ``vertices`` array the root of the tree is in determines
``u``, and ``vertex`` stores ``v``. The integer ``number`` stores only the
number of unlabeled arcs from ``u`` to ``v``.

Currently, labels are stored in a simple linked list, whose nodes are instances
of the following type::

    cdef struct SparseGraphLLNode:
        int label
        int number
        SparseGraphLLNode *next

The int ``label`` must be a positive integer, since 0 indicates no label, and
negative numbers indicate errors. The int ``number`` is the number of arcs with
the given label.

TODO: Optimally, edge labels would also be represented by a binary tree, which
would help performance in graphs with many overlapping edges. Also, a more
efficient binary tree structure could be used, although in practice the trees
involved will usually have very small order, unless the degree of vertices
becomes significantly larger than the ``expected_degree`` given, because this is
the size of each hash table. Indeed, the expected size of the binary trees is
`\frac{\text{actual degree}}{\text{expected degree}}`. Ryan Dingman, e.g., is
working on a general-purpose Cython-based red black tree, which would be optimal
for both of these uses.
"""

#*****************************************************************************
#       Copyright (C) 2008-9 Robert L. Miller <rlmillster@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#                  http://www.gnu.org/licenses/
#*****************************************************************************


from libc.string cimport memset
from cysignals.memory cimport check_malloc, check_allocarray, sig_free

from sage.data_structures.bitset_base cimport *
from sage.data_structures.bitset cimport *

cdef enum:
    BT_REORDERING_CONSTANT = 145533211
    # Since the binary tree will often see vertices coming in already sorted,
    # we don't use the normal ordering on integers, instead multiplying by a
    # randomly chosen number and (after reducing mod the size of integers)
    # comparing the result. This isn't necessarily the most efficient way to do
    # things, but it may just be on binary trees that are never bigger than two
    # or three nodes.

cdef inline int compare(int a, int b):
    # Here we rely on the fact that C performs arithmetic on unsigned
    # ints modulo 2^wordsize.
    cdef unsigned int aa = a, bb = b # signed ints lead to badness like a>b>c>a...
    if aa*BT_REORDERING_CONSTANT > bb*BT_REORDERING_CONSTANT:
        return 1
    elif aa*BT_REORDERING_CONSTANT < bb*BT_REORDERING_CONSTANT:
        return -1
    return 0

cdef class SparseGraph(CGraph):
    """
    Compiled sparse graphs.

    ::

        sage: from sage.graphs.base.sparse_graph import SparseGraph

    Sparse graphs are initialized as follows::

        sage: S = SparseGraph(nverts = 10, expected_degree = 3, extra_vertices = 10)

    INPUT:

     - ``nverts`` -- non-negative integer, the number of vertices.

     - ``expected_degree`` -- non-negative integer (default: 16), expected upper
        bound on degree of vertices.

     - ``extra_vertices`` -- non-negative integer (default: 0), how many extra
        vertices to allocate.

     - ``verts`` -- optional list of vertices to add

     - ``arcs`` -- optional list of arcs to add

    The first ``nverts`` are created as vertices of the graph, and the next
    ``extra_vertices`` can be freely added without reallocation. See top level
    documentation for more details. The input ``verts`` and ``arcs`` are mainly
    for use in pickling.

    """

    def __cinit__(self, int nverts, int expected_degree = 16, int extra_vertices = 10, verts=None, arcs=None, directed=True):
        """
        Allocation and initialization happen in one place.

        Memory usage is roughly

        O(  (nverts + extra_vertices)*expected_degree + num_arcs  ).

        EXAMPLES::

            sage: from sage.graphs.base.sparse_graph import SparseGraph
            sage: S = SparseGraph(nverts = 10, expected_degree = 3, extra_vertices = 10)

        TESTS::

            sage: Graph(-1)
            Traceback (most recent call last):
            ...
            ValueError: The number of vertices cannot be strictly negative!
        """
        cdef int i = 1
        if nverts < 0:
            raise ValueError("The number of vertices cannot be strictly negative!")
        if nverts == 0 and extra_vertices == 0:
            raise RuntimeError('Sparse graphs must allocate space for vertices!')
        self.num_verts = nverts
        nverts += extra_vertices
        self.num_arcs = 0
        while i < expected_degree:
            i = i << 1
        self.hash_length = i
        self.hash_mask = i - 1

        # Allocating memory (initialized to zero)
        self.vertices = <SparseGraphBTNode **>check_calloc(
                nverts * self.hash_length, sizeof(SparseGraphBTNode *))
        if directed:
            # In a directed graph we keep also track of the incoming edges.
            # So each edge has two copies.
            self.vertices_rev = <SparseGraphBTNode **>check_calloc(
                    nverts * self.hash_length, sizeof(SparseGraphBTNode *))
        else:
            self.vertices_rev = self.vertices
        self._directed = directed

        self.in_degrees = <int *>check_calloc(nverts, sizeof(int))
        self.out_degrees = <int *>check_calloc(nverts, sizeof(int))

        bitset_init(self.active_vertices, self.num_verts + extra_vertices)
        bitset_set_first_n(self.active_vertices, self.num_verts)

        if verts is not None:
            self.add_vertices(verts)

        if arcs is not None:
            for u,v,l in arcs:
                self.add_arc_label(u,v,l)

    def __dealloc__(self):
        """
        New and dealloc are both tested at class level.
        """
        cdef SparseGraphBTNode **temp
        cdef SparseGraphLLNode *label_temp
        cdef size_t i

        # Freeing the list of arcs attached to each vertex (going out)
        for i in range(self.active_vertices.size * self.hash_length):
            temp = &(self.vertices[i])

            # While temp[0]=self.vertices[i] is not NULL, find a leaf in the
            # tree rooted at temp[0] and free it. Then go back to temp[0] and do
            # it again. When self.vertices[i] is NULL, go for self.vertices[i+1]
            while temp[0]:
                if temp[0].left:
                    temp = &(temp[0].left)
                elif temp[0].right:
                    temp = &(temp[0].right)
                else:
                    label_temp = temp[0].labels
                    while label_temp:
                        temp[0].labels = label_temp.next
                        sig_free(label_temp)
                        label_temp = temp[0].labels
                    sig_free(temp[0])
                    temp[0] = NULL
                    temp = &(self.vertices[i])

        if self.is_directed():

            # Freeing the list of arcs attached to each vertex (going in)
            for i in range(self.active_vertices.size * self.hash_length):
                temp = &(self.vertices_rev[i])

                # While temp[0]=self.vertices_rev[i] is not NULL, find a leaf in the
                # tree rooted at temp[0] and free it. Then go back to temp[0] and do
                # it again. When self.vertices_rev[i] is NULL, go for self.vertices_rev[i+1]
                while temp[0]:
                    if temp[0].left:
                        temp = &(temp[0].left)
                    elif temp[0].right:
                        temp = &(temp[0].right)
                    else:
                        label_temp = temp[0].labels
                        while label_temp:
                            temp[0].labels = label_temp.next
                            sig_free(label_temp)
                            label_temp = temp[0].labels
                        sig_free(temp[0])
                        temp[0] = NULL
                        temp = &(self.vertices_rev[i])
            sig_free(self.vertices_rev)

        sig_free(self.vertices)
        sig_free(self.in_degrees)
        sig_free(self.out_degrees)
        bitset_free(self.active_vertices)

    cpdef realloc(self, int total):
        """
        Reallocate the number of vertices to use, without actually adding any.

        INPUT:

         - ``total`` -- integer, the total size to make the array

        Returns -1 and fails if reallocation would destroy any active vertices.

        EXAMPLES::

            sage: from sage.graphs.base.sparse_graph import SparseGraph
            sage: S = SparseGraph(nverts=4, extra_vertices=4)
            sage: S.current_allocation()
            8
            sage: S.add_vertex(6)
            6
            sage: S.current_allocation()
            8
            sage: S.add_vertex(10)
            10
            sage: S.current_allocation()
            16
            sage: S.add_vertex(40)
            Traceback (most recent call last):
            ...
            RuntimeError: requested vertex is past twice the allocated range: use realloc
            sage: S.realloc(50)
            sage: S.add_vertex(40)
            40
            sage: S.current_allocation()
            50
            sage: S.realloc(30)
            -1
            sage: S.current_allocation()
            50
            sage: S.del_vertex(40)
            sage: S.realloc(30)
            sage: S.current_allocation()
            30

        """
        if not total:
            raise RuntimeError('Sparse graphs must allocate space for vertices!')
        cdef bitset_t bits
        cdef size_t s_total = <size_t>total
        if s_total < self.active_vertices.size:
            bitset_init(bits, self.active_vertices.size)
            bitset_set_first_n(bits, s_total)
            if not bitset_issubset(self.active_vertices, bits):
                bitset_free(bits)
                return -1
            bitset_free(bits)

        self.vertices = <SparseGraphBTNode **>check_reallocarray(
                self.vertices, s_total * self.hash_length, sizeof(SparseGraphBTNode *))
        if self.is_directed():
            self.vertices_rev = <SparseGraphBTNode **>check_reallocarray(
                    self.vertices_rev, s_total * self.hash_length, sizeof(SparseGraphBTNode *))
        else:
            self.vertices_rev = self.vertices

        self.in_degrees = <int *>check_reallocarray(self.in_degrees, s_total, sizeof(int))
        self.out_degrees = <int *>check_reallocarray(self.out_degrees, s_total, sizeof(int))

        cdef int new_vertices = total - self.active_vertices.size

        # Initializing the entries corresponding to new vertices if any
        if new_vertices > 0:

            # self.vertices
            memset(self.vertices + self.active_vertices.size * self.hash_length, 0,
                   new_vertices * self.hash_length * sizeof(SparseGraphBTNode *))
            if self.is_directed():
                memset(self.vertices_rev + self.active_vertices.size * self.hash_length, 0,
                       new_vertices * self.hash_length * sizeof(SparseGraphBTNode *))

            # self.in_degrees
            memset(self.in_degrees + self.active_vertices.size, 0,
                    new_vertices * sizeof(int))

            # self.out_degrees
            memset(self.out_degrees + self.active_vertices.size, 0,
                    new_vertices * sizeof(int))

        # self.active_vertices
        bitset_realloc(self.active_vertices, s_total)

    cpdef inline bint is_directed(self):
        r"""
        Return whether the graph is directed.

        EXAMPLES::

            sage: from sage.graphs.base.sparse_graph import SparseGraph
            sage: G = SparseGraph(5)
            sage: G.is_directed()
            True
            sage: G = SparseGraph(5, directed=False)
            sage: G.is_directed()
            False
        """
        return self._directed

    ###################################
    # Unlabeled arc functions
    ###################################

    cdef inline int _del_arc_unsafe(self, int u, int v, SparseGraphBTNode **parent) except -1:
        """
        .. WARNING::

            This method is for internal use only. Use :meth:`del_arc_unsafe` instead.

        Deletes *all* arcs from u to v, returns the number of arcs deleted.
        """
        cdef int i = (u * self.hash_length) + (v & self.hash_mask)
        parent = &parent[i]
        cdef int compared, left_len, right_len
        cdef SparseGraphBTNode *temp
        cdef SparseGraphBTNode **left_child
        cdef SparseGraphBTNode **right_child
        cdef SparseGraphLLNode *labels
        cdef int n_arcs = 0

        # Assigning to parent the SparseGraphBTNode corresponding to arc (u,v)
        while parent[0]:
            compared = compare(parent[0].vertex, v)
            if compared > 0:
                parent = &(parent[0].left)
            elif compared < 0:
                parent = &(parent[0].right)
            else:# if parent[0].vertex == v:
                break

        # If not found, there is no arc to delete !
        if not parent[0]:
            return n_arcs

        # now parent[0] points to the BT node corresponding to (u,v)
        labels = parent[0].labels
        n_arcs += parent[0].number

        # Freeing the labels
        while labels:
            n_arcs += labels.number
            parent[0].labels = parent[0].labels.next
            sig_free(labels)
            labels = parent[0].labels

        # Now, if the SparseGraphBTNode element is to be removed, it has to be
        # replaced in the binary tree by one of its children.

        # If there is no left child
        if not parent[0].left:
            temp = parent[0]
            parent[0] = parent[0].right
            sig_free(temp)
            return n_arcs

        # If there is no right child
        elif not parent[0].right:
            temp = parent[0]
            parent[0] = parent[0].left
            sig_free(temp)
            return n_arcs

        # Both children
        else:
            left_len = 0
            right_len = 0
            left_child = &(parent[0].left)
            right_child = &(parent[0].right)

            # left_len is equal to the maximum length of a path LR...R. The
            # last element of this path is the value of left_child

            while left_child[0].right:
                left_len += 1
                left_child = &(left_child[0].right)
            # right_len is equal to the maximum length of a path RL...L. The
            # last element of this path is the value of right_child

            while right_child[0].left:
                right_len += 1
                right_child = &(right_child[0].left)

            # According to the respective lengths, replace parent by the left or
            # right child and place the other child at its expected place.
            if left_len > right_len:
                left_child[0].right = parent[0].right
                temp = parent[0]
                parent[0] = left_child[0]
                left_child[0] = left_child[0].left
                parent[0].left = temp.left
                sig_free(temp)
                return n_arcs
            else:
                right_child[0].left = parent[0].left
                temp = parent[0]
                parent[0] = right_child[0]
                right_child[0] = right_child[0].right
                parent[0].right = temp.right
                sig_free(temp)
                return n_arcs

    cdef int del_arc_unsafe(self, int u, int v) except -1:
        """
        Deletes *all* arcs from u to v.

        INPUT:

        - ``u, v`` -- non-negative integers

        OUTPUT:
            0 -- No error.
            1 -- No arc to delete.

        """
        cdef int n_arcs = self._del_arc_unsafe(u, v, self.vertices)
        if u != v or self.is_directed():
            # We remove the reverse copy only if u != v or graph is directed.
            self._del_arc_unsafe(v, u, self.vertices_rev)
            if self.vertices == self.vertices_rev:
                # In case of an undirected graph, we have added two copies each.
                self.in_degrees[u] -= n_arcs
                self.out_degrees[v] -= n_arcs
                self.num_arcs -= n_arcs

        self.in_degrees[v] -= n_arcs
        self.out_degrees[u] -= n_arcs
        self.num_arcs -= n_arcs
        if n_arcs:
            return 1

    ###################################
    # Neighbor functions
    ###################################

    cdef int out_neighbors_BTNode_unsafe(self, int u, SparseGraphBTNode *** p_pointers):
        """
        List the out-neighbors of a vertex as BTNodes

        Technically, this function transforms a binary tree into a list. The
        information it returns is a list of pointers toward a
        ``SparseGraphBTNode``, thus a ``SparseGraphBTNode **``.

        INPUT:

        - ``u`` -- the vertex to consider

        - ``p_pointers`` -- a pointer toward a ``SparseGraphBTNode **``, i.e. a
          ``SparseGraphBTNode ***``. When the function terminates,
          ``p_pointers[0]`` points toward a filled ``SparseGraphBTNode **``. It
          returns the length of this array.

        .. NOTE::

            Don't forget to free ``p_pointers[0]``  !
        """
        cdef int num_nbrs = 0
        cdef int degree = self.out_degrees[u]
        if degree == 0:
            p_pointers[0] = NULL
            return 0
        cdef SparseGraphBTNode **pointers = <SparseGraphBTNode **>check_allocarray(degree, sizeof(SparseGraphBTNode *))
        p_pointers[0] = pointers

        cdef SparseGraphBTNode* v = self.next_out_neighbor_BTNode_unsafe(u, -1)
        while v:
            pointers[num_nbrs] = v
            num_nbrs += 1
            v = self.next_out_neighbor_BTNode_unsafe(u, v.vertex)

        return num_nbrs

    cdef inline int next_out_neighbor_unsafe(self, int u, int v, int* l) except -2:
        """
        Return the next out-neighbor of ``u`` that is greater than ``v``.

        If ``v`` is ``-1`` return the first neighbor of ``u``.

        Return ``-1`` in case there does not exist such an out-neighbor.

        Set ``l`` to be the label of the first arc.
        """
        cdef SparseGraphBTNode* next_bt = self.next_out_neighbor_BTNode_unsafe(u, v)
        if next_bt:
            if next_bt.number:
                l[0] = 0
            else:
                l[0] = next_bt.labels.label
            return next_bt.vertex
        else:
            return -1

    cdef inline SparseGraphBTNode* next_neighbor_BTNode_unsafe(self, SparseGraphBTNode** vertices, int u, int v):
        """
        Return the next neighbor of ``u`` that is greater than ``v``.

        If ``v`` is ``-1`` return the first neighbor of ``u``.

        Return ``NULL`` in case there does not exist such a neighbor.

        If ``vertices`` is ``self.vertices`` the out-neighbor is given.
        If ``vertices`` is ``self.vertices_rev`` the in-neighbor is given.
        """
        cdef int i
        cdef int start_i = (u * self.hash_length) + (v & self.hash_mask)
        cdef SparseGraphBTNode* temp
        cdef SparseGraphBTNode* last_larger

        i = start_i
        if v != -1 and vertices[i]:
            last_larger = NULL
            temp = vertices[i]
            while temp:
                if compare(temp.vertex, v) > 0:
                    # We have found a candidate.
                    # We fall back to it, if we do not find anything smaller.
                    last_larger = temp
                    temp = temp.left
                else: # note compare < 0
                    temp = temp.right
            if last_larger:
                return last_larger
        elif v == -1:
            start_i = (u*self.hash_length) - 1

        # Return the next vertex.
        for i in range(start_i+1, (u+1) * self.hash_length):
            if not vertices[i]:
                continue
            temp = vertices[i]
            while temp.left:
                temp = temp.left
            return temp
        return NULL

    cpdef int out_degree(self, int u):
        """
        Returns the out-degree of ``v``

        INPUT:

         - ``u`` -- integer

        EXAMPLES::

            sage: from sage.graphs.base.sparse_graph import SparseGraph
            sage: G = SparseGraph(5)
            sage: G.add_arc(0,1)
            sage: G.add_arc(1,2)
            sage: G.add_arc(1,3)
            sage: G.out_degree(0)
            1
            sage: G.out_degree(1)
            2
        """
        return self.out_degrees[u]

    cdef int in_neighbors_BTNode_unsafe(self, int v, SparseGraphBTNode *** p_pointers):
        """
        List the in-neighbors of a vertex as BTNodes

        Technically, this function transforms a binary tree into a list. The
        information it returns is a list of pointers toward a
        ``SparseGraphBTNode``, thus a ``SparseGraphBTNode **``.

        INPUT:

        - ``u`` -- the vertex to consider

        - ``p_pointers`` -- a pointer toward a ``SparseGraphBTNode **``, i.e. a
          ``SparseGraphBTNode ***``. When the function terminates,
          ``p_pointers[0]`` points toward a filled ``SparseGraphBTNode **``. It
          returns the length of this array.

        .. NOTE::

            Don't forget to free ``p_pointers[0]``  !
        """
        cdef int num_nbrs = 0
        cdef int degree = self.in_degrees[v]
        if degree == 0:
            p_pointers[0] = NULL
            return 0
        cdef SparseGraphBTNode **pointers = <SparseGraphBTNode **>check_allocarray(degree, sizeof(SparseGraphBTNode *))
        p_pointers[0] = pointers

        cdef SparseGraphBTNode* u = self.next_in_neighbor_BTNode_unsafe(v, -1)
        while u:
            pointers[num_nbrs] = u
            num_nbrs += 1
            u = self.next_in_neighbor_BTNode_unsafe(v, u.vertex)

        return num_nbrs

    cdef inline int next_in_neighbor_unsafe(self, int v, int u, int* l) except -2:
        """
        Return the next in-neighbor of ``v`` that is greater than ``u``.

        If ``u`` is ``-1`` return the first neighbor of ``v``.

        Return ``-1`` in case there does not exist such an in-neighbor.

        Set ``l`` to be the label of the first arc.
        """
        cdef SparseGraphBTNode* next_bt = self.next_in_neighbor_BTNode_unsafe(v, u)
        if next_bt:
            if next_bt.number:
                l[0] = 0
            else:
                l[0] = next_bt.labels.label
            return next_bt.vertex
        else:
            return -1

    cpdef int in_degree(self, int v):
        """
        Returns the in-degree of ``v``

        INPUT:

         - ``v`` -- integer

        EXAMPLES::

            sage: from sage.graphs.base.sparse_graph import SparseGraph
            sage: G = SparseGraph(5)
            sage: G.add_arc(0,1)
            sage: G.add_arc(1,2)
            sage: G.add_arc(1,3)
            sage: G.in_degree(0)
            0
            sage: G.in_degree(1)
            1
        """
        return self.in_degrees[v]

    ###################################
    # Labeled arc functions
    ###################################

    cdef inline int _add_arc_label_unsafe(self, int u, int v, int l, SparseGraphBTNode **ins_pt) except -1:
        r"""
        .. WARNING::

            This method is for internal use only. Use :meth:`add_arc_label_unsafe` instead.

        Add arc (u, v) with label l to only the ingoing or outgoing arcs
        """
        cdef int i = (u * self.hash_length) + (v & self.hash_mask)
        ins_pt = &ins_pt[i]
        cdef int compared
        cdef SparseGraphLLNode *label_ptr
        while ins_pt[0]:
            compared = compare(ins_pt[0].vertex, v)
            if compared > 0:
                ins_pt = &(ins_pt[0].left)
            elif compared < 0:
                ins_pt = &(ins_pt[0].right)
            else:
                break
        if not ins_pt[0]:
            ins_pt[0] = <SparseGraphBTNode *>check_malloc(sizeof(SparseGraphBTNode))
            ins_pt[0].number = 0
            ins_pt[0].vertex = v
            ins_pt[0].left = NULL
            ins_pt[0].right = NULL
            ins_pt[0].labels = NULL
        if l:
            label_ptr = ins_pt[0].labels
            while label_ptr and label_ptr.label != l:
                label_ptr = label_ptr.next
            if not label_ptr:
                label_ptr = <SparseGraphLLNode *>check_malloc(sizeof(SparseGraphLLNode))
                label_ptr.label = l
                label_ptr.number = 1
                label_ptr.next = ins_pt[0].labels
                ins_pt[0].labels = label_ptr
            else:
                label_ptr.number += 1
        else:
            ins_pt[0].number += 1

    cdef int add_arc_label_unsafe(self, int u, int v, int l) except -1:
        """
        Add arc (u, v) to the graph with label l.

        INPUT:

        - ``u, v`` -- non-negative integers

        - ``l`` -- a positive integer label, or zero for no label

        OUTPUT: ``0`` -- No error.

        """
        self._add_arc_label_unsafe(u, v, l, self.vertices)
        if u != v or self.is_directed():
            # We add the reverse copy only if u != v or graph is directed.
            self._add_arc_label_unsafe(v, u, l, self.vertices_rev)
            if self.vertices == self.vertices_rev:
                # In case of an undirected graph, we have added two arcs.
                self.in_degrees[u] += 1
                self.out_degrees[v] += 1
                self.num_arcs += 1


        self.in_degrees[v] += 1
        self.out_degrees[u] += 1
        self.num_arcs += 1

    def add_arc_label(self, int u, int v, int l=0):
        """
        Add arc ``(u, v)`` to the graph with label ``l``.

        INPUT:

         - ``u, v`` -- non-negative integers, must be in self

         - ``l`` -- a positive integer label, or zero for no label

        EXAMPLES::

            sage: from sage.graphs.base.sparse_graph import SparseGraph
            sage: G = SparseGraph(5)
            sage: G.add_arc_label(0,1)
            sage: G.add_arc_label(4,7)
            Traceback (most recent call last):
            ...
            LookupError: vertex (7) is not a vertex of the graph
            sage: G.has_arc(1,0)
            False
            sage: G.has_arc(0,1)
            True
            sage: G.add_arc_label(1,2,2)
            sage: G.arc_label(1,2)
            2

        """
        self.check_vertex(u)
        self.check_vertex(v)
        if l < 0:
            raise ValueError("Label ({0}) must be a nonnegative integer.".format(l))
        self.add_arc_label_unsafe(u,v,l)

    cdef int arc_label_unsafe(self, int u, int v) except -1:
        """
        Retrieves the first label found associated with (u, v) (a positive
        integer).

        INPUT:

        - ``u, v`` -- integers from `0, ..., n-1`, where `n` is the number of vertices

        OUTPUT: one of

        - positive integer -- indicates that there is a label on ``(u, v)``.

        - ``0`` -- either the arc ``(u, v)`` is unlabeled, or there is no arc at all.

        """
        cdef int i = (u * self.hash_length) + (v & self.hash_mask)
        cdef int compared
        cdef SparseGraphBTNode *temp = self.vertices[i]
        while temp:
            compared = compare(temp.vertex, v)
            if compared > 0:
                temp = temp.left
            elif compared < 0:
                temp = temp.right
            else:
                break
        if not temp or not temp.labels:
            return 0
        return temp.labels.label

    cdef int all_arcs_unsafe(self, int u, int v, int *arc_labels, int size) except -1:
        """
        Gives the labels of all arcs (u, v).

        INPUT:

        - ``u, v`` -- integers from 0, ..., n-1, where n is the number of vertices
            arc_labels -- must be a pointer to an (allocated) integer array
            size -- the length of the array

        OUTPUT:

        - integer -- the number of arcs ``(u, v)``
          ``-1`` -- indicates that the array has been filled with labels, but
          there were more

        """
        cdef int i = (u * self.hash_length) + (v & self.hash_mask), j
        cdef int compared, num_arcs
        cdef SparseGraphBTNode *temp = self.vertices[i]
        cdef SparseGraphLLNode *label
        while temp:
            compared = compare(temp.vertex, v)
            if compared > 0:
                temp = temp.left
            elif compared < 0:
                temp = temp.right
            else: # temp.vertex == v:
                break
        if not temp:
            return 0
        j = 0
        num_arcs = temp.number
        while j < num_arcs and j < size:
            arc_labels[j] = 0
            j += 1
        label = temp.labels
        while label:
            num_arcs += label.number
            while j < num_arcs and j < size:
                arc_labels[j] = label.label
                j += 1
            label = label.next
        if j == size and label:
            return -1
        return num_arcs

    cdef SparseGraphLLNode* arc_labels_unsafe(self, int u, int v):
        """
        Return the first label of arcs (u, v) or ``NULL`` if there are none.

        INPUT:

        - ``u, v`` -- integers from 0, ..., n-1, where n is the number of vertices
            arc_labels -- must be a pointer to an (allocated) integer array
            size -- the length of the array

        OUTPUT:

        - a pointer to the first label or ``NULL`` if there are none
        """
        cdef int i = (u * self.hash_length) + (v & self.hash_mask), j
        cdef int compared, num_arcs
        cdef SparseGraphBTNode *temp = self.vertices[i]
        cdef SparseGraphLLNode *label
        while temp:
            compared = compare(temp.vertex, v)
            if compared > 0:
                temp = temp.left
            elif compared < 0:
                temp = temp.right
            else: # temp.vertex == v:
                break
        if not temp:
            return NULL
        return temp.labels

    cdef inline int _del_arc_label_unsafe(self, int u, int v, int l, SparseGraphBTNode **parent):
        """
        .. WARNING::

            This method is for internal use only. Use :meth:`del_arc_label_unsafe` instead.

        Delete an arc (u, v) with label l.

        OUTPUT:
            0 -- No error.
            1 -- No arc with label l.
        """
        cdef int i = (u * self.hash_length) + (v & self.hash_mask)
        cdef SparseGraphBTNode **old_parent = parent
        parent = &parent[i]
        cdef int compared
        cdef SparseGraphLLNode **labels
        cdef SparseGraphLLNode *label
        while parent[0]:
            compared = compare(parent[0].vertex, v)
            if compared > 0:
                parent = &(parent[0].left)
            elif compared < 0:
                parent = &(parent[0].right)
            else: # if parent[0].vertex == v:
                break
        if not parent[0]:
            return 1 # indicate an error
        if l == 0:
            if parent[0].number > 1: parent[0].number -= 1
            elif parent[0].number == 1:
                if not parent[0].labels:
                    self._del_arc_unsafe(u, v, old_parent)
                    return 0
                else: parent[0].number -= 1
            else: return 1 # indicate an error
        else:
            labels = &(parent[0].labels)
            while labels[0] and labels[0].label != l:
                labels = &(labels[0].next)
            if not labels[0]:
                return 1
            label = labels[0]
            if label.number > 1:
                label.number -= 1
            else:
                labels[0] = labels[0].next
                sig_free(label)
                if labels == &(parent[0].labels) and not labels[0] and parent[0].number == 0:
                    # here we need to delete an "empty" binary tree node
                    self._del_arc_unsafe(u, v, old_parent)

    cdef int del_arc_label_unsafe(self, int u, int v, int l) except -1:
        """
        Delete an arc (u, v) with label l.

        INPUT:

        - ``u, v`` -- integers from `0, ..., n-1`, where `n` is the number of vertices

        - ``l`` -- a positive integer label, or zero for no label

        OUTPUT: one of

        - ``0`` -- No error

        - ``1`` -- No arc with label ``l``
        """
        if self._del_arc_label_unsafe(u, v, l, self.vertices):
            return 1 # indicate an error

        if u != v or self.is_directed():
            # We remove the reverse copy only if u != v or graph is directed.
            self._del_arc_label_unsafe(v, u, l, self.vertices_rev)
            if self.vertices == self.vertices_rev:
                # In case of an undirected graph, we have removed two arcs.
                self.in_degrees[u] -= 1
                self.out_degrees[v] -= 1
                self.num_arcs -= 1

        self.in_degrees[v] -= 1
        self.out_degrees[u] -= 1
        self.num_arcs -= 1

    cdef int has_arc_label_unsafe(self, int u, int v, int l) except -1:
        """
        Indicates whether there is an arc (u, v) with label l.

        INPUT:

        - ``u, v`` -- integers from `0, ..., n-1`, where `n` is the number of vertices

        - ``l`` -- a positive integer label, or zero for no label, or ``-1`` for any label

        OUTPUT: one of

        - ``0`` -- False

        - ``1`` -- True
        """
        cdef int i = (u * self.hash_length) + (v & self.hash_mask)
        cdef int compared
        cdef SparseGraphBTNode *temp = self.vertices[i]
        cdef SparseGraphLLNode *label
        while temp:
            compared = compare(temp.vertex, v)
            if compared > 0:
                temp = temp.left
            elif compared < 0:
                temp = temp.right
            else:# if temp.vertex == v:
                break
        if not temp:
            return 0
        if l == -1:
            return 1
        if l == 0 and temp.number > 0:
            return 1
        label = temp.labels
        while label:
            if label.label == l:
                return 1
            label = label.next
        return 0

##############################
# Further tests. Unit tests for methods, functions, classes defined with cdef.
##############################

def _test_adjacency_sequence_out():
    """
    Randomly test the method ``SparseGraph.adjacency_sequence_out()``. No output
    indicates that no errors were found.

    TESTS::

        sage: from sage.graphs.base.sparse_graph import _test_adjacency_sequence_out
        sage: _test_adjacency_sequence_out()  # long time
    """
    from sage.graphs.digraph import DiGraph
    from sage.graphs.graph_generators import GraphGenerators
    from sage.misc.prandom import randint, random
    low = 0
    high = 1000
    randg = DiGraph(GraphGenerators().RandomGNP(randint(low, high), random()))
    n = randg.order()
    # set all labels to 0
    E = [(u, v, 0) for u, v in randg.edges(labels=False)]
    cdef SparseGraph g = SparseGraph(n,
                                     verts=randg.vertices(),
                                     arcs=E)
    assert g.num_verts == randg.order(), (
        "Graph order mismatch: %s vs. %s" % (g.num_verts, randg.order()))
    assert g.num_arcs == randg.size(), (
        "Graph size mismatch: %s vs. %s" % (g.num_arcs, randg.size()))
    M = randg.adjacency_matrix()
    cdef int *V = <int *>check_allocarray(n, sizeof(int))
    cdef int i = 0
    for v in randg.vertex_iterator():
        V[i] = v
        i += 1
    cdef int *seq = <int *>check_allocarray(n, sizeof(int))
    for i in range(randint(50, 101)):
        u = randint(low, n - 1)
        g.adjacency_sequence_out(n, V, u, seq)
        A = [seq[k] for k in range(n)]
        try:
            assert A == list(M[u])
        except AssertionError:
            sig_free(V)
            sig_free(seq)
            raise AssertionError("Graph adjacency mismatch")
    sig_free(seq)
    sig_free(V)

###########################################
# Sparse Graph Backend
###########################################

cdef class SparseGraphBackend(CGraphBackend):
    """
    Backend for Sage graphs using SparseGraphs.

    ::

        sage: from sage.graphs.base.sparse_graph import SparseGraphBackend

    This class is only intended for use by the Sage Graph and DiGraph class.
    If you are interested in using a SparseGraph, you probably want to do
    something like the following example, which creates a Sage Graph instance
    which wraps a SparseGraph object::

        sage: G = Graph(30, sparse=True)
        sage: G.add_edges([(0,1), (0,3), (4,5), (9, 23)])
        sage: G.edges(labels=False)
        [(0, 1), (0, 3), (4, 5), (9, 23)]

    Note that Sage graphs using the backend are more flexible than SparseGraphs
    themselves. This is because SparseGraphs (by design) do not deal with Python
    objects::

        sage: G.add_vertex((0,1,2))
        sage: sorted(list(G),
        ....:        key=lambda x: (isinstance(x, tuple), x))
        [0,
        ...
         29,
         (0, 1, 2)]
        sage: from sage.graphs.base.sparse_graph import SparseGraph
        sage: SG = SparseGraph(30)
        sage: SG.add_vertex((0,1,2))
        Traceback (most recent call last):
        ...
        TypeError: an integer is required

    """

    def __init__(self, int n, directed=True):
        """
        Initialize a sparse graph with n vertices.

        EXAMPLES::

            sage: D = sage.graphs.base.sparse_graph.SparseGraphBackend(9)
            sage: D.add_edge(0,1,None,False)
            sage: list(D.iterator_edges(range(9), True))
            [(0, 1, None)]

        """
        self._cg = SparseGraph(n, directed=directed)
        self._directed = directed
        self.vertex_labels = {}
        self.vertex_ints = {}
        self.edge_labels = {}
        self.edge_labels_max = 1
        self.edge_labels_available_ids = []

    cdef inline int new_edge_label(self, object l) except -1:
        """
        Returns a new unique int representing the arbitrary label l.
        """
        if l is None:
            return 0

        cdef int l_int
        if self.edge_labels_available_ids:
            l_int = self.edge_labels_available_ids.pop(-1)
        else:
            l_int = self.edge_labels_max
            self.edge_labels_max += 1

        self.edge_labels[l_int] = l
        return l_int

    def add_edge(self, object u, object v, object l, bint directed):
        """
        Add the edge ``(u,v)`` to self.

        INPUT:

         - ``u,v`` -- the vertices of the edge

         - ``l`` -- the edge label

         - ``directed`` -- if False, also add ``(v,u)``

        EXAMPLES::

            sage: D = sage.graphs.base.sparse_graph.SparseGraphBackend(9)
            sage: D.add_edge(0,1,None,False)
            sage: list(D.iterator_edges(range(9), True))
            [(0, 1, None)]

        TESTS::

            sage: D = DiGraph(sparse=True)
            sage: D.add_edge(0,1,2)
            sage: D.add_edge(0,1,3)
            sage: D.edges()
            [(0, 1, 3)]

        Check :trac:`22991`::

            sage: G = Graph(3, sparse=True)
            sage: G.add_edge(0,0)
            Traceback (most recent call last):
            ...
            ValueError: cannot add edge from 0 to 0 in graph without loops
            sage: G = Graph(3, sparse=True, loops=True)
            sage: G.add_edge(0,0); G.edges()
            [(0, 0, None)]

        Remove edges correctly when multiedges are not allowed (:trac:`28077`)::

            sage: D = DiGraph(multiedges=False)
            sage: D.add_edge(1, 2, 'A')
            sage: D.add_edge(1, 2, 'B')
            sage: D.delete_edge(1, 2)
            sage: D.incoming_edges(2)
            []
            sage: D.shortest_path(1, 2)
            []
        """
        if u is None: u = self.add_vertex(None)
        if v is None: v = self.add_vertex(None)

        cdef int u_int = self.check_labelled_vertex(u, False)
        cdef int v_int = self.check_labelled_vertex(v, False)

        cdef int l_int
        if l is None:
            l_int = 0
        else:
            l_int = self.new_edge_label(l)

        if u_int == v_int and not self._loops:
            raise ValueError(f"cannot add edge from {u!r} to {v!r} in graph without loops")

        if not self.multiple_edges(None):
            if self._cg.has_arc_label(u_int, v_int, l_int):
                return
            else:
                self._cg.del_all_arcs(u_int, v_int)
                if not directed and self._directed and v_int != u_int:
                    self._cg.del_all_arcs(v_int, u_int)

        self._cg.add_arc_label(u_int, v_int, l_int)
        if not directed and self._directed and v_int != u_int:
            self._cg.add_arc_label(v_int, u_int, l_int)

    def add_edges(self, object edges, bint directed):
        """
        Add edges from a list.

        INPUT:

         - ``edges`` -- the edges to be added; can either be of the form
           ``(u,v)`` or ``(u,v,l)``

         - ``directed`` -- if False, add ``(v,u)`` as well as ``(u,v)``

        EXAMPLES::

            sage: D = sage.graphs.base.sparse_graph.SparseGraphBackend(9)
            sage: D.add_edges([(0,1), (2,3), (4,5), (5,6)], False)
            sage: list(D.iterator_edges(range(9), True))
            [(0, 1, None),
             (2, 3, None),
             (4, 5, None),
             (5, 6, None)]

        """
        cdef object u,v,l,e
        for e in edges:
            try:
                u,v,l = e
            except Exception:
                u,v = e
                l = None
            self.add_edge(u,v,l,directed)

    def del_edge(self, object u, object v, object l, bint directed):
        """
        Delete edge ``(u,v,l)``.

        INPUT:

         - ``u,v`` -- the vertices of the edge

         - ``l`` -- the edge label

         - ``directed`` -- if False, also delete ``(v,u,l)``

        EXAMPLES::

            sage: D = sage.graphs.base.sparse_graph.SparseGraphBackend(9)
            sage: D.add_edges([(0,1), (2,3), (4,5), (5,6)], False)
            sage: list(D.iterator_edges(range(9), True))
            [(0, 1, None),
             (2, 3, None),
             (4, 5, None),
             (5, 6, None)]
            sage: D.del_edge(0,1,None,True)
            sage: list(D.iterator_out_edges(range(9), True))
            [(1, 0, None),
             (2, 3, None),
             (3, 2, None),
             (4, 5, None),
             (5, 4, None),
             (5, 6, None),
             (6, 5, None)]

        TESTS::

            sage: G = Graph(sparse=True)
            sage: G.add_edge(0,1,2)
            sage: G.delete_edge(0,1)
            sage: G.edges()
            []

            sage: G = Graph(multiedges=True, sparse=True)
            sage: G.add_edge(0,1,2)
            sage: G.add_edge(0,1,None)
            sage: G.delete_edge(0,1)
            sage: G.edges()
            [(0, 1, 2)]

        Do we remove loops correctly? (:trac:`12135`)::

            sage: g=Graph({0:[0,0,0]}, sparse=True)
            sage: g.edges(labels=False)
            [(0, 0), (0, 0), (0, 0)]
            sage: g.delete_edge(0,0); g.edges(labels=False)
            [(0, 0), (0, 0)]
        """
        if not ( self.has_vertex(u) and self.has_vertex(v) ):
            return
        cdef int u_int = self.check_labelled_vertex(u, False)
        cdef int v_int = self.check_labelled_vertex(v, False)

        if l is None:
            if self._cg.has_arc_label(u_int, v_int, 0):
                l_int = 0
            else:
                l_int = self._cg.arc_label(u_int, v_int)
        else:
            for l_int in self.edge_labels:
                if self.edge_labels[l_int] == l and self._cg.has_arc_label(u_int, v_int, l_int):
                    break
            else:
                return

        self._cg.del_arc_label(u_int, v_int, l_int)
        if not directed and self._directed and v_int != u_int:
            self._cg.del_arc_label(v_int, u_int, l_int)
        if l_int:
            self.edge_labels.pop(l_int)
            self.edge_labels_available_ids.append(l_int)

    def get_edge_label(self, object u, object v):
        """
        Returns the edge label for ``(u,v)``.

        INPUT:

         - ``u,v`` -- the vertices of the edge

        EXAMPLES::

            sage: D = sage.graphs.base.sparse_graph.SparseGraphBackend(9)
            sage: D.add_edges([(0,1,1), (2,3,2), (4,5,3), (5,6,2)], False)
            sage: list(D.iterator_edges(range(9), True))
            [(0, 1, 1), (2, 3, 2), (4, 5, 3), (5, 6, 2)]
            sage: D.get_edge_label(3,2)
            2

        """
        cdef int l_int
        if not self.has_vertex(u):
            raise LookupError("({0}) is not a vertex of the graph.".format(repr(u)))
        if not self.has_vertex(v):
            raise LookupError("({0}) is not a vertex of the graph.".format(repr(v)))
        cdef int u_int = self.get_vertex(u)
        cdef int v_int = self.get_vertex(v)
        if not self._cg.has_arc_unsafe(u_int, v_int):
            raise LookupError("({0}, {1}) is not an edge of the graph.".format(repr(u),repr(v)))
        if self.multiple_edges(None):
            return [self.edge_labels[l_int] if l_int != 0 else None
                     for l_int in self._cg.all_arcs(u_int, v_int)]
        l_int = self._cg.arc_label(u_int, v_int)
        return self.edge_labels[l_int] if l_int else None

    def has_edge(self, object u, object v, object l):
        """
        Returns whether this graph has edge ``(u,v)`` with label ``l``. If ``l``
        is ``None``, return whether this graph has an edge ``(u,v)`` with any
        label.

        INPUT:

         - ``u, v`` -- the vertices of the edge

         - ``l`` -- the edge label, or ``None``

        EXAMPLES::

            sage: D = sage.graphs.base.sparse_graph.SparseGraphBackend(9)
            sage: D.add_edges([(0,1), (2,3), (4,5), (5,6)], False)
            sage: D.has_edge(0,1,None)
            True

        """
        cdef int u_int = self.get_vertex_checked(u)
        cdef int v_int = self.get_vertex_checked(v)
        if u_int == -1 or v_int == -1:
            return False

        cdef SparseGraph cg = self.cg()
        if l is None:
            return 1 == cg.has_arc_unsafe(u_int, v_int)
        cdef SparseGraphLLNode* label = cg.arc_labels_unsafe(u_int, v_int)
        while label:
            if label.label and self.edge_labels[label.label] == l:
                return True
            label = label.next
        return False

    def multiple_edges(self, new):
        """
        Get/set whether or not ``self`` allows multiple edges.

        INPUT:

         - ``new`` -- boolean (to set) or ``None`` (to get)

        EXAMPLES::

            sage: G = sage.graphs.base.sparse_graph.SparseGraphBackend(9)
            sage: G.multiple_edges(True)
            sage: G.multiple_edges(None)
            True
            sage: G.multiple_edges(False)
            sage: G.multiple_edges(None)
            False
            sage: G.add_edge(0,1,0,True)
            sage: G.add_edge(0,1,0,True)
            sage: list(G.iterator_out_edges(range(9), True))
            [(0, 1, 0)]

        """
        if new is None:
            return self._multiple_edges
        self._multiple_edges = bool(new)

    def set_edge_label(self, object u, object v, object l, bint directed):
        """
        Label the edge ``(u,v)`` by ``l``.

        INPUT:

         - ``u,v`` -- the vertices of the edge

         - ``l`` -- the edge label

         - ``directed`` -- if ``False``, also set ``(v,u)`` with label ``l``

        EXAMPLES::

            sage: G = sage.graphs.base.sparse_graph.SparseGraphBackend(9)
            sage: G.add_edge(1,2,None,True)
            sage: G.set_edge_label(1,2,'a',True)
            sage: list(G.iterator_out_edges(range(9), True))
            [(1, 2, 'a')]

        Note that it fails silently if there is no edge there::

            sage: G.set_edge_label(2,1,'b',True)
            sage: list(G.iterator_out_edges(range(9), True))
            [(1, 2, 'a')]

        """
        if not self.has_edge(u, v, None):
            return
        if self.multiple_edges(None):
            if len(self.get_edge_label(u, v)) > 1:
                raise RuntimeError("Cannot set edge label, since there are multiple edges from %s to %s."%(u,v))
        # now we know there is exactly one edge from u to v
        cdef int l_int, ll_int
        if l is None:
            l_int = 0
        else:
            l_int = self.new_edge_label(l)
        cdef int u_int = self.get_vertex(u)
        cdef int v_int = self.get_vertex(v)
        if not (<SparseGraph>self._cg).has_arc_unsafe(u_int, v_int):
            return
        ll_int = (<SparseGraph>self._cg).arc_label_unsafe(u_int, v_int)
        if ll_int:
            self.edge_labels.pop(ll_int)
            self.edge_labels_available_ids.append(ll_int)
        self._cg.del_arc_label(u_int, v_int, ll_int)
        self._cg.add_arc_label(u_int, v_int, l_int)
        if not directed and self._directed and v_int != u_int:
            self._cg.del_arc_label(v_int, u_int, ll_int)
            self._cg.add_arc_label(v_int, u_int, l_int)
