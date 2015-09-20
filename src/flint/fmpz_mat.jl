###############################################################################
#
#   fmpz_mat.jl : Flint matrices over fmpz
#
###############################################################################

export fmpz_mat, FmpzMatSpace, getindex, getindex!, setindex!, rows, cols,
       charpoly, determinant, determinant_divisor, determinant_given_divisor,
       gram, hadamard, is_hadamard, hnf, is_hnf, hnf_with_transform,
       hnf_modular, lll, lll_gram, lll_with_transform, lll_gram_with_transform,
       lll_with_removal, lll_with_removal_transform,
       nullspace, rank, rref, reduce_mod, snf, snf_diagonal, is_snf, solve,
       solve_dixon, trace, transpose, content, hcat, vcat, addmul!, zero!,
       window

###############################################################################
#
#   Data type and parent object methods
#
###############################################################################

elem_type(::FmpzMatSpace) = fmpz_mat

base_ring(a::FmpzMatSpace) = a.base_ring

parent(a::fmpz_mat) = a.parent

function check_parent(a::fmpz_mat, b::fmpz_mat)
   parent(a) != parent(b) && error("Incompatible moduli in residue operation")
end

###############################################################################
#
#   Windows - handle with care!!!
#
###############################################################################

function window(x::fmpz_mat, r1::Int, c1::Int, r2::Int, c2::Int)
  _checkbounds(x.r, r1) || throw(BoundsError())
  _checkbounds(x.r, r2) || throw(BoundsError())
  _checkbounds(x.c, c1) || throw(BoundsError())
  _checkbounds(x.c, c2) || throw(BoundsError())
  (r1 > r2 || c1 > c2) && error("Invalid parameters")  
  b = fmpz_mat()
  b.parent = MatrixSpace(parent(x).base_ring, r2 - r1 + 1, c2 - c1 + 1)
  ccall((:fmpz_mat_window_init, :libflint), Void, 
        (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Int, Int, Int, Int),
            &b, &x, r1-1, c1-1, r2, c2)
  finalizer(b, _fmpz_mat_window_clear_fn)
  return b
end

function window(x::fmpz_mat, r::UnitRange{Int}, c::UnitRange{Int})
  return window(x, r.start, c.start, r.stop, c.stop)
end

function _fmpz_mat_window_clear_fn(a::fmpz_mat)
   ccall((:fmpz_mat_window_clear, :libflint), Void, (Ptr{fmpz_mat},), &a)
end

size(x::fmpz_mat) = tuple(x.parent.rows, x.parent.cols)

size(t::fmpz_mat, d) = d <= 2 ? size(t)[d] : 1

###############################################################################
#
#   Basic manipulation
#
###############################################################################

function hash(a::fmpz_mat)
   h = 0xb14b9caecfda49af
   for i in 1:rows(a)
      for j in 1:cols(a)
         h $= hash(getindex(a, i, j))
         h = (h << 1) | (h >> (sizeof(Int)*8 - 1))
      end
   end
   return h
end

function getindex!(v::fmpz, a::fmpz_mat, r::Int, c::Int)
   z = ccall((:fmpz_mat_entry, :libflint), Ptr{fmpz},
             (Ptr{fmpz_mat}, Int, Int), &a, r - 1, c - 1)
   ccall((:fmpz_set, :libflint), Void, (Ptr{fmpz}, Ptr{fmpz}), &v, z)
end
 
function getindex(a::fmpz_mat, r::Int, c::Int)
   _checkbounds(a.parent.rows, r) || throw(BoundsError())
   _checkbounds(a.parent.cols, c) || throw(BoundsError())
   v = fmpz()
   z = ccall((:fmpz_mat_entry, :libflint), Ptr{fmpz},
             (Ptr{fmpz_mat}, Int, Int), &a, r - 1, c - 1)
   ccall((:fmpz_set, :libflint), Void, (Ptr{fmpz}, Ptr{fmpz}), &v, z)
   return v
end
 
function setindex!(a::fmpz_mat, d::fmpz, r::Int, c::Int)
   z = ccall((:fmpz_mat_entry, :libflint), Ptr{fmpz},
             (Ptr{fmpz_mat}, Int, Int), &a, r - 1, c - 1)
   ccall((:fmpz_set, :libflint), Void, (Ptr{fmpz}, Ptr{fmpz}), z, &d)
end

setindex!(a::fmpz_mat, d::Integer, r::Int, c::Int) = setindex!(a, fmpz(d), r, c)

