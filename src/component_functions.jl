abstract type Coupling end
"""
    struct AntiSymmetric <: Coupling end

AntiSymmetric coupling type. The edge function f is evaluated once:

 - the dst vertex receives the first `d` values of the edge state,
 - the src vertex receives (-1) of that.

Here, `d` is the edge depth of the Network.
"""
struct AntiSymmetric <: Coupling end
"""
    struct Symmetric <: Coupling end

Symmetric coupling type. The edge function f is evaluated once:

 - the dst vertex receives the first `d` values of the edge state,
 - the src vertex receives the same.

Here, `d` is the edge depth of the Network.
"""
struct Symmetric <: Coupling end
"""
    struct Directed <: Coupling end

Directed coupling type. The edge function f is evaluated once:

 - the dst vertex receives the first `d` values of the edge state,
 - the src vertex receives nothing.

Here, `d` is the edge depth of the Network.
"""
struct Directed <: Coupling end
"""
    struct Fiducial <: Coupling end

Fiducial coupling type. The edge function f is evaluated once:

 - the dst vertex receives the `1:d` values of the edge state,
 - the src vertex receives the `d+1:2d` values of the edge state.

Here, `d` is the edge depth of the Network.
"""
struct Fiducial <: Coupling end
const CouplingUnion = Union{AntiSymmetric,Symmetric,Directed,Fiducial}

abstract type ComponentFunction end

Mixers.@pour CommonFields begin
    name::Symbol
    f::F
    sym::Vector{Symbol}
    depth::Int
    psym::Vector{Symbol}
    obsf::OF
    obssym::Vector{Symbol}
    symmetadata::Dict{Symbol,Dict{Symbol, Any}}
    metadata::Dict{Symbol,Any}
end
compf(c::ComponentFunction) = c.f
dim(c::ComponentFunction)::Int = length(sym(c))
sym(c::ComponentFunction)::Vector{Symbol} = c.sym
pdim(c::ComponentFunction)::Int = length(psym(c))
psym(c::ComponentFunction)::Vector{Symbol} = c.psym
obsf(c::ComponentFunction) = c.obsf
obssym(c::ComponentFunction)::Vector{Symbol} = c.obssym
depth(c::ComponentFunction)::Int = c.depth
symmetadata(c::ComponentFunction)::Dict{Symbol,Dict{Symbol,Any}} = c.symmetadata
metadata(c::ComponentFunction)::Dict{Symbol,Any} = c.metadata

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
struct ODEVertex{F,OF,MM} <: VertexFunction
    @CommonFields
    mass_matrix::MM
    # dfdp dfdv dfde
end
ODEVertex(; kwargs...) = _construct_comp(ODEVertex, kwargs)
ODEVertex(f; kwargs...) = ODEVertex(;f, kwargs...)
ODEVertex(f, dim; kwargs...) = ODEVertex(;f, _dimsym(dim)..., kwargs...)
ODEVertex(f, dim, pdim; kwargs...) = ODEVertex(;f, _dimsym(dim, pdim)..., kwargs...)

struct StaticVertex{F,OF} <: VertexFunction
    @CommonFields
end
StaticVertex(; kwargs...) = _construct_comp(StaticVertex, kwargs)
StaticVertex(f; kwargs...) = StaticVertex(;f, kwargs...)
StaticVertex(f, dim; kwargs...) = StaticVertex(;f, _dimsym(dim)..., kwargs...)
StaticVertex(f, dim, pdim; kwargs...) = StaticVertex(;f, _dimsym(dim, pdim)..., kwargs...)
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

struct StaticEdge{C,F,OF} <: EdgeFunction{C}
    @CommonFields
    coupling::C
end
StaticEdge(; kwargs...) = _construct_comp(StaticEdge, kwargs)
StaticEdge(f; kwargs...) = StaticEdge(;f, kwargs...)
StaticEdge(f, dim, coupling; kwargs...) = StaticEdge(;f, _dimsym(dim)..., coupling, kwargs...)
StaticEdge(f, dim, pdim, coupling; kwargs...) = StaticEdge(;f, _dimsym(dim, pdim)..., coupling, kwargs...)

struct ODEEdge{C,F,OF,MM} <: EdgeFunction{C}
    @CommonFields
    coupling::C
    mass_matrix::MM
