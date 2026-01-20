"""
    proposal_propagate(particle::Particle, earth::Earth, seed=nothing) -> Tuple

Propagates a particle through the Earth using the PROPOSAL library.

The function calculates the particle's path and the densities it encounters. It then propagates
the particle through these segments, collecting information about stochastic losses, continuous
energy loss, and decay products.

# Arguments
- `particle::Particle`: The initial particle state.
- `earth::Earth`: The Earth model.
- `seed`: An optional seed for the random number generator.

# Returns
- A tuple containing:
    - `losses`: A vector of `Particle` objects representing stochastic losses.
    - `continuous_e`: The total continuous energy loss.
    - `secondaries`: A vector of `Particle` objects representing decay products.
    - `final_state`: The final `Particle` state after propagation.
"""
function proposal_propagate(
    particle::Particle{T},
    earth::Earth{T},
    seed=nothing
) where {T<:Real}
    cs = CoordinateSystem(earth)
    ray = Ray(particle)
    ixs = intersect_all(earth, ray)

    
    seed = isnothing(seed) ? rand(Int32) : seed
    pp.RandomGenerator.get().set_seed(seed)

    densities = compute_density(ixs, particle.direction)
    lengths = compute_lengths(ixs)
    lepton_id = particle.pdg
    losses = Particle{T}[]
    secondaries = Particle{T}[]
    current_e, continuous_e, accrued_d, accrued_t = particle.energy, 0.0u"GeV", 0.0u"m", particle.time
    final_state = nothing
    for (l, density) in zip(lengths, densities)
        medium = density > 1u"g/cm^3" ? "StandardRock" : "Air"

        propagator = prop_cache[(Int(lepton_id), medium)]
        lepton = pp.particle.ParticleState()
        lepton.position = pp.Cartesian3D([0,0,0])
        lepton.direction = pp.Cartesian3D(particle.direction.point)
        lepton.energy = ustrip(current_e |> u"MeV")
        lepton.propagated_distance = 0.0
        lepton.time = 0.0

        propped_state = propagator.propagate(lepton, ustrip(l |> u"cm"))
        pp_final_state = propped_state.final_state()
        current_e = pp_final_state.energy * u"MeV"

        for loss in propped_state.stochastic_losses()
            int_type = loss.type
            loss_e = loss.energy * u"MeV"
            dist = accrued_d + loss.propagated_distance * u"cm"
            loss_t = accrued_t + T(loss.time) * u"s"
            p = dist * particle.direction + particle.position
            dir = Direction([loss.direction.x, loss.direction.y, loss.direction.z], cs)
            l = Particle(ParticleType(int_type), loss_e, p, dir, loss_t)
            push!(losses, l)
        end
        
        x = sum([x.energy * u"MeV" for x in propped_state.continuous_losses()])
        continuous_e += x

        dist = accrued_d + pp_final_state.propagated_distance * u"cm"
        final_t = accrued_t + T(pp_final_state.time) * u"s"
        p = dist * particle.direction + particle.position
        final_state = Particle(lepton_id, current_e, p, particle.direction, final_t)

        decay_products = propped_state.decay_products()
        if length(decay_products) > 0
            for sec in decay_products
                dist = accrued_d + sec.propagated_distance * u"cm"
                sec_t = accrued_t + T(sec.time) * u"s"
                p = dist * particle.direction + particle.position
                e = sec.energy * u"MeV"
                pdg = sec.type
                dir = Direction([sec.direction.x, sec.direction.y, sec.direction.z], cs)
                decay_product = Particle(ParticleType(pdg), e, p, dir, sec_t)
                push!(secondaries, decay_product)
            end
            break
        end
        accrued_d += pp_final_state.propagated_distance * u"cm"
        accrued_t += T(pp_final_state.time) * u"s"
    end
    return losses, continuous_e, secondaries, final_state
end
