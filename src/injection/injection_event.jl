struct InjectionEvent{T <: Real}
    event_id::Int
    entry_state::Particle{T}
    initial_state::Particle{T}
    final_state::Particle{T}
    weight_params::WeightParameters{T}
end

null_event(id=0, initial_state=nothing) = InjectionEvent(
    id,
    isnothing(initial_state) ? null_particle : initial_state,
    null_particle,
    null_particle,
    null_params
)