function setindex!(a::fmpz_mat, d::Int, r::Int, c::Int)
   _checkbounds(a.parent.rows, r) || throw(BoundsError())
   _checkbounds(a.parent.cols, c) || throw(BoundsError())
   z = ccall((:fmpz_mat_entry, :libflint), Ptr{fmpz},
             (Ptr{fmpz_mat}, Int, Int), &a, r - 1, c - 1)
   ccall((:fmpz_set_si, :libflint), Void, (Ptr{fmpz}, Int), z, d)
end

rows(a::fmpz_mat) = a.r

cols(a::fmpz_mat) = a.c

zero(a::FmpzMatSpace) = a()

one(a::FmpzMatSpace) = a(1)

iszero(a::fmpz_mat) = ccall((:fmpz_mat_is_zero, :libflint), Bool, 
                            (Ptr{fmpz_mat},), &a)

isone(a::fmpz_mat) = ccall((:fmpz_mat_is_one, :libflint), Bool, 
                           (Ptr{fmpz_mat},), &a)

function deepcopy(d::fmpz_mat)
   z = fmpz_mat(d)
   z.parent = d.parent
   return z
end

###############################################################################
#
#   Canonicalisation
#
###############################################################################

canonical_unit(a::fmpz_mat) = canonical_unit(a[1, 1])

###############################################################################
#
#   AbstractString{} I/O
#
###############################################################################

function show(io::IO, a::FmpzMatSpace)
   print(io, "Matrix Space of ")
   print(io, a.rows, " rows and ", a.cols, " columns over ")
   print(io, "Integer Ring")
end

function show(io::IO, a::fmpz_mat)
   rows = a.parent.rows
   cols = a.parent.cols
   for i = 1:rows
      print(io, "[")
      for j = 1:cols
         print(io, a[i, j])
         if j != cols
            print(io, " ")
         end
      end
      print(io, "]")
      if i != rows
         println(io, "")
      end
   end
end

show_minus_one(::Type{fmpz_mat}) = show_minus_one(fmpz)

###############################################################################
#
#   Unary operations
#
###############################################################################

function -(x::fmpz_mat)
   z = parent(x)()
   ccall((:fmpz_mat_neg, :libflint), Void, 
         (Ptr{fmpz_mat}, Ptr{fmpz_mat}), &z, &x)
   return z
end

###############################################################################
#
#   transpose
#
###############################################################################

function transpose(x::fmpz_mat)
   z = MatrixSpace(FlintZZ, cols(x), rows(x))()
   ccall((:fmpz_mat_transpose, :libflint), Void,
         (Ptr{fmpz_mat}, Ptr{fmpz_mat}), &z, &x)
   return z
end

###############################################################################
#
#   Binary operations
#
###############################################################################

function +(x::fmpz_mat, y::fmpz_mat)
   check_parent(x, y)
   z = parent(x)()
   ccall((:fmpz_mat_add, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat},  Ptr{fmpz_mat}), 
               &z, &x, &y)
   return z
end

function -(x::fmpz_mat, y::fmpz_mat)
   check_parent(x, y)
   z = parent(x)()
   ccall((:fmpz_mat_sub, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat},  Ptr{fmpz_mat}), 
               &z, &x, &y)
   return z
end

function *(x::fmpz_mat, y::fmpz_mat)
   cols(x) != rows(y) && error("Incompatible matrix dimensions")
   if rows(x) == cols(y) && rows(x) == cols(x)
      parz = parent(x)
   else
      parz = FmpzMatSpace(rows(x), cols(y))
   end
   z = parz()
   ccall((:fmpz_mat_mul, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat},  Ptr{fmpz_mat}), 
               &z, &x, &y)
   return z
end

###############################################################################
#
#   Ad hoc binary operators
#
###############################################################################

function *(x::Int, y::fmpz_mat)
   z = parent(y)()
   ccall((:fmpz_mat_scalar_mul_si, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Int), &z, &y, x)
   return z
end

function *(x::fmpz, y::fmpz_mat)
   z = parent(y)()
   ccall((:fmpz_mat_scalar_mul_fmpz, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz}), &z, &y, &x)
   return z
end

*(x::fmpz_mat, y::Int) = y*x

*(x::fmpz_mat, y::fmpz) = y*x

*(x::Integer, y::fmpz_mat) = fmpz(x)*y

*(x::fmpz_mat, y::Integer) = fmpz(y)*x

