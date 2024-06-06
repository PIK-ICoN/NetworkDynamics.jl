abstract type Coupling end
struct AntiSymmetric <: Coupling end
struct Symmetric <: Coupling end
struct Directed <: Coupling end
struct Fiducial <: Coupling end
const CouplingUnion = Union{AntiSymmetric,Symmetric,Directed,Fiducial}

abstract type ComponentFunction end

# TODO: change nothing to missing for default values?
Mixers.@pour CommonFields begin
    f::F
    dim::Int
    sym::Vector{Symbol} = [dim>1 ? Symbol("s", subscript(i)) : :s for i in 1:dim]
    def::Vector{Union{Nothing,Float64}} = [nothing for _ in 1:dim]
    pdim::Int
    psym::Vector{Symbol} = [pdim>1 ? Symbol("p", subscript(i)) : :p for i in 1:pdim]
    pdef::Vector{Union{Nothing,Float64}} = [nothing for _ in 1:pdim]
    obsf::OF = nothing
    obssym::Vector{Symbol} = Symbol[]
end
# XXX: Mixers Issue argument ordering + asserts for pdim, psymlength
compf(c::ComponentFunction) = c.f
dim(c::ComponentFunction)::Int = c.dim
sym(c::ComponentFunction)::Vector{Symbol} = c.sym
def(c::ComponentFunction)::Vector{Union{Nothing,Float64}} = c.def
pdim(c::ComponentFunction)::Int = c.pdim
psym(c::ComponentFunction)::Vector{Symbol} = c.psym
pdef(c::ComponentFunction)::Vector{Union{Nothing,Float64}} = c.pdef
obsf(c::ComponentFunction) = c.obsf
obssym(c::ComponentFunction)::Vector{Symbol} = c.obssym
depth(c::ComponentFunction)::Int = c.depth

"""
Abstract supertype for all vertex functions.
"""
abstract type VertexFunction <: ComponentFunction end

"""
Abstract supertype for all edge functions.
"""
# abstract type EdgeFunction{C<:Coupling} <: ComponentFunction end
abstract type EdgeFunction{C} <: ComponentFunction end

coupling(::EdgeFunction{C}) where {C} = C()
coupling(::Type{<:EdgeFunction{C}}) where {C} = C()

"""
$(TYPEDEF)

# Fields
$(FIELDS)
"""
@with_kw_noshow struct ODEVertex{F,OF,MM} <: VertexFunction
    @CommonFields
    name::Symbol = :ODEVertex
    mass_matrix::MM = LinearAlgebra.I
    # dfdp dfdv dfde
    depth::Int = dim
end
ODEVertex(f, dim, pdim; kwargs...) = ODEVertex(;f, dim, pdim, kwargs...)
ODEVertex(f; kwargs...) = ODEVertex(;f, kwargs...)

@with_kw_noshow struct StaticVertex{F,OF} <: VertexFunction
    @CommonFields
    name::Symbol = :StaticVertex
    depth::Int = dim
end
StaticVertex(f, dim, pdim; kwargs...) = StaticVertex(;f, dim, pdim, kwargs...)
StaticVertex(f; kwargs...) = StaticVertex(;f, kwargs...)
function ODEVertex(sv::StaticVertex)
    d = Dict{Symbol,Any}()
    for prop in propertynames(sv)
        d[prop] = getproperty(sv, prop)
    end
    d[:f]  = let _f = sv.f
        (dx, x, esum, p, t) -> begin
            _f(dx, esum, p, t)
            @inbounds for i in eachindex(dx)
                dx[i] = dx[i] - x[i]
            end
            return nothing
        end
    end
    d[:mass_matrix] = 0.0
    ODEVertex(; d...)
end

@with_kw_noshow struct StaticEdge{C,F,OF} <: EdgeFunction{C}
    @CommonFields
    name::Symbol = :StaticEdge
    coupling::C
    depth::Int = coupling==Fiducial() ? floor(Int, dim/2) : dim
end
StaticEdge(f, dim, pdim, coupling; kwargs...) = StaticEdge(;f, dim, pdim, coupling, kwargs...)
StaticEdge(f; kwargs...) = StaticEdge(;f, kwargs...)

@with_kw_noshow struct ODEEdge{C,F,OF,MM} <: EdgeFunction{C}
    @CommonFields
    name::Symbol = :ODEEdge
    coupling::C
    mass_matrix::MM = LinearAlgebra.I
    depth::Int = coupling==Fiducial() ? floor(Int, dim/2) : dim
end
ODEEdge(f, dim, pdim, coupling; kwargs...) = ODEEdge(;f, dim, pdim, coupling, kwargs...)
ODEEdge(f; kwargs...) = ODEEdge(;f, kwargs...)

statetype(::T) where {T<:ComponentFunction} = statetype(T)
statetype(::Type{<:ODEVertex}) = Dynamic()
statetype(::Type{<:StaticEdge}) = Static()
statetype(::Type{<:ODEEdge}) = Dynamic()
isdynamic(x::ComponentFunction) = statetype(x) == Dynamic()

"""
    comptT(<:ComponentFunction) :: Type{<:ComponentFunction}

Returns the dispatch type of the component. Does not include unecessary type parameters.
"""
compT(::T) where {T<:ComponentFunction} = compT(T)
compT(::Type{<:ODEVertex}) = ODEVertex
compT(T::Type{<:StaticEdge}) = StaticEdge{typeof(coupling(T))}
compT(T::Type{<:ODEEdge}) = ODEEdge{typeof(coupling(T))}

batchequal(a, b) = false
function batchequal(a::EdgeFunction, b::EdgeFunction)
    for f in (compf, dim, pdim, coupling)
        f(a) == f(b) || return false
    end
    return true
end
function batchequal(a::VertexFunction, b::VertexFunction)
    for f in (compf, dim, pdim)
        f(a) == f(b) || return false
    end
    return true
end

