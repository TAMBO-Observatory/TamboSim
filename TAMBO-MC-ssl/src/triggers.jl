using Random: seed!

"""
    accept_all(e)

Returns an acceptance probability of 1.0, effectively accepting all events.

This function serves as a placeholder efficiency function that always returns 1.0.

# Arguments
- `e`: The event property (e.g., energy) for which to determine acceptance.

# Returns
- `Float64`: Always returns 1.0.
"""
function accept_all(e)::Float64
    return 1.0
end

"""
    reject_all(e)

Returns an acceptance probability of 0.0, effectively rejecting all events.

This function serves as a placeholder efficiency function that always returns 0.0.

# Arguments
- `e`: The event property (e.g., energy) for which to determine acceptance.

# Returns
- `Float64`: Always returns 0.0.
"""
function reject_all(e)::Float64
    return 0.0
end

"""
    _interpolated_efficiency(e, interpolated_eff)::Float64

Internal helper function that calculates interpolated efficiency for a given energy.

Handles energy values outside the interpolation range by returning 0.0 for energies
below the lower limit and the efficiency at the upper limit for energies above it.

# Arguments
- `e`: The energy of the particle.
- `interpolated_eff`: The interpolation function to use.

# Returns
- `Float64`: The interpolated efficiency for the given energy.
"""
function _interpolated_efficiency(e, interpolated_eff)::Float64
    lower_limit = extrema(interpolated_eff.itp.knots[1])[begin]
    upper_limit = extrema(interpolated_eff.itp.knots[1])[end]

    if e < lower_limit
        return 0.0
    elseif e > upper_limit
        return interpolated_eff(upper_limit)
    else
        return interpolated_eff(e)
    end
end

"""
    interpolated_electron_efficiency(e)

Calculates the interpolated efficiency for electrons based on their energy.

# Arguments
- `e`: The energy of the electron.

# Returns
- `Float64`: The interpolated efficiency for the given electron energy.
"""
interpolated_electron_efficiency(e)::Float64 = _interpolated_efficiency(e, interpolated_eff_electron)

"""
    interpolated_muon_efficiency(e)

Calculates the interpolated efficiency for muons based on their energy.

# Arguments
- `e`: The energy of the muon.

# Returns
- `Float64`: The interpolated efficiency for the given muon energy.
"""
interpolated_muon_efficiency(e)::Float64 = _interpolated_efficiency(e, interpolated_eff_muon)

"""
    interpolated_gamma_efficiency(e)

Calculates the interpolated efficiency for gamma particles based on their energy.

# Arguments
- `e`: The energy of the gamma particle.

# Returns
- `Float64`: The interpolated efficiency for the given gamma particle energy.
"""
interpolated_gamma_efficiency(e)::Float64 = _interpolated_efficiency(e, interpolated_eff_gamma)

"""
    get_nhit(hit_map, efficiencies::Dict{Int, Function}) -> Int

Calculates the total number of "hits" or effective particles/photons based on a hit map and efficiencies.

This function iterates through a `hit_map`, which contains lists of `CorsikaEvent`s for different
detector modules. For each `CorsikaEvent`, it applies the relevant efficiency function from the
`efficiencies` dictionary to determine its contribution to the total `nhit`.

# Arguments
- `hit_map`: A map (e.g., dictionary) where keys represent detector modules and values are
  vectors of `CorsikaEvent`s that hit that module.
- `efficiencies::Dict{Int, Function}`: A dictionary mapping particle PDG IDs (Int) to
  efficiency functions (Function) that take a `CorsikaEvent` and return a weight or count.

# Returns
- `Int`: The total number of effective hits.
"""
function get_nhit(hit_map, efficiencies)
#function get_nhit(hit_map, efficiencies::Dict{Int, Function})
    nhit = 0
    for hits in values(hit_map)
        nhit += sum([corsika_int_weight(hit, efficiencies) for hit in hits])
    end
    return nhit