function +(x::fmpz_mat, y::Integer)
   z = deepcopy(x)
   for i = 1:min(rows(x), cols(x))
      z[i, i] += y
   end
   return z
end

+(x::Integer, y::fmpz_mat) = y + x

function -(x::fmpz_mat, y::Integer)
   z = deepcopy(x)
   for i = 1:min(rows(x), cols(x))
      z[i, i] -= y
   end
   return z
end

function -(x::Integer, y::fmpz_mat)
   z = -y
   for i = 1:min(rows(y), cols(y))
      z[i, i] += x
   end
   return z
end

###############################################################################
#
#   Scaling
#
###############################################################################

function <<(x::fmpz_mat, y::Int)
   y < 0 && throw(DomainError())
   z = parent(x)()
   ccall((:fmpz_mat_scalar_mul_2exp, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Int), 
               &z, &x, y)
   return z
end

function >>(x::fmpz_mat, y::Int)
   y < 0 && throw(DomainError())
   z = parent(x)()
   ccall((:fmpz_mat_scalar_tdiv_q_2exp, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Int), 
               &z, &x, y)
   return z
end

###############################################################################
#
#   Powering
#
###############################################################################

function ^(x::fmpz_mat, y::Int)
   y < 0 && throw(DomainError())
   rows(x) != cols(x) && error("Incompatible matrix dimensions")
   z = parent(x)()
   ccall((:fmpz_mat_pow, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Int), 
               &z, &x, y)
   return z
end

###############################################################################
#
#   Comparisons
#
###############################################################################

function ==(x::fmpz_mat, y::fmpz_mat)
   check_parent(x, y)
   ccall((:fmpz_mat_equal, :libflint), Bool, 
                                       (Ptr{fmpz_mat}, Ptr{fmpz_mat}), &x, &y)
end

###############################################################################
#
#   Ad hoc comparisons
#
###############################################################################

function ==(x::fmpz_mat, y::Integer) 
   for i = 1:min(rows(x), cols(x))
      if x[i, i] != y
         return false
      end
   end
   for i = 1:rows(x)
      for j = 1:cols(x)
         if i != j && x[i, j] != 0
            return false
         end
      end
   end
   return true
end

==(x::Integer, y::fmpz_mat) = y == x

###############################################################################
#
#   Inversion
#
###############################################################################

function inv(x::fmpz_mat)
   z = parent(x)()
   d = fmpz()
   ccall((:fmpz_mat_inv, :libflint), Void, 
         (Ptr{fmpz_mat}, Ptr{fmpz}, Ptr{fmpz_mat}), &z, &d, &x)
   if d == 1
      return z
   end
   if d == -1
      return -z
   end
   error("Matrix not invertible")
end

###############################################################################
#
#   Exact division
#
###############################################################################

function divexact(x::fmpz_mat, y::fmpz_mat)
   cols(x) != cols(y) && error("Incompatible matrix dimensions")
   x*inv(y)
end

###############################################################################
#
#   Ad hoc exact division
#
###############################################################################

function divexact(x::fmpz_mat, y::Int)
   z = parent(x)()
   ccall((:fmpz_mat_scalar_divexact_si, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Int), &z, &x, y)
   return z
end

function divexact(x::fmpz_mat, y::fmpz)
   z = parent(x)()
   ccall((:fmpz_mat_scalar_divexact_fmpz, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz}), &z, &x, &y)
   return z
end

divexact(x::fmpz_mat, y::Integer) = divexact(x, fmpz(y))

###############################################################################
#
#   Modular reduction
#
###############################################################################

function reduce_mod(x::fmpz_mat, y::fmpz)
   z = parent(x)()
   ccall((:fmpz_mat_scalar_mod_fmpz, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz}), &z, &x, &y)
   return z
end

reduce_mod(x::fmpz_mat, y::Integer) = reduce_mod(x, fmpz(y))

###############################################################################
#
#   Characteristic polynomial
#
###############################################################################

function charpoly(R::FmpzPolyRing, x::fmpz_mat)
   rows(x) != cols(x) && error("Non-square")
   z = R()
   ccall((:fmpz_mat_charpoly, :libflint), Void, 
                (Ptr{fmpz_poly}, Ptr{fmpz_mat}), &z, &x)
   return z
end

###############################################################################
#
#   Determinant
#
###############################################################################

function determinant(x::fmpz_mat)
   rows(x) != cols(x) && error("Non-square matrix")
   z = fmpz()
   ccall((:fmpz_mat_det, :libflint), Void, 
                (Ptr{fmpz}, Ptr{fmpz_mat}), &z, &x)
   return z
