struct ProposalResult{T}
    event_id::Int
    stochastic_losses::Vector{StochasticLoss{T}}
    continuous_loss::Quantity{T,edim,typeof(u"GeV")}
    decay_products::Vector{Particle{T}}
    propped_state::Particle{T}
    function ProposalResult(
        event_id::Int,
        stochastic_losses::Vector{StochasticLoss{T}},
        continuous_losses::Quantity{T,edim},
        decay_products::Vector{Particle{T}},
        propped_state::Particle{T}
        ) where {T<:Real}
        continuous_losses |> u"GeV"
        return new{T}(event_id, stochastic_losses, continuous_losses, decay_products, propped_state)
    end
end

function proposal_propagate(
    particle::Particle{T},
    earth::Earth{T},
    event_id=-1
) where {T<:Real}
    cs = CoordinateSystem(earth)
    ray = Ray(particle.position, particle.direction)
    ixs = intersect_all(earth, ray)

    densities = compute_density(ixs, particle.direction)
    lengths = compute_lengths(ixs)
    lepton_id = particle.pdg_id
    losses = StochasticLoss{T}[]
    secondaries = Particle{T}[]
    current_e, continuous_e, accrued_d = particle.energy, 0.0u"GeV", 0.0u"m"
    final_state = nothing
    for (l, density) in zip(lengths, densities)
        medium = density > 1u"g/cm^3" ? "StandardRock" : "Air"

        propagator = prop_cache[(lepton_id, medium)]
        lepton = pp.particle.ParticleState()
        lepton.position = pp.Cartesian3D([0,0,0])
        lepton.direction = pp.Cartesian3D([0,0,1])
        lepton.energy = ustrip(current_e |> u"MeV")
        lepton.propagated_distance = 0.0
        lepton.time = 0.0

        propped_state = propagator.propagate(lepton, ustrip(l |> u"cm"))
        pp_final_state = propped_state.final_state()
        current_e = pp_final_state.energy * u"MeV"

        for loss in propped_state.stochastic_losses()
            int_type = loss.type
            loss_e = loss.energy * u"MeV"
            dist = accrued_d + loss.position.z * u"cm"
            p = dist * particle.direction + particle.position
            l = StochasticLoss(int_type, loss_e, p)
            push!(losses, l)
        end
        
        x = sum([x.energy * u"MeV" for x in propped_state.continuous_losses()])
        continuous_e += x

        dist = accrued_d + pp_final_state.position.z * u"cm"
        p = dist * particle.direction + particle.position
        final_state = Particle(lepton_id, current_e, p, particle.direction)

        decay_products = propped_state.decay_products()
        if length(decay_products) > 0
            for sec in decay_products
                dist = accrued_d + sec.position.z * u"cm"
                p = dist * particle.direction + particle.position
                e = sec.energy * u"MeV"
                pdg_id = sec.type
                decay_product = Particle(pdg_id, e, p, particle.direction)
                push!(secondaries, decay_product)
            end
            break
        end
    end
    return ProposalResult(event_id, losses, continuous_e, secondaries, final_state)
end



#function init_proposal_cross_sections(config::Dict{String, Any})
#end