end

"""
    did_trigger(
        hit_map,
        module_trigger_thresh::Int=3,
        event_trigger_thresh::Int=30,
        trigger_type::String="whitepaper"
    ) -> Bool

Determines if an event triggers the detector based on a hit map and specified trigger criteria.

This method acts as a dispatcher, setting up the appropriate efficiency functions based on
`trigger_type` and then calling the core `did_trigger` method. It defines the particle
acceptance rules for different trigger types (e.g., "whitepaper", "threeamigos", "icetop_tanks").

# Arguments
- `hit_map`: A map containing `CorsikaEvent`s for each detector module.
- `module_trigger_thresh::Int`: The minimum number of hits (particles or photons) required
  for an individual module to be considered triggered. Defaults to 3.
- `event_trigger_thresh::Int`: The minimum total number of hits across all triggered modules
  for the entire event to be considered triggered. Defaults to 30.
- `trigger_type::String`: Specifies the type of trigger logic to apply.
  Supported types include "whitepaper", "threeamigos", "icetop_tanks", and "icetop_panels".

# Returns
- `Bool`: `true` if the event triggers the detector, `false` otherwise.
"""
function did_trigger(
    hit_map,
    module_trigger_thresh::Int=3,
    event_trigger_thresh::Int=30, # Note that this is either in number of incident particle or number of photons created depending on trigger type
    trigger_type::String="whitepaper"
)
    pids = Int[]
    for hits in values(hit_map)
        for hit in hits
            if hit.pdg in pids
                continue
            end
            push!(pids, hit.pdg)
        end
    end

    if trigger_type == "whitepaper"
        efficiencies = Dict(pid => accept_all for pid in pids)
    elseif trigger_type == "threeamigos"
        efficiencies = Dict()
        for pid in pids
            if pid == 11 || pid == 22 || pid == 13 # TODO: antiparticles?
                efficiencies[pid] = accept_all
            else
                efficiencies[pid] = reject_all
            end
        end
    elseif trigger_type == "icetop_tanks" || trigger_type == "icetop_panels"
        efficiencies = Dict()
        for pid in pids
            if pid == 11
                efficiencies[pid] = interpolated_electron_efficiency
            elseif pid == 13
                efficiencies[pid] = interpolated_muon_efficiency
            elseif pid == 22
                efficiencies[pid] = interpolated_gamma_efficiency
            else
                efficiencies[pid] = reject_all
            end
        end
    end

    return did_trigger(
        hit_map,
        efficiencies,
        module_trigger_thresh,
        event_trigger_thresh
    )
end

"""
    did_trigger(
        hit_map,
        efficiencies::Dict{Int, Function},
        module_trigger_thresh::Int=3,
        event_trigger_thresh::Int=30
    ) -> Bool

Core function to determine if an event triggers the detector.

This method applies the given `efficiencies` to the `hit_map` to calculate effective hits.
An event triggers if a sufficient number of individual modules are triggered (each exceeding
`module_trigger_thresh`), and the total effective hits across these modules exceeds
`event_trigger_thresh`.

# Arguments
- `hit_map`: A map containing `CorsikaEvent`s for each detector module.
- `efficiencies::Dict{Int, Function}`: A dictionary mapping particle PDG IDs (Int) to
  efficiency functions (Function) that take a `CorsikaEvent` and return a weight or count.
- `module_trigger_thresh::Int`: The minimum number of hits (particles or photons) required
  for an individual module to be considered triggered. Defaults to 3.
- `event_trigger_thresh::Int`: The minimum total number of effective hits across all triggered modules
  for the entire event to be considered triggered. Defaults to 30.

# Returns
- `Bool`: `true` if the event triggers the detector, `false` otherwise.
"""
function did_trigger(
    hit_map,
    efficiencies,
    #efficiencies::Dict{Int, Function},
    module_trigger_thresh::Int=3, # Number of particles or photons that must hit / be generated by a module to trigger it
    event_trigger_thresh::Int=30
)
    hit_map = filter( # Each entry in the hit_map is a vector of CorsikaEvents that hit a single module
        kv->sum(corsika_int_weight(kv[2], efficiencies)) >= module_trigger_thresh,
        hit_map
    )
    if length(hit_map) < 3 # At least this many modules must trigger (pass module_trigger_thresh)
        return false
    end
    
    nhit = get_nhit(hit_map, efficiencies)
    return nhit >= event_trigger_thresh