end

function determinant_divisor(x::fmpz_mat)
   rows(x) != cols(x) && error("Non-square matrix")
   z = fmpz()
   ccall((:fmpz_mat_det_divisor, :libflint), Void, 
                (Ptr{fmpz}, Ptr{fmpz_mat}), &z, &x)
   return z
end

function determinant_given_divisor(x::fmpz_mat, d::fmpz, proved=true)
   rows(x) != cols(x) && error("Non-square")
   z = fmpz()
   ccall((:fmpz_mat_det_modular_given_divisor, :libflint), Void, 
               (Ptr{fmpz}, Ptr{fmpz_mat}, Ptr{fmpz}, Cint), &z, &x, &d, proved)
   return z
end

function determinant_given_divisor(x::fmpz_mat, d::Integer, proved=true)
   return determinant_given_divisor(x, fmpz(d), proved)
end

###############################################################################
#
#   Gram matrix
#
###############################################################################

function gram(x::fmpz_mat)
   if rows(x) == cols(x)
      parz = parent(x)
   else
      parz = FmpzMatSpace(rows(x), rows(x))
   end
   z = parz()   
   ccall((:fmpz_mat_gram, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}), &z, &x)
   return z
end

###############################################################################
#
#   Hadamard matrix
#
###############################################################################

function hadamard(R::FmpzMatSpace)
   R.rows != R.cols && error("Unable to create Hadamard matrix")
   z = R()
   success = ccall((:fmpz_mat_hadamard, :libflint), Bool, 
                   (Ptr{fmpz_mat},), &z)
   !success && error("Unable to create Hadamard matrix")
   return z
end

function is_hadamard(x::fmpz_mat)
   return ccall((:fmpz_mat_is_hadamard, :libflint), Bool, 
                   (Ptr{fmpz_mat},), &x)
end

###############################################################################
#
#   Hermite normal form
#
###############################################################################

function hnf(x::fmpz_mat)
   z = parent(x)()
   ccall((:fmpz_mat_hnf, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}), &z, &x)
   return z
end

function hnf_with_transform(x::fmpz_mat)
   z = parent(x)()
   if rows(x) == cols(x)
      parz = parent(x)
   else
      parz = FmpzMatSpace(rows(x), rows(x))
   end
   u = parz()
   ccall((:fmpz_mat_hnf_transform, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz_mat}), &z, &u, &x)
   return z, u
end

function hnf_modular(x::fmpz_mat, d::fmpz)
   z = parent(x)()
   ccall((:fmpz_mat_hnf_modular, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz}), &z, &x, &d)
   return z
end

function is_hnf(x::fmpz_mat)
   return ccall((:fmpz_mat_is_in_hnf, :libflint), Bool, 
                   (Ptr{fmpz_mat},), &x)
end

###############################################################################
#
#   LLL
#
###############################################################################

type lll_ctx
   delta::Float64
   eta::Float64
   rep_type::Int
   gram_type::Int

   function lll_ctx(delta::Float64, eta::Float64, rep=:zbasis, gram=:approx) 
      rt = rep == :zbasis ? 1 : 0
      gt = gram == :approx ? 0 : 1
      return new(delta, eta, rt, gt)
   end
end


function lll_with_transform(x::fmpz_mat, ctx=lll_ctx(0.99, 0.51))
   z = deepcopy(x)
   if rows(x) == cols(x)
      parz = parent(x)
   else
      parz = FmpzMatSpace(rows(x), rows(x))
   end
   u = parz(1)
   ccall((:fmpz_lll, :libflint), Void, 
         (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{lll_ctx}), &z, &u, &ctx)
   return z, u
end

function lll(x::fmpz_mat, ctx=lll_ctx(0.99, 0.51))
   z = deepcopy(x)
   if rows(x) == cols(x)
      parz = parent(x)
   else
      parz = FmpzMatSpace(rows(x), rows(x))
   end
   u = parz(1)
   ccall((:fmpz_lll, :libflint), Void, 
         (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{lll_ctx}), &z, &u, &ctx)
   return z
end

function lll_gram_with_transform(x::fmpz_mat, ctx=lll_ctx(0.99, 0.51, :gram))
   z = deepcopy(x)
   if rows(x) == cols(x)
      parz = parent(x)
   else
      parz = FmpzMatSpace(rows(x), rows(x))
   end
   u = parz(1)
   ccall((:fmpz_lll, :libflint), Void, 
         (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{lll_ctx}), &z, &u, &ctx)
   return z, u
