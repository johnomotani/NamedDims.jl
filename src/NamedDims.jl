module NamedDims
using Base: @propagate_inbounds
using Statistics

export NamedDimsArray, dim

include("name_core.jl")
include("wrapper_array.jl")
include("functions.jl")
include("functions_dims.jl")
include("functions_math.jl")

end # module
