# Immutable types s.t. we can use map on functions with kwargs
abstract FilterOutput
immutable AllOut<:FilterOutput end
immutable MinimumOut<:FilterOutput end

abstract FilterPresample
immutable IncludePresample<:FilterPresample end
immutable ExcludePresample<:FilterPresample end

"""
```
filter{S<:AbstractFloat}(m::AbstractModel, df::DataFrame,
    syses::Vector{System{S}}, z0::Vector{S} = Vector{S}(), vz0::Matrix{S} =
    Matrix{S}(); lead::Int = 0, allout::Bool = false, include_presample::Bool =
    true)

filter{S<:AbstractFloat}(m::AbstractModel, data::Matrix{S},
    syses::Vector{System{S}}, z0::Vector{S} = Vector{S}(), vz0::Matrix{S} =
    Matrix{S}(); lead::Int = 0, allout::Bool = false, include_presample::Bool =
    true)
```
    
Computes and returns the filtered values of states for every state-space system in `syses`.

### Inputs

- `m`: model object
- `data`: DataFrame or matrix of data for observables
- `syses`: a vector of `System` objects specifying state-space
  system matrices for each draw
- `z0`: an optional `Nz` x 1 initial state vector
- `vz0`: an optional `Nz` x `Nz` covariance matrix of an initial state vector
- `allout`: an optional keyword argument indicating whether we want optional
  output variables returned as well
- `include_presample`: indicates whether to include presample periods in the
  returned vector of `Kalman` objects

### Outputs

`filter` returns a vector of `Kalman` objects, which each contain the following fields:

- `logl`: value of the average log likelihood function of the SSM under assumption that
  observation noise ϵ(t) is normally distributed
- `pred`: a `Nz` x `T+lead` matrix containing one-step predicted state vectors.
- `vpred`: a `Nz` x `Nz` x `T+lead` matrix containing mean square errors of predicted
  state vectors.
- `filt`: an optional `Nz` x `T` matrix containing filtered state vectors.
- `vfilt`: an optional `Nz` x `Nz` x `T` matrix containing mean square errors of filtered
  state vectors.
"""
function filter{S<:AbstractFloat}(m::AbstractModel, df::DataFrame, syses::Vector{System{S}},
                                  z0::Vector{S} = Vector{S}(), vz0::Matrix{S} = Matrix{S}();
                                  lead::Int = 0, allout::Bool = false,
                                  include_presample::Bool = true)
    
    # Convert the DataFrame to a data matrix without altering the original dataframe  
    data = df_to_matrix(m, df)
    filter(m, data, syses, z0, vz0; lead = lead, allout = allout, include_presample = include_presample)
end

function filter{S<:AbstractFloat}(m::AbstractModel, data::Matrix{S}, syses::Vector{System{S}},
                                  z0::Vector{S} = Vector{S}(), vz0::Matrix{S} = Matrix{S}();
                                  lead::Int = 0, allout::Bool = false, include_presample::Bool = true)

    # numbers of useful things
    ndraws = size(syses, 1)

    # Broadcast models and data matrices 
    models = fill(m, ndraws)
    datas = fill(data, ndraws)
    z0s = fill(z0, ndraws)
    vz0s = fill(vz0, ndraws)
    allouts = if allout
        fill(AllOut(), ndraws)
    else
        fill(MinimumOut(), ndraws)
    end
    include_presamples = if include_presample
        fill(IncludePresample(), ndraws)
    else
        fill(ExcludePresample(), ndraws)
    end
    
    # Call filter over all draws
    if use_parallel_workers(m) && nworkers() > 1
        println("Using pmap")
        mapfcn = pmap
    else
        mapfcn = map
    end    

    mapfcn(DSGE.tricky_filter, allouts, include_presamples, models, datas, syses, z0s, vz0s)
end

tricky_filter(::AllOut, ::IncludePresample, m::AbstractModel, data::Matrix, sys::System, z0::Vector, vz0::Matrix) =
    filter(m, data, sys, z0, vz0; allout = true, include_presample = true)
tricky_filter(::AllOut, ::ExcludePresample, m::AbstractModel, data::Matrix, sys::System, z0::Vector, vz0::Matrix) =
    filter(m, data, sys, z0, vz0; allout = true, include_presample = false)
tricky_filter(::MinimumOut, ::IncludePresample, m::AbstractModel, data::Matrix, sys::System, z0::Vector, vz0::Matrix) = 
    filter(m, data, sys, z0, vz0; allout = false, include_presample = true)
tricky_filter(::MinimumOut, ::ExcludePresample, m::AbstractModel, data::Matrix, sys::System, z0::Vector, vz0::Matrix) = 
    filter(m, data, sys, z0, vz0; allout = false, include_presample = false)
    
function filter{S<:AbstractFloat}(m::AbstractModel, data::Matrix{S}, sys::System,
                                  z0::Vector{S} = Vector{S}(), vz0::Matrix{S} = Matrix{S}();
                                  lead::Int = 0, allout::Bool = false, include_presample::Bool = true)
    
    # pull out the elements of sys
    TTT    = sys[:TTT]
    RRR    = sys[:RRR]
    CCC    = sys[:CCC]
    QQ     = sys[:QQ]
    ZZ     = sys[:ZZ]
    DD     = sys[:DD]
    VVall  = sys[:VVall]

    # Call the appropriate version of the Kalman filter
    if n_anticipated_shocks(m) > 0

        # We have 3 regimes: presample, main sample, and expected-rate sample
        # (starting at index_zlb_start)
        k, _, _, _ = kalman_filter_2part(m, data, TTT, RRR, CCC, z0, vz0;
            lead = lead, allout = allout, include_presample = include_presample)
    else
        # regular Kalman filter with no regime-switching
        k = kalman_filter(m, data', TTT, CCC, ZZ, DD, VVall, z0, vz0;
            lead = lead, allout = allout, include_presample = include_presample)
    end

    return k
