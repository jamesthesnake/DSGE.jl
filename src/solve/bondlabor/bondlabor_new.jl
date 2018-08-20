using DSGE
using BenchmarkTools
using Distributions
using JLD
using Roots

test_output = true

m = BondLabor()

# Steady-state computation
steadystate!(m)
@btime steadystate!(m)

test_output && include("test/steady_state.jl")

# Jacobian computation
m.testing = true        # So that it will test against the unnormalized Jacobian
JJ = DSGE.jacobian(m)
@btime JJ = DSGE.jacobian(m)

test_output && include("test/jacobian.jl")

# Solve
m.testing = false      # So the Jacobian will be normalized within the klein solution
gx, hx = klein(m)
@btime klein(m)

test_output && include("test/solve.jl")