end
ODEEdge(; kwargs...) = _construct_comp(ODEEdge, kwargs)
ODEEdge(f; kwargs...) = ODEEdge(;f, kwargs...)
ODEEdge(f, dim, coupling; kwargs...) = ODEEdge(;f, _dimsym(dim)..., coupling, kwargs...)
ODEEdge(f, dim, pdim, coupling; kwargs...) = ODEEdge(;f, _dimsym(dim, pdim)..., coupling, kwargs...)

statetype(::T) where {T<:ComponentFunction} = statetype(T)
statetype(::Type{<:ODEVertex}) = Dynamic()
statetype(::Type{<:StaticVertex}) = Static()
statetype(::Type{<:StaticEdge}) = Static()
statetype(::Type{<:ODEEdge}) = Dynamic()

isdynamic(x) = statetype(x) == Dynamic()
isstatic(x)  = statetype(x) == Static()

"""
    dispatchT(<:ComponentFunction) :: Type{<:ComponentFunction}

Returns the type "essence" of the component used for dispatch.
Fills up type parameters with `nothing` to ensure `Core.compiler.isconstType`
for GPU compatibility.
"""
dispatchT(::T) where {T<:ComponentFunction} = dispatchT(T)
dispatchT(::Type{<:StaticVertex}) = StaticVertex{nothing,nothing}
dispatchT(::Type{<:ODEVertex}) = ODEVertex{nothing,nothing,nothing}
dispatchT(T::Type{<:StaticEdge}) = StaticEdge{typeof(coupling(T)),nothing,nothing}
dispatchT(T::Type{<:ODEEdge}) = ODEEdge{typeof(coupling(T)),nothing,nothing,nothing}

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

# helper functions to dispatch on correct dim/sym keywords based on type
const _sym_T = Union{Vector, Pair, Symbol}
_dimsym(dim::Number) = (; dim)
_dimsym(sym::_sym_T) = (; sym)
_dimsym(dim::Number, pdim::Number) = (; dim, pdim)
_dimsym(dim::Number, psym::_sym_T) = (; dim, psym)
_dimsym(sym::_sym_T, pdim::Number) = (; sym, pdim)
_dimsym(sym::_sym_T, psym::_sym_T) = (; sym, psym)

"""
    _construct_comp(::Type{T}, kwargs) where {T}

Internal function to construct a component function from keyword arguments.
Fills up kw arguments with default values and performs sanity checks.
"""
function _construct_comp(::Type{T}, kwargs) where {T}
    dict = _fill_defaults(T, kwargs)

    # check signature of f
    # if !_valid_signature(T, dict[:f])
    #     throw(ArgumentError("Function f does not take the correct number of arguments."))
    # end

    # pop check keyword
    check = pop!(dict, :check, true)

    if !all(in(keys(dict)), fieldnames(T))
        throw(ArgumentError("Cannot construct $T: arguments $(setdiff(fieldnames(T), keys(dict))) missing."))
    end
    if !all(in(fieldnames(T)), keys(dict))
        throw(ArgumentError("Cannot construct $T: got additional arguments $(setdiff(keys(dict), fieldnames(T)))."))
    end

    args = map(fieldtypes(T), fieldnames(T)) do FT, name
        convert(FT, dict[name])
    end

    c = T(args...)
    check && chk_component(c)
    return c
end