end

function lll_gram(x::fmpz_mat, ctx=lll_ctx(0.99, 0.51, :gram))
   z = deepcopy(x)
   if rows(x) == cols(x)
      parz = parent(x)
   else
      parz = FmpzMatSpace(rows(x), rows(x))
   end
   u = parz(1)
   ccall((:fmpz_lll, :libflint), Void, 
         (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{lll_ctx}), &z, &u, &ctx)
   return z
end

function lll_with_removal_transform(x::fmpz_mat, b::fmpz, ctx=lll_ctx(0.99, 0.51))
   z = deepcopy(x)
   if rows(x) == cols(x)
      parz = parent(x)
   else
      parz = FmpzMatSpace(rows(x), rows(x))
   end
   u = parz(1)
   d = Int(ccall((:fmpz_lll_with_removal, :libflint), Cint, 
    (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz}, Ptr{lll_ctx}), &z, &u, &b, &ctx))
   return d, z, u
end

function lll_with_removal(x::fmpz_mat, b::fmpz, ctx=lll_ctx(0.99, 0.51))
   z = deepcopy(x)
   if rows(x) == cols(x)
      parz = parent(x)
   else
      parz = FmpzMatSpace(rows(x), rows(x))
   end
   u = parz(1)
   d = Int(ccall((:fmpz_lll_with_removal, :libflint), Cint, 
    (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz}, Ptr{lll_ctx}), &z, &u, &b, &ctx))
   return d, z
end

###############################################################################
#
#   Nullspace
#
###############################################################################

function nullspace(x::fmpz_mat)
   z = parent(x)()
   if rows(x) == cols(x)
      parz = parent(x)
   else
      parz = FmpzMatSpace(cols(x), cols(x))
   end
   u = parz()
   rank = ccall((:fmpz_mat_nullspace, :libflint), Cint, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}), &u, &x)
   return u, rank
end

###############################################################################
#
#   Rank
#
###############################################################################

function rank(x::fmpz_mat)
   return ccall((:fmpz_mat_rank, :libflint), Int, 
                (Ptr{fmpz_mat},), &x)
end

###############################################################################
#
#   Reduced row echelon form
#
###############################################################################

function rref(x::fmpz_mat)
   z = parent(x)()
   d = fmpz()
   ccall((:fmpz_mat_rref, :libflint), Void,
         (Ptr{fmpz_mat}, Ptr{fmpz}, Ptr{fmpz_mat}), &z, &d, &x)
   return z, d
end

###############################################################################
#
#   Smith normal form
#
###############################################################################

function snf(x::fmpz_mat)
   z = parent(x)()
   ccall((:fmpz_mat_snf, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}), &z, &x)
   return z
end

function snf_diagonal(x::fmpz_mat)
   z = parent(x)()
   ccall((:fmpz_mat_snf_diagonal, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}), &z, &x)
   return z
end

function is_snf(x::fmpz_mat)
   return ccall((:fmpz_mat_is_in_snf, :libflint), Bool, 
                   (Ptr{fmpz_mat},), &x)
end

###############################################################################
#
#   Linear solving
#
###############################################################################

function solve(a::fmpz_mat, b::fmpz_mat)
   rows(a) != cols(a) && error("Not a square matrix in solve")
   rows(b) != rows(a) || cols(b) != 1 && ("Not a column vector in solve")
   z = parent(b)()
   d = fmpz()
   nonsing = ccall((:fmpz_mat_solve, :libflint), Bool,
      (Ptr{fmpz_mat}, Ptr{fmpz}, Ptr{fmpz_mat}, Ptr{fmpz_mat}), &z, &d, &a, &b)
   !nonsing && error("Singular matrix in solve")
   return z, d
end

function solve_dixon(a::fmpz_mat, b::fmpz_mat)
   rows(a) != cols(a) && error("Not a square matrix in solve")
   rows(b) != rows(a) || cols(b) != 1 && ("Not a column vector in solve")
   z = parent(b)()
   d = fmpz()
   nonsing = ccall((:fmpz_mat_solve_dixon, :libflint), Bool,
      (Ptr{fmpz_mat}, Ptr{fmpz}, Ptr{fmpz_mat}, Ptr{fmpz_mat}), &z, &d, &a, &b)
   !nonsing && error("Singular matrix in solve")
   return z, d
end

###############################################################################
#
#   Trace
#
###############################################################################

