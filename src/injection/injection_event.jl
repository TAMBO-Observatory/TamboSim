struct InjectionEvent{T <: Real, U, V}
    event_id::Int
    entry_state::Particle{T,U}
    initial_state::Particle{T,U}
    final_state::Particle{T,U}
    genX::Quantity{T, V, typeof(u"g" / u"cm"^2)}
    mc_weight::T
    oneweight::T
end

const null_event = InjectionEvent(
    -1,
    null_particle,
    null_particle,
    null_particle,
    0.0*u"g" / u"cm"^2,
    0.0,
    0.0
)