"""
    _fill_defaults(T, kwargs)

Fill up keyword arguments `kwargs` for type T with default values.
Also perfoms sanity check some properties like mass matrix, depth, ...
"""
function _fill_defaults(T, kwargs)
    dict = Dict{Symbol, Any}(kwargs)

    # syms might be provided as single pairs or symbols, wrap in vector
    _maybewrap!(dict, :sym, Union{Symbol, Pair})
    _maybewrap!(dict, :psym, Union{Symbol, Pair})
    _maybewrap!(dict, :obssym, Symbol)

    symmetadata = get!(dict, :symmetadata, Dict{Symbol,Dict{Symbol,Any}}())
    metadata = get!(dict, :metadata, Dict{Symbol,Any}())

    # sym & dim
    haskey(dict, :dim) || haskey(dict, :sym) || throw(ArgumentError("Either `dim` or `sym` must be provided to construct $T."))
    if haskey(dict, :sym)
        if haskey(dict, :dim)
            if dict[:dim] != length(dict[:sym])
                throw(ArgumentError("Length of sym and dim must match."))
            end
            # @warn "Unnecessary kw dim, can be infered from sym."
            delete!(dict, :dim)
        end
        if _has_metadata(dict[:sym])
            dict[:sym], _metadata = _split_metadata(dict[:sym])
            mergewith!(merge!, symmetadata, _metadata)
        end
    else
        _dim = pop!(dict, :dim)
        if T <: VertexFunction
            dict[:sym] = [_dim>1 ? Symbol("v", subscript(i)) : :s for i in 1:_dim]
        else
            dict[:sym] = [_dim>1 ? Symbol("e", subscript(i)) : :e for i in 1:_dim]
        end
    end
    dim = length(dict[:sym])
    if haskey(dict,:def)
        _def = pop!(dict, :def)
        @argcheck length(_def)==dim  "Length of sym & def must match dim."
        for (sym, def) in zip(dict[:sym], _def)
            if isnothing(def)
                continue
            end
            if haskey(symmetadata, sym) && haskey(symmetadata[sym], :default)
                throw(ArgumentError("Default value for $sym is already provided in metadata."))
            else
                mt = get!(symmetadata, sym, Dict{Symbol,Any}())
                mt[:default] = def
            end
        end
    end

    # psym & pdim
    if !haskey(dict, :pdim) && !haskey(dict, :psym)
        dict[:pdim] = 0
    end
    if haskey(dict, :psym)
        if haskey(dict, :pdim)
            if dict[:pdim] != length(dict[:psym])
                throw(ArgumentError("Length of sym and dim must match."))
            end
            # @warn "Unnecessary kw pdim, can be infered from psym."
            delete!(dict, :pdim)
        end
        if _has_metadata(dict[:psym])
            dict[:psym], _metadata = _split_metadata(dict[:psym])
            mergewith!(merge!, symmetadata, _metadata)
        end
    else
        _pdim = pop!(dict, :pdim)
        dict[:psym] = [_pdim>1 ? Symbol("p", subscript(i)) : :p for i in 1:_pdim]
    end
    if haskey(dict,:pdef)
        _pdef = pop!(dict, :pdef)
        @argcheck length(_pdef) == length(dict[:psym]) "Length of sym & def must match dim."
        for (sym, def) in zip(dict[:psym], _pdef)
            if isnothing(def)
                continue
            end
            if haskey(symmetadata, sym) && haskey(symmetadata[sym], :default)
                throw(ArgumentError("Default value for $sym is already provided in metadata."))
            else
                mt = get!(symmetadata, sym, Dict{Symbol,Any}())
                mt[:default] = def
            end
        end
    end

    # obsf & obssym
    if haskey(dict, :obsf) || haskey(dict, :obssym)
        if !(haskey(dict, :obsf) && haskey(dict, :obssym))
            throw(ArgumentError("If `obsf` is provided, `obssym` must be provided as well."))
        end
        if _has_metadata(dict[:obssym])
            dict[:obssym], _metadata = _split_metadata(dict[:obssym])
            mergewith!(merge!, symmetadata, _metadata)
        end
    else
        dict[:obsf] = nothing
        dict[:obssym] = Symbol[]
    end

    # name
    if !haskey(dict, :name)
        dict[:name] = _default_name(T)
    end

    # mass_matrix
    if isdynamic(T)
        if !haskey(dict, :mass_matrix)
            dict[:mass_matrix] = LinearAlgebra.I
        else
            mm = dict[:mass_matrix]
            if mm isa UniformScaling
            elseif mm isa Vector # convert to diagonal
                if length(mm) == dim
                    dict[:mass_matrix] = LinearAlgebra.Diagonal(mm)
                else
                    throw(ArgumentError("If given as a vector, mass matrix must have length equal to dimension of component."))
                end
            elseif mm isa Number # convert to uniform scaling
                dict[:mass_matrix] = LinearAlgebra.UniformScaling(mm)
            elseif mm isa AbstractMatrix
                @argcheck size(mm) == (dim, dim) "Size of mass matrix must match dimension of component."
            else
                throw(ArgumentError("Mass matrix must be a vector, square matrix,\
                                     a uniform scaling, or scalar. Got $(mm)."))
            end
        end
    end

    # coupling
    if T<:EdgeFunction && !haskey(dict, :coupling)
        throw(ArgumentError("Coupling type must be provided to construct $T."))
    end

    # depth
    if !haskey(dict, :depth)
        if T<:VertexFunction
            dict[:depth] = dim
        elseif T<:EdgeFunction
            coupling = dict[:coupling]
            dict[:depth] = coupling==Fiducial() ? floor(Int, dim/2) : dim
        else
            throw(ArgumentError("Cannot construct $T: default depth not known."))
        end
    end
    if haskey(dict, :coupling) && dict[:coupling]==Fiducial() && dict[:depth] > floor(dim/2)
        throw(ArgumentError("Depth cannot exceed half the dimension for Fiducial coupling."))
    elseif dict[:depth] > dim
        throw(ArgumentError("Depth cannot exceed half the dimension."))
    end

    # check for name clashes (at the end because only now sym, psym, obssym are initialized)
    _s  = get(dict, :sym, Symbol[])
    _ps = get(dict, :psym, Symbol[])
    _os = get(dict, :obssym, Symbol[])
    allunique(vcat(_s, _ps, _os)) || throw(ArgumentError("Symbol names must be unique. There are clashes in sym, psym and obssym."))

    return dict
end

_default_name(::Type{StaticVertex}) = :StaticVertex
_default_name(::Type{ODEVertex}) = :ODEVertex
_default_name(::Type{StaticEdge}) = :StaticEdge
_default_name(::Type{ODEEdge}) = :ODEEdge

_has_metadata(vec::AbstractVector{<:Symbol}) = false
_has_metadata(vec::AbstractVector{<:Pair}) = true
_has_metadata(vec::AbstractVector) = any(el -> el isa Pair, vec)
function _split_metadata(input)
    Base.require_one_based_indexing(input)
    syms = Vector{Symbol}(undef, length(input))
    metadata = Dict{Symbol,Dict{Symbol,Any}}()
    for i in eachindex(input)
        if input[i] isa Pair
            sym = input[i].first
            dat  = input[i].second
            syms[i] = sym
            metadata[sym] = if dat isa Number
                Dict(:default => dat)
            elseif dat isa NamedTuple
                Dict(zip(keys(dat), values(dat)))
            else
                dat
            end
        else
            syms[i] = input[i]
        end
    end
    syms, metadata
end

"If index `s` in `d` exists and isa `T` wrap in vector."
function _maybewrap!(d, s, T)
    if haskey(d, s)
        v = d[s]
        if v isa T
            d[s] = [v]
        end
    end
end

_valid_signature(::Type{<:StaticVertex}, f) = _takes_n_vectors(f, 3) #(u, edges, p, t)
_valid_signature(::Type{<:ODEVertex}, f) = _takes_n_vectors(f, 4) #(du, u, edges, p, t)
_valid_signature(::Type{<:StaticEdge}, f) = _takes_n_vectors(f, 4) #(u, src, dst, p, t)
_valid_signature(::Type{<:ODEEdge}, f) = _takes_n_vectors(f, 5) #(du, u, src, dst, p, t)

_takes_n_vectors(f, n) = hasmethod(f, (Tuple(Vector{Float64} for i in 1:n)..., Float64))


####
#### per sym metadata
####
function has_metadata(c::ComponentFunction, sym, key)
    md = symmetadata(c)
    haskey(md, sym) && haskey(md[sym], key)
end
get_metadata(c::ComponentFunction, sym, key) = symmetadata(c)[sym][key]

set_metadata!(c::ComponentFunction, sym, pair::Pair) = set_metadata!(c, sym, pair.first, pair.second)
function set_metadata!(c::ComponentFunction, sym, key, value)
    d = get!(symmetadata(c), sym, Dict{Symbol,Any}())
    d[key] = value
end

has_default(c::ComponentFunction, sym) = has_metadata(c, sym, :default)
get_default(c::ComponentFunction, sym) = get_metadata(c, sym, :default)
set_default!(c::ComponentFunction, sym, value) = set_metadata!(c, sym, :default, value)

function def(c::ComponentFunction)::Vector{Union{Nothing,Float64}}
    map(c.sym) do s
        has_default(c, s) ? get_default(c, s) : nothing
    end
end
function pdef(c::ComponentFunction)::Vector{Union{Nothing,Float64}}
    map(c.psym) do s
        has_default(c, s) ? get_default(c, s) : nothing
    end
end
