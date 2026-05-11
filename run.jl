println("=== Ontario Energy System Optimization ===\n")

println("[ 1 / 3 ]  Loading inputs...")
include("src/load_inputs.jl")

println("[ 2 / 3 ]  Building and solving model...")
include("src/build_model.jl")

println("[ 3 / 3 ]  Writing outputs...")
include("src/write_outputs.jl")

println("\nDone.")
