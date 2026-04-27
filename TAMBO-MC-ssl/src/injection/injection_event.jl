"""
    InjectionEvent{T<:Real}

Represents a single particle injection event, tracking its state through different simulation stages.

# Fields
- `event_id::Int`: A unique identifier for the event.
- `entry_state::Particle{T}`: The state of the particle upon entering the simulation volume (e.g., at the injection plane).
- `initial_state::Particle{T}`: The initial state of the particle after relevant pre-simulation processing.
- `final_state::Particle{T}`: The final state of the particle after interaction or propagation.
- `weight_params::WeightParameters{T}`: Parameters used for calculating the event's Monte Carlo weight.
"""
struct InjectionEvent{T <: Real}
    event_id::Int
    entry_state::Particle{T}
    initial_state::Particle{T}
    final_state::Particle{T}
    weight_params::WeightParameters{T}
end

"""
    null_event(id::Int=0, initial_state::Union{Nothing, Particle}=nothing) -> InjectionEvent

Creates a "null" or default `InjectionEvent` for cases where a valid event could not be formed.

This function initializes an `InjectionEvent` with default (or null) particle states and
weight parameters, which can be useful for handling events that are rejected early in the
simulation process.

# Arguments
- `id::Int`: The event ID to assign to the null event. Defaults to 0.
- `initial_state::Union{Nothing, Particle}`: An optional `Particle` object to use as the initial state.
  If `nothing`, `null_particle` is used.

# Returns
- An `InjectionEvent` object configured as a null event.
"""
null_event(id=0, initial_state=nothing) = InjectionEvent(
    id,
    isnothing(initial_state) ? null_particle : initial_state,
    null_particle,
    null_particle,
    null_params
)