end

"""
```
filterandsmooth{S<:AbstractFloat}(m::AbstractModel, df::DataFrame,
    syses::Vector{System{S}}, z0::Vector{S} = Vector{S}(), vz0::Matrix{S} =
    Matrix{S}(); lead::Int = 0, allout::Bool = false, include_presample::Bool =
    true)

filterandsmooth{S<:AbstractFloat}(m::AbstractModel, data::Matrix{S},
    syses::Vector{System{S}}, z0::Vector{S} = Vector{S}(), vz0::Matrix{S} =
    Matrix{S}(); lead::Int = 0, allout::Bool = false, include_presample::Bool =
    true)
```
    
Computes and returns the smoothed states and shocks for every state-space system in `syses`.

### Inputs

- `m`: model object
- `data`: DataFrame or matrix of data for observables
- `syses`: a vector of `System` objects specifying state-space
  system matrices for each draw
- `z0`: an optional `Nz` x 1 initial state vector
- `vz0`: an optional `Nz` x `Nz` covariance matrix of an initial state vector
- `include_presample`: indicates whether to include presample periods in the
  returned vectors of smoothed states and shocks

### Outputs

- `alpha_hats`: a vector of smoothed states (`alpha_hat`s) returned from the
  smoother specified by `smoother_flag(m)`, one for each system in `syses`
- `eta_hats`: a vector of smoothed shocks (`eta_hat`s) returned from the
  smoother, one for each system in `syses`
"""
function filterandsmooth{S<:AbstractFloat}(m::AbstractModel, df::DataFrame,
                                           syses::Vector{System{S}},
                                           z0::Vector{S} = Vector{S}(),
                                           vz0::Matrix{S} = Matrix{S}();
                                           lead::Int = 0, allout::Bool = false,
                                           include_presample::Bool = true)

    data = df_to_matrix(m, df)
    filterandsmooth(m, data, syses, z0, vz0; lead = lead, include_presample = include_presample)
end

function filterandsmooth{S<:AbstractFloat}(m::AbstractModel, data::Matrix{S},
                                           syses::Vector{System{S}},
                                           z0::Vector{S} = Vector{S}(),
                                           vz0::Matrix{S} = Matrix{S}();
                                           lead::Int = 0, include_presample::Bool = true)
    # numbers of useful things
    ndraws = length(syses)

    # Broadcast models and data matrices 
    models = fill(m, ndraws)
    datas = fill(data, ndraws)
    z0s = fill(z0, ndraws)
    vz0s = fill(vz0, ndraws)
    include_presamples = if include_presample
        fill(IncludePresample(), ndraws)
    else
        fill(ExcludePresample(), ndraws)
    end
    
    # Call filter over all draws
    if use_parallel_workers(m) && nworkers() > 1
        println("Using pmap")
        mapfcn = pmap
    else
        mapfcn = map
    end    
    out = mapfcn(DSGE.tricky_filterandsmooth, include_presamples, models, datas, syses, z0s, vz0s)

    alpha_hats = [Array(x[1]) for x in out] # to make type stable 
    eta_hats   = [Array(x[2]) for x in out] 

    return alpha_hats, eta_hats
end

tricky_filterandsmooth(::IncludePresample, m::AbstractModel, data::Matrix, sys::System, z0::Vector, vz0::Matrix) = 
    filterandsmooth(m, data, sys, z0, vz0; include_presample = true)
tricky_filterandsmooth(::ExcludePresample, m::AbstractModel, data::Matrix, sys::System, z0::Vector, vz0::Matrix) = 
    filterandsmooth(m, data, sys, z0, vz0; include_presample = false)

function filterandsmooth{S<:AbstractFloat}(m::AbstractModel, data::Matrix{S}, sys::System,
                                           z0::Vector{S} = Vector{S}(), vz0::Matrix{S} = Matrix{S}();
                                           lead::Int = 0, include_presample::Bool = true)
    ## 1. Filter

    # pull out the elements of sys
    TTT   = sys[:TTT]
    RRR   = sys[:RRR]
    CCC   = sys[:CCC]
    QQ    = sys[:QQ]
    ZZ    = sys[:ZZ]
    DD    = sys[:DD]
    VVall = sys[:VVall]

    # Call the appropriate version of the Kalman filter
    if n_anticipated_shocks(m) > 0

        # We have 3 regimes: presample, main sample, and expected-rate sample
        # (starting at index_zlb_start)
        k, _, _, _ = kalman_filter_2part(m, data, TTT, RRR, CCC, z0, vz0; lead =
            lead, allout = true, include_presample = true)
    else
        # regular Kalman filter with no regime-switching
        k = kalman_filter(m, data', TTT, CCC, ZZ, DD, VVall, z0, vz0;
            lead = lead, allout = true, include_presample = true)
    end

    ## 2. Smooth

    alpha_hat, eta_hat = if forecast_smoother(m) == :kalman
        kalman_smoother(m, data', sys, k[:z0], k[:vz0], k[:pred], k[:vpred])
    elseif forecast_smoother(m) == :durbin_koopman
        durbin_koopman_smoother(m, data', sys, k[:z0], k[:vz0])
    end

    return alpha_hat, eta_hat
end
