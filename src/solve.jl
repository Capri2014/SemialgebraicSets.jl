export algebraicsolver, ReorderedSchurMultiplicationMatricesSolver

"""
    AbstractAlgebraicSolver

Solver of algebraic equations.
"""
abstract type AbstractAlgebraicSolver end

"""
    solvealgebraicequations(V::AbstractAlgebraicSet, algo::AbstractAlgebraicSolver)::Nullable{Vector{<:Vector}}

Solve the algebraic equations for which `V` is the set of solutions using the algorithm `algo`.
Returns a nullable which is `null` if `V` is not zero-dimensional and is the list of solutions otherwise.
"""
solvealgebraicequations(V::AbstractAlgebraicSet) = solvealgebraicequations(V, defaultalgebraicsolver(V))

"""
    AbstractMultiplicationMatricesAlgorithm

Algorithm computing multiplication matrices from algebraic equations.
"""
abstract type AbstractMultiplicationMatricesAlgorithm end

"""
    multiplicationmatrices(V::AbstractAlgebraicSet, algo::AbstractMultiplicationMatricesAlgorithm)::Nullable{Vector{<:AbstractMatrix}}

Computing multiplication matrices from the algebraic equations for which `V` is the set of solution using the algorithm `algo`.
Returns a nullable which is `null` if `V` is not zero-dimensional and is the list of multiplication matrices otherwise.
"""
function multiplicationmatrices end

"""
    AbstractMultiplicationMatricesSolver

Solver of algebraic equations using multiplication matrices.
"""
abstract type AbstractMultiplicationMatricesSolver end

"""
    solvemultiplicationmatrices(Ms::AbstractVector{<:AbstractMatrix{T}}, algo::AbstractMultiplicationMatricesSolver)::Vector{Vector{T}} where T

Solve the algebraic equations having multiplication matrices `Ms` using the algorithm `algo`.
Returns the list of solutions.
"""
function solvemultiplicationmatrices end


struct SolverUsingMultiplicationMatrices{A<:AbstractMultiplicationMatricesAlgorithm, S<:AbstractMultiplicationMatricesSolver} <: AbstractAlgebraicSolver
    algo::A
    solver::S
end

function solvealgebraicequations(V::AbstractAlgebraicSet, solver::SolverUsingMultiplicationMatrices)::Nullable{Vector{eltype(V)}}
    Ms = multiplicationmatrices(V, solver.algo)
    if isnull(Ms)
        nothing
    else
        solvemultiplicationmatrices(get(Ms), solver.solver)
    end
end

struct GröbnerBasisMultiplicationMatricesAlgorithm <: AbstractMultiplicationMatricesAlgorithm
end

function multiplicationmatrix(V::AbstractAlgebraicSet, v::AbstractVariable, B)
    M = Matrix{eltype(eltype(V))}(length(B), length(B))
    for i in 1:length(B)
        p = rem(v * B[i], equalities(V))
        M[:, i] = coefficients(p, B)
    end
    M
end

function multiplicationmatrices(V::AbstractAlgebraicSet, algo::GröbnerBasisMultiplicationMatricesAlgorithm)::Nullable{Vector{AbstractMatrix{eltype(eltype(V))}}}
    iszd, B = monomialbasis(V.I)
    if !iszd
        nothing
    else
        vs = variables(B)
        n = length(vs)
        if iszero(n)
            Matrix{eltype(eltype(T))}[]
        else
            [multiplicationmatrix(V, v, B) for v in vs]
        end
    end
end



"""
Corless, R. M.; Gianni, P. M. & Trager, B. M. A reordered Schur factorization method for zero-dimensional polynomial systems with multiple roots Proceedings of the 1997 international symposium on Symbolic and algebraic computation, 1997, 133-140
"""
struct ReorderedSchurMultiplicationMatricesSolver{T} <: AbstractMultiplicationMatricesSolver
    atol::T
    rtol::T
    ztol::T
end
ReorderedSchurMultiplicationMatricesSolver(ɛ) = ReorderedSchurMultiplicationMatricesSolver(ɛ, ɛ, ɛ)
# Example 5.2 and 5.3 of CGT97 in tests may fail if we do not multiply by 16.
# This is a sign that we need to improve the clustering but for new let's just multiply by 16 by default.
ReorderedSchurMultiplicationMatricesSolver() = ReorderedSchurMultiplicationMatricesSolver(Base.rtoldefault(Float64) * 16)

function solvemultiplicationmatrices(Ms::AbstractVector{<:AbstractMatrix{T}}, solver::ReorderedSchurMultiplicationMatricesSolver) where T
    λ = rand(length(Ms))
    λ /= sum(λ)
    _solvemultiplicationmatrices(Ms, λ, solver)
end

# Deterministic part
function _solvemultiplicationmatrices(Ms::AbstractVector{<:AbstractMatrix{T}}, λ, solver::ReorderedSchurMultiplicationMatricesSolver) where T
    @assert length(Ms) == length(λ)
    n = length(λ)
    M = sum(λ .* Ms)
    sf = schurfact(M)
    # M = Z * T * Z' and "values" gives the eigenvalues
    Z = sf[:Z]
    v = sf[:values]
    # Clustering
    clusters = Vector{Int}[]
    λavg = eltype(v)[]
    for i in eachindex(v)
        k = 0
        best = zero(Base.promote_op(abs, eltype(v)))
        for j in eachindex(clusters)
            if isapprox(v[i], λavg[j]; atol=solver.atol, rtol=solver.rtol)
                d = abs(v[i] - λavg[j])
                if iszero(k) || d < best
                    k = j
                    best = abs(v[i] - λavg[j])
                end
            end
        end
        if iszero(k)
            push!(λavg, v[i])
            push!(clusters, [i])
        else
            nk = length(clusters[k])
            λavg[k] = (λavg[k] * nk + v[i]) / (nk + 1)
            push!(clusters[k], i)
        end
    end
    clusters = clusters[isapproxzero.(imag.(λavg); ztol=solver.ztol)]
    r = length(clusters)
    vals = [zeros(T, n) for k in 1:r]
    for k in 1:r
        nk = length(clusters[k])
        for j in clusters[k]
            q = Z[:, j]
            for i in 1:n
                vals[k][i] += dot(q, Ms[i] * q) / nk
            end
        end
    end
    vals
end

function algebraicsolver(algo::AbstractMultiplicationMatricesAlgorithm,
                         solver::AbstractMultiplicationMatricesSolver)
    SolverUsingMultiplicationMatrices(algo, solver)
end
function algebraicsolver(solver::AbstractMultiplicationMatricesSolver)
    algebraicsolver(GröbnerBasisMultiplicationMatricesAlgorithm(), solver)
end

function defaultalgebraicsolver(::Type{T}) where T
    algebraicsolver(GröbnerBasisMultiplicationMatricesAlgorithm(), ReorderedSchurMultiplicationMatricesSolver())
end