"""
    NamedDimsStyle{S}
This is a `BroadcastStyle` for NamedDimsArray's
It preserves the dimension names.
`S` should be the `BroadcastStyle` of the wrapped type.
"""
struct NamedDimsStyle{S<:BroadcastStyle} <: AbstractArrayStyle{Any} end
NamedDimsStyle(::S) where {S} = NamedDimsStyle{S}()
NamedDimsStyle(::S, ::Val{N}) where {S,N} = NamedDimsStyle(S(Val(N)))
NamedDimsStyle(::Val{N}) where {N} = NamedDimsStyle{DefaultArrayStyle{N}}()
function NamedDimsStyle(a::BroadcastStyle, b::BroadcastStyle)
    inner_style = BroadcastStyle(a, b)

    # if the inner_style is Unknown then so is the outer-style
    if inner_style isa Unknown
        return Unknown()
    else
        return NamedDimsStyle(inner_style)
    end
end

function Base.BroadcastStyle(::Type{<:NamedDimsArray{L,T,N,A}}) where {L,T,N,A}
    inner_style = typeof(BroadcastStyle(A))
    return NamedDimsStyle{inner_style}()
end
function Base.BroadcastStyle(::NamedDimsStyle{A}, ::NamedDimsStyle{B}) where {A,B}
    return NamedDimsStyle(A(), B())
end

# Resolve ambiguities
# for all these cases, we define that we win to be the outer style regardless of order
for B in (
    :BroadcastStyle, :DefaultArrayStyle, :AbstractArrayStyle, :(Broadcast.Style{Tuple}),
)
    @eval function Base.BroadcastStyle(::NamedDimsStyle{A}, b::$B) where A
        return NamedDimsStyle(A(), b)
    end
    @eval function Base.BroadcastStyle(b::$B, ::NamedDimsStyle{A}) where A
        return NamedDimsStyle(b, A())
    end
end


"""
    unwrap_broadcasted

Recursively unwraps `NamedDimsArray`s and `NamedDimsStyle`s.
replacing the `NamedDimsArray`s with the wrapped array,
and `NamedDimsStyle` with the wrapped `BroadcastStyle`.
"""
function unwrap_broadcasted(bc::Broadcasted{NamedDimsStyle{S}}) where {S}
    inner_args = map(unwrap_broadcasted, bc.args)
    return Broadcasted{S}(bc.f, inner_args, axes(bc))
end
unwrap_broadcasted(x) = x
unwrap_broadcasted(nda::NamedDimsArray) = parent(nda)

# We need to implement copy because if the wrapper array type does not support setindex
# then the `similar` based default method will not work
function Broadcast.copy(bc::Broadcasted{NamedDimsStyle{S}}) where {S}
    inner_bc = unwrap_broadcasted(bc)
    data = copy(inner_bc)

    L = broadcasted_names(bc)
    return NamedDimsArray{L}(data)
end

function Base.copyto!(dest::AbstractArray, bc::Broadcasted{NamedDimsStyle{S}}) where {S}
    inner_bc = unwrap_broadcasted(bc)
    copyto!(dest, inner_bc)
    L = unify_names(dimnames(dest), broadcasted_names(bc))
    return NamedDimsArray{L}(dest)
end

broadcasted_names(bc::Broadcasted) = broadcasted_names(bc.args...)
const unroll_size = 2
# Create wrapper that handles calls with more arguments than unroll_size
let argnames = Tuple(Symbol("a$i") for i ∈ 1:unroll_size)
    eval(quote
         function broadcasted_names($(argnames...), bs...)
             a_name = broadcasted_names($(argnames...))
             b_name = broadcasted_names(bs...)
             return unify_names_longest(a_name, b_name)
         end
    end)
end
# Create unrolled functions that call broadcasted_names on each argument for numbers of
# arguments up to unroll_size
for n ∈ 2:unroll_size
    argnames = Tuple(Symbol("a$(i)") for i ∈ 1:n)
    names = Tuple(Symbol("a$(i)_name") for i ∈ 1:n)
    func_body = :()
    for (argname, name) ∈ zip(argnames, names)
        func_body = quote
            $func_body
            $name = broadcasted_names($argname)
        end
    end
    eval(quote
        function broadcasted_names($(argnames...))
            $func_body
            return unify_names_longest($(names...))
        end
    end)
end
broadcasted_names(a::AbstractArray) = dimnames(a)
broadcasted_names(a) = tuple()