function trace(x::fmpz_mat)
   rows(x) != cols(x) && error("Not a square matrix in trace")
   d = fmpz()
   ccall((:fmpz_mat_trace, :libflint), Int, 
                (Ptr{fmpz}, Ptr{fmpz_mat}), &d, &x)
   return d
end

###############################################################################
#
#   Content
#
###############################################################################

function content(x::fmpz_mat)
  d = fmpz()
  ccall((:fmpz_mat_content, :libflint), Void, 
        (Ptr{fmpz}, Ptr{fmpz_mat}), &d, &x)
  return d
end

###############################################################################
#
#   Concatenation
#
###############################################################################

function hcat(a::fmpz_mat, b::fmpz_mat)
  rows(a) != rows(b) && error("Incompatible number of rows in hcat")
  c = MatrixSpace(FlintZZ, rows(a), cols(a) + cols(b))()
  ccall((:fmpz_mat_concat_horizontal, :libflint), Void, 
        (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz_mat}), &c, &a, &b)
  return c
end

function vcat(a::fmpz_mat, b::fmpz_mat)
  cols(a) != cols(b) && error("Incompatible number of columns in vcat")
  c = MatrixSpace(FlintZZ, rows(a) + rows(b), cols(a))()
  ccall((:fmpz_mat_concat_vertical, :libflint), Void, 
        (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz_mat}), &c, &a, &b)
  return c
end

###############################################################################
#
#   Unsafe functions
#
###############################################################################

function mul!(z::fmpz_mat, x::fmpz_mat, y::fmpz_mat)
   ccall((:fmpz_mat_mul, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz_mat}), &z, &x, &y)
end

function mul!(y::fmpz_mat, x::Int)
   ccall((:fmpz_mat_scalar_mul_si, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Int), &y, &y, x)
   return y
end

function mul!(y::fmpz_mat, x::fmpz)
   ccall((:fmpz_mat_scalar_mul_fmpz, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz}), &y, &y, &x)
   return y
end

function addmul!(z::fmpz_mat, y::fmpz_mat, x::fmpz)
   ccall((:fmpz_mat_scalar_addmul_fmpz, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz}), &z, &y, &x)
   return y
end

function addmul!(z::fmpz_mat, y::fmpz_mat, x::Int)
   ccall((:fmpz_mat_scalar_addmul_si, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Int), &z, &y, x)
   return y
end

function addeq!(z::fmpz_mat, x::fmpz_mat)
   ccall((:fmpz_mat_add, :libflint), Void, 
                (Ptr{fmpz_mat}, Ptr{fmpz_mat}, Ptr{fmpz_mat}), &z, &z, &x)
end

function zero!(z::fmpz_mat)
   ccall((:fmpz_mat_zero, :libflint), Void, 
                (Ptr{fmpz_mat},), &z)
end                

###############################################################################
#
#   Parent object call overloads
#
###############################################################################

function Base.call(a::FmpzMatSpace)
   z = fmpz_mat(a.rows, a.cols)
   z.parent = a
   return z
end

function Base.call(a::FmpzMatSpace, arr::Array{fmpz, 2})
   z = fmpz_mat(a.rows, a.cols, arr)
   z.parent = a
   return z
end

function Base.call{T <: Integer}(a::FmpzMatSpace, arr::Array{T, 2})
   z = fmpz_mat(a.rows, a.cols, arr)
   z.parent = a
   return z
end

Base.call(a::FmpzMatSpace, arr::Array{fmpz, 1}) = a(arr'')

Base.call{T <: Integer}(a::FmpzMatSpace, arr::Array{T, 1}) = a(arr'')

function Base.call(a::FmpzMatSpace, d::fmpz)
   z = fmpz_mat(a.rows, a.cols, d)
   z.parent = a
   return z
end

function Base.call(a::FmpzMatSpace, d::Integer)
   z = fmpz_mat(a.rows, a.cols, fmpz(d))
   z.parent = a
   return z
end

Base.call(a::FmpzMatSpace, d::fmpz_mat) = d

###############################################################################
#
#   Promotions
#
###############################################################################

Base.promote_rule{T <: Integer}(::Type{fmpz_mat}, ::Type{T}) = fmpz_mat

Base.promote_rule(::Type{fmpz_mat}, ::Type{fmpz}) = fmpz_mat

###############################################################################
#
#   MatrixSpace constructor
#
###############################################################################

function MatrixSpace(R::FlintIntegerRing, r::Int, c::Int)
   return FmpzMatSpace(r, c)
end