end

"""
    corsika_int_weight(event::CorsikaEvent, efficiencies::Dict{Int, Function}) -> Int

Calculates the interaction weight for a single `CorsikaEvent` using a generated seed.

This method generates a random seed based on the event's hash and then calls the
`corsika_int_weight` method that accepts a seed.

# Arguments
- `event::CorsikaEvent`: The CORSIKA event for which to calculate the weight.
- `efficiencies::Dict{Int, Function}`: A dictionary mapping particle PDG IDs (Int) to
  efficiency functions (Function).

# Returns
- `Int`: The calculated interaction weight.
"""
function corsika_int_weight(
    event::CorsikaEvent,
    efficiencies
)::Int
    seed = mod(hash(event), 2^32)
    return corsika_int_weight(event, efficiencies, seed)
end

"""
    corsika_int_weight(
        event::CorsikaEvent,
        efficiencies::Dict{Int, Function},
        seed::Int
    ) -> Int

Calculates the interaction weight for a single `CorsikaEvent` with a specified random seed.

This is the core method for calculating the interaction weight. It uses the provided
`seed` for reproducibility, retrieves the relevant efficiency function based on the
particle's PDG ID, and then applies the efficiency logic. If the efficiency function
is `accept_all` or `reject_all`, it samples based on an acceptance probability and
may apply Poissonian weighting for `event.weight`. Otherwise, it rounds the efficiency
output to determine the number of generated photons.

# Arguments
- `event::CorsikaEvent`: The CORSIKA event for which to calculate the weight.
- `efficiencies::Dict{Int, Function}`: A dictionary mapping particle PDG IDs (Int) to
  efficiency functions (Function).
- `seed::Int`: The random seed to use for sampling.

# Returns
- `Int`: The calculated interaction weight or number of photons.
"""
function corsika_int_weight(
    event::CorsikaEvent,
    efficiencies,
    seed::Int
)::Int
    seed!(seed)
    efficiency = efficiencies[event.pdg]

    # First if statement is for case we're counting particle hit, not photons
    if efficiency === accept_all || efficiency === reject_all
        ϵ = efficiency(event.kinetic_energy)
        if rand() > ϵ
            return 0
        end
        weight = event.weight
        if weight > 1
            weight = rand(Poisson(weight))
        end
        return weight
    end

    n_photons = round(efficiency(event.kinetic_energy)) # TODO: add statistical fluctuations
    return n_photons
end

"""
    corsika_int_weight(
        events::Vector{CorsikaEvent},
        efficiencies::Dict{Int, Function}
    ) -> Vector{Int}

Calculates interaction weights for a vector of `CorsikaEvent`s.

This method broadcasts the `corsika_int_weight` function (which takes a single event)
over a vector of `CorsikaEvent`s, applying the same `efficiencies` to all.

# Arguments
- `events::Vector{CorsikaEvent}`: A vector of CORSIKA events.
- `efficiencies::Dict{Int, Function}`: A dictionary mapping particle PDG IDs (Int) to
  efficiency functions (Function).

# Returns
- `Vector{Int}`: A vector of calculated interaction weights, one for each event.
"""
function corsika_int_weight(
    events::Vector{CorsikaEvent},
    efficiencies
)::Vector{Int}
    return [corsika_int_weight(event, efficiencies) for event in events]
end

