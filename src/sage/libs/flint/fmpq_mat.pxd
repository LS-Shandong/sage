# distutils: libraries = flint
# distutils: depends = flint/fmpq_mat.h

################################################################################
# This file is auto-generated by the script
#   SAGE_ROOT/src/sage_setup/autogen/flint_autogen.py.
# From the commit 3e2c3a3e091106a25ca9c6fba28e02f2cbcd654a
# Do not modify by hand! Fix and rerun the script instead.
################################################################################

from libc.stdio cimport FILE
from sage.libs.gmp.types cimport *
from sage.libs.mpfr.types cimport *
from sage.libs.flint.types cimport *

cdef extern from "flint_wrap.h":
    void fmpq_mat_init(fmpq_mat_t mat, slong rows, slong cols) noexcept
    void fmpq_mat_init_set(fmpq_mat_t mat1, const fmpq_mat_t mat2) noexcept
    void fmpq_mat_clear(fmpq_mat_t mat) noexcept
    void fmpq_mat_swap(fmpq_mat_t mat1, fmpq_mat_t mat2) noexcept
    void fmpq_mat_swap_entrywise(fmpq_mat_t mat1, fmpq_mat_t mat2) noexcept
    fmpq * fmpq_mat_entry(const fmpq_mat_t mat, slong i, slong j) noexcept
    fmpz * fmpq_mat_entry_num(const fmpq_mat_t mat, slong i, slong j) noexcept
    fmpz * fmpq_mat_entry_den(const fmpq_mat_t mat, slong i, slong j) noexcept
    slong fmpq_mat_nrows(const fmpq_mat_t mat) noexcept
    slong fmpq_mat_ncols(const fmpq_mat_t mat) noexcept
    void fmpq_mat_set(fmpq_mat_t dest, const fmpq_mat_t src) noexcept
    void fmpq_mat_zero(fmpq_mat_t mat) noexcept
    void fmpq_mat_one(fmpq_mat_t mat) noexcept
    void fmpq_mat_transpose(fmpq_mat_t rop, const fmpq_mat_t op) noexcept
    void fmpq_mat_swap_rows(fmpq_mat_t mat, slong * perm, slong r, slong s) noexcept
    void fmpq_mat_swap_cols(fmpq_mat_t mat, slong * perm, slong r, slong s) noexcept
    void fmpq_mat_invert_rows(fmpq_mat_t mat, slong * perm) noexcept
    void fmpq_mat_invert_cols(fmpq_mat_t mat, slong * perm) noexcept
    void fmpq_mat_add(fmpq_mat_t mat, const fmpq_mat_t mat1, const fmpq_mat_t mat2) noexcept
    void fmpq_mat_sub(fmpq_mat_t mat, const fmpq_mat_t mat1, const fmpq_mat_t mat2) noexcept
    void fmpq_mat_neg(fmpq_mat_t rop, const fmpq_mat_t op) noexcept
    void fmpq_mat_scalar_mul_fmpq(fmpq_mat_t rop, const fmpq_mat_t op, const fmpq_t x) noexcept
    void fmpq_mat_scalar_mul_fmpz(fmpq_mat_t rop, const fmpq_mat_t op, const fmpz_t x) noexcept
    void fmpq_mat_scalar_div_fmpz(fmpq_mat_t rop, const fmpq_mat_t op, const fmpz_t x) noexcept
    void fmpq_mat_print(const fmpq_mat_t mat) noexcept
    void fmpq_mat_randbits(fmpq_mat_t mat, flint_rand_t state, flint_bitcnt_t bits) noexcept
    void fmpq_mat_randtest(fmpq_mat_t mat, flint_rand_t state, flint_bitcnt_t bits) noexcept
    void fmpq_mat_window_init(fmpq_mat_t window, const fmpq_mat_t mat, slong r1, slong c1, slong r2, slong c2) noexcept
    void fmpq_mat_window_clear(fmpq_mat_t window) noexcept
    void fmpq_mat_concat_vertical(fmpq_mat_t res, const fmpq_mat_t mat1, const fmpq_mat_t mat2) noexcept
    void fmpq_mat_concat_horizontal(fmpq_mat_t res, const fmpq_mat_t mat1, const fmpq_mat_t mat2) noexcept
    void fmpq_mat_hilbert_matrix(fmpq_mat_t mat) noexcept
    bint fmpq_mat_equal(const fmpq_mat_t mat1, const fmpq_mat_t mat2) noexcept
    bint fmpq_mat_is_integral(const fmpq_mat_t mat) noexcept
    bint fmpq_mat_is_zero(const fmpq_mat_t mat) noexcept
    bint fmpq_mat_is_one(const fmpq_mat_t mat) noexcept
    bint fmpq_mat_is_empty(const fmpq_mat_t mat) noexcept
    bint fmpq_mat_is_square(const fmpq_mat_t mat) noexcept
    int fmpq_mat_get_fmpz_mat(fmpz_mat_t dest, const fmpq_mat_t mat) noexcept
    void fmpq_mat_get_fmpz_mat_entrywise(fmpz_mat_t num, fmpz_mat_t den, const fmpq_mat_t mat) noexcept
    void fmpq_mat_get_fmpz_mat_matwise(fmpz_mat_t num, fmpz_t den, const fmpq_mat_t mat) noexcept
    void fmpq_mat_get_fmpz_mat_rowwise(fmpz_mat_t num, fmpz * den, const fmpq_mat_t mat) noexcept
    void fmpq_mat_get_fmpz_mat_rowwise_2(fmpz_mat_t num, fmpz_mat_t num2, fmpz * den, const fmpq_mat_t mat, const fmpq_mat_t mat2) noexcept
    void fmpq_mat_get_fmpz_mat_colwise(fmpz_mat_t num, fmpz * den, const fmpq_mat_t mat) noexcept
    void fmpq_mat_set_fmpz_mat(fmpq_mat_t dest, const fmpz_mat_t src) noexcept
    void fmpq_mat_set_fmpz_mat_div_fmpz(fmpq_mat_t mat, const fmpz_mat_t num, const fmpz_t den) noexcept
    void fmpq_mat_get_fmpz_mat_mod_fmpz(fmpz_mat_t dest, const fmpq_mat_t mat, const fmpz_t mod) noexcept
    int fmpq_mat_set_fmpz_mat_mod_fmpz(fmpq_mat_t X, const fmpz_mat_t Xmod, const fmpz_t mod) noexcept
    void fmpq_mat_mul_direct(fmpq_mat_t C, const fmpq_mat_t A, const fmpq_mat_t B) noexcept
    void fmpq_mat_mul_cleared(fmpq_mat_t C, const fmpq_mat_t A, const fmpq_mat_t B) noexcept
    void fmpq_mat_mul(fmpq_mat_t C, const fmpq_mat_t A, const fmpq_mat_t B) noexcept
    void fmpq_mat_mul_fmpz_mat(fmpq_mat_t C, const fmpq_mat_t A, const fmpz_mat_t B) noexcept
    void fmpq_mat_mul_r_fmpz_mat(fmpq_mat_t C, const fmpz_mat_t A, const fmpq_mat_t B) noexcept
    void fmpq_mat_mul_fmpq_vec(fmpq * c, const fmpq_mat_t A, const fmpq * b, slong blen) noexcept
    void fmpq_mat_mul_fmpz_vec(fmpq * c, const fmpq_mat_t A, const fmpz * b, slong blen) noexcept
    void fmpq_mat_mul_fmpq_vec_ptr(fmpq * const * c, const fmpq_mat_t A, const fmpq * const * b, slong blen) noexcept
    void fmpq_mat_mul_fmpz_vec_ptr(fmpq * const * c, const fmpq_mat_t A, const fmpz * const * b, slong blen) noexcept
    void fmpq_mat_fmpq_vec_mul(fmpq * c, const fmpq * a, slong alen, const fmpq_mat_t B) noexcept
    void fmpq_mat_fmpz_vec_mul(fmpq * c, const fmpz * a, slong alen, const fmpq_mat_t B) noexcept
    void fmpq_mat_fmpq_vec_mul_ptr(fmpq * const * c, const fmpq * const * a, slong alen, const fmpq_mat_t B) noexcept
    void fmpq_mat_fmpz_vec_mul_ptr(fmpq * const * c, const fmpz * const * a, slong alen, const fmpq_mat_t B) noexcept
    void fmpq_mat_kronecker_product(fmpq_mat_t C, const fmpq_mat_t A, const fmpq_mat_t B) noexcept
    void fmpq_mat_trace(fmpq_t trace, const fmpq_mat_t mat) noexcept
    void fmpq_mat_det(fmpq_t det, const fmpq_mat_t mat) noexcept
    int fmpq_mat_solve_fraction_free(fmpq_mat_t X, const fmpq_mat_t A, const fmpq_mat_t B) noexcept
    int fmpq_mat_solve_dixon(fmpq_mat_t X, const fmpq_mat_t A, const fmpq_mat_t B) noexcept
    int fmpq_mat_solve_multi_mod(fmpq_mat_t X, const fmpq_mat_t A, const fmpq_mat_t B) noexcept
    int fmpq_mat_solve(fmpq_mat_t X, const fmpq_mat_t A, const fmpq_mat_t B) noexcept
    int fmpq_mat_solve_fmpz_mat_fraction_free(fmpq_mat_t X, const fmpz_mat_t A, const fmpz_mat_t B) noexcept
    int fmpq_mat_solve_fmpz_mat_dixon(fmpq_mat_t X, const fmpz_mat_t A, const fmpz_mat_t B) noexcept
    int fmpq_mat_solve_fmpz_mat_multi_mod(fmpq_mat_t X, const fmpz_mat_t A, const fmpz_mat_t B) noexcept
    int fmpq_mat_solve_fmpz_mat(fmpq_mat_t X, const fmpz_mat_t A, const fmpz_mat_t B) noexcept
    int fmpq_mat_can_solve_multi_mod(fmpq_mat_t X, const fmpq_mat_t A, const fmpq_mat_t B) noexcept
    int fmpq_mat_can_solve_fraction_free(fmpq_mat_t X, const fmpq_mat_t A, const fmpq_mat_t B) noexcept
    int fmpq_mat_can_solve(fmpq_mat_t X, const fmpq_mat_t A, const fmpq_mat_t B) noexcept
    int fmpq_mat_inv(fmpq_mat_t B, const fmpq_mat_t A) noexcept
    int fmpq_mat_pivot(slong * perm, fmpq_mat_t mat, slong r, slong c) noexcept
    slong fmpq_mat_rref_classical(fmpq_mat_t B, const fmpq_mat_t A) noexcept
    slong fmpq_mat_rref_fraction_free(fmpq_mat_t B, const fmpq_mat_t A) noexcept
    slong fmpq_mat_rref(fmpq_mat_t B, const fmpq_mat_t A) noexcept
    void fmpq_mat_gso(fmpq_mat_t B, const fmpq_mat_t A) noexcept
    void fmpq_mat_similarity(fmpq_mat_t A, slong r, fmpq_t d) noexcept
    void _fmpq_mat_charpoly(fmpz * coeffs, fmpz_t den, const fmpq_mat_t mat) noexcept
    void fmpq_mat_charpoly(fmpq_poly_t pol, const fmpq_mat_t mat) noexcept
    slong _fmpq_mat_minpoly(fmpz * coeffs, fmpz_t den, const fmpq_mat_t mat) noexcept
    void fmpq_mat_minpoly(fmpq_poly_t pol, const fmpq_mat_t mat) noexcept

from .fmpq_mat_macros cimport *
