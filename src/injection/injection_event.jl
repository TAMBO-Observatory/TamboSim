struct InjectionEvent{T <: Real}
    event_id::Int
    entry_state::Particle{T}
    initial_state::Particle{T}
    final_state::Particle{T}
    genX::Quantity{T, mdim/ldim^2, typeof(u"g" / u"cm"^2)}
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
