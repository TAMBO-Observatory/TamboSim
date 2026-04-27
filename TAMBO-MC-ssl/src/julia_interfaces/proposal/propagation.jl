"""
    proposal_propagate(particle::Particle, earth::Earth, seed=nothing) -> Tuple

Propagates a particle through the Earth using the PROPOSAL.jl library.

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

    if !is_proposal_available()
        error("PROPOSAL not available. Call init_proposal(config) first.")
    end

    cs = CoordinateSystem(earth)
    ray = Ray(particle)
    ixs = intersect_all(earth, ray)

    # Set random seed if provided
    seed = isnothing(seed) ? rand(Int32) : Int32(mod(seed, typemax(Int32)))
    PP.set_random_seed(seed)

    densities = compute_density(ixs, particle.direction)
    lengths = compute_lengths(ixs)
    lepton_id = Int(particle.pdg)

    losses = Particle{T}[]
    secondaries = Particle{T}[]
    current_e = particle.energy
    continuous_e = 0.0u"GeV"
    accrued_d = 0.0u"m"
    accrued_t = particle.time
    final_state = nothing

    for (l, density) in zip(lengths, densities)
        medium = density > 1u"g/cm^3" ? "StandardRock" : "Air"

        propagator = _propagator_cache[(lepton_id, medium)]

        # Create PROPOSAL particle state
        # PROPOSAL uses MeV for energy and cm for distance
        particle_type = pdg_to_proposal_type(lepton_id)
        dir = particle.direction.point
        state = PP.ParticleState(
            particle_type,
            0.0, 0.0, 0.0,      # position (cm)
            dir[1], dir[2], dir[3],  # direction
            ustrip(current_e |> u"MeV");  # energy (MeV)
            time=0.0,
            propagated_distance=0.0
        )

        # Propagate through this segment
        max_distance = ustrip(l |> u"cm")
        propped_result = PP.propagate(propagator, state; max_distance=max_distance, min_energy=0.0)

        # Get final state
        pp_final_state = PP.get_final_state(propped_result)
        current_e = PP.get_energy(pp_final_state) * u"MeV"

        # Process stochastic losses
        n_stochastic = PP.get_stochastic_losses_count(propped_result)
        for i in 0:(n_stochastic - 1)
            loss = PP.get_stochastic_loss_at(propped_result, i)

            int_type = PP.get_type(loss)
            loss_e = PP.get_energy(loss) * u"MeV"
            prop_dist = PP.get_propagated_distance(loss) * u"cm"
            loss_time = PP.get_time(loss) * u"s"

            dist = accrued_d + prop_dist
            loss_t = accrued_t + T(ustrip(loss_time |> u"s")) * u"s"
            p = dist * particle.direction + particle.position

            pp_dir = PP.get_direction(loss)
            dir_vec = [PP.get_x(pp_dir), PP.get_y(pp_dir), PP.get_z(pp_dir)]
            dir = Direction(dir_vec, cs)

            l_particle = Particle(ParticleType(int_type), loss_e, p, dir, loss_t)
            push!(losses, l_particle)
        end

        # Get continuous energy loss directly from PROPOSAL
        continuous_e += PP.get_total_continuous_energy_loss(propped_result) * u"MeV"

        # Update final state
        final_dist = accrued_d + PP.get_propagated_distance(pp_final_state) * u"cm"
        final_t = accrued_t + T(PP.get_time(pp_final_state)) * u"s"
        p = final_dist * particle.direction + particle.position
        final_state = Particle(ParticleType(lepton_id), current_e, p, particle.direction, final_t)

        # Extract decay products if PROPOSAL reports a decay
        if PP.has_decay(propped_result)
            max_products = 10
            types_arr = zeros(Int32, max_products)
            energies_arr = zeros(Float64, max_products)
            dx_arr = zeros(Float64, max_products)
            dy_arr = zeros(Float64, max_products)
            dz_arr = zeros(Float64, max_products)

            n_products = PP.get_decay_products_to_array(
                propped_result, types_arr, energies_arr,
                dx_arr, dy_arr, dz_arr
            )

            for j in 1:n_products
                dp_dir = Direction([dx_arr[j], dy_arr[j], dz_arr[j]], cs)
                dp = Particle(
                    ParticleType(types_arr[j]),
                    energies_arr[j] * u"MeV",
                    final_state.position,
                    dp_dir,
                    final_state.time
                )
                push!(secondaries, dp)
            end
            break
        end

        accrued_d += PP.get_propagated_distance(pp_final_state) * u"cm"
        accrued_t += T(PP.get_time(pp_final_state)) * u"s"
    end

    return losses, continuous_e, secondaries, final_state
end

"""
    proposal_propagate_to_air(particle::Particle, earth::Earth, plane::Plane, seed=nothing) -> Tuple

Propagates a particle through Earth segments using PROPOSAL.jl, stopping at the last
rock→air interface before the observation plane. If the tau reaches that interface
alive, it is returned as `air_entry_state` so it can be handed directly to CORSIKA.

If the tau decays in rock before reaching the air interface, the decay products are
returned as usual (same as `proposal_propagate`).

# Arguments
- `particle::Particle`: The initial particle state.
- `earth::Earth`: The Earth model.
- `plane::Plane`: The observation plane (used to determine which air interface is relevant).
- `seed`: An optional seed for the random number generator.

# Returns
- A tuple containing:
    - `losses`: A vector of `Particle` objects representing stochastic losses.
    - `continuous_e`: The total continuous energy loss.
    - `secondaries`: A vector of `Particle` objects representing decay products.
    - `final_state`: The final `Particle` state after propagation.
    - `air_entry_state`: The `Particle` at the last rock→air boundary, or `nothing` if it decayed in rock.
"""
function proposal_propagate_to_air(
    particle::Particle{T},
    earth::Earth{T},
    plane::Plane{T},
    seed=nothing
) where {T<:Real}

    if !is_proposal_available()
        error("PROPOSAL not available. Call init_proposal(config) first.")
    end

    cs = CoordinateSystem(earth)
    ray = Ray(particle)
    ixs = intersect_all(earth, ray)

    # Set random seed if provided
    seed = isnothing(seed) ? rand(Int32) : Int32(mod(seed, typemax(Int32)))
    PP.set_random_seed(seed)

    densities = compute_density(ixs, particle.direction)
    lengths = compute_lengths(ixs)

    # Find the observation plane intersection distance
    _, plane_t = find_intersection(ray, plane)

    # Find the index of the last rock→air transition before the plane.
    # A rock→air transition is where density goes from >1 g/cm³ to ≤1 g/cm³.
    last_rock_idx = nothing
    cumulative_d = zero(T) * u"m"
    for i in 1:length(densities)
        cumulative_d += lengths[i]
        is_rock = densities[i] > 1u"g/cm^3"
        is_next_air = (i < length(densities)) && (densities[i+1] <= 1u"g/cm^3")
        before_plane = isnothing(plane_t) || cumulative_d <= plane_t
        if is_rock && is_next_air && before_plane
            last_rock_idx = i
        end
    end

    # If we found a rock→air boundary, propagate up to and including last_rock_idx.
    # Otherwise, propagate through all segments (fallback to normal behavior).
    max_segment = isnothing(last_rock_idx) ? length(densities) : last_rock_idx

    lepton_id = Int(particle.pdg)
    losses = Particle{T}[]
    secondaries = Particle{T}[]
    current_e = particle.energy
    continuous_e = 0.0u"GeV"
    accrued_d = 0.0u"m"
    accrued_t = particle.time
    final_state = nothing
    air_entry_state = nothing
    decayed = false

    for seg_idx in 1:max_segment
        l = lengths[seg_idx]
        density = densities[seg_idx]
        medium = density > 1u"g/cm^3" ? "StandardRock" : "Air"

        propagator = _propagator_cache[(lepton_id, medium)]

        # Create PROPOSAL particle state
        # PROPOSAL uses MeV for energy and cm for distance
        particle_type = pdg_to_proposal_type(lepton_id)
        dir = particle.direction.point
        state = PP.ParticleState(
            particle_type,
            0.0, 0.0, 0.0,           # position (cm)
            dir[1], dir[2], dir[3],  # direction
            ustrip(current_e |> u"MeV");  # energy (MeV)
            time=0.0,
            propagated_distance=0.0
        )

        # Propagate through this segment
        max_distance = ustrip(l |> u"cm")
        propped_result = PP.propagate(propagator, state; max_distance=max_distance, min_energy=0.0)

        # Get final state
        pp_final_state = PP.get_final_state(propped_result)
        current_e = PP.get_energy(pp_final_state) * u"MeV"

        # Process stochastic losses
        n_stochastic = PP.get_stochastic_losses_count(propped_result)
        for i in 0:(n_stochastic - 1)
            loss = PP.get_stochastic_loss_at(propped_result, i)

            int_type = PP.get_type(loss)
            loss_e = PP.get_energy(loss) * u"MeV"
            prop_dist = PP.get_propagated_distance(loss) * u"cm"
            loss_time = PP.get_time(loss) * u"s"

            dist = accrued_d + prop_dist
            loss_t = accrued_t + T(ustrip(loss_time)) * u"s"
            p = dist * particle.direction + particle.position

            pp_dir = PP.get_direction(loss)
            dir_vec = [PP.get_x(pp_dir), PP.get_y(pp_dir), PP.get_z(pp_dir)]
            loss_dir = Direction(dir_vec, cs)

            l_particle = Particle(ParticleType(int_type), loss_e, p, loss_dir, loss_t)
            push!(losses, l_particle)
        end

        # Get continuous energy loss directly from PROPOSAL
        continuous_e += PP.get_total_continuous_energy_loss(propped_result) * u"MeV"

        # Update final state
        final_dist = accrued_d + PP.get_propagated_distance(pp_final_state) * u"cm"
        final_t = accrued_t + T(PP.get_time(pp_final_state)) * u"s"
        p = final_dist * particle.direction + particle.position
        final_state = Particle(ParticleType(lepton_id), current_e, p, particle.direction, final_t)

        # Extract decay products if PROPOSAL reports a decay
        if PP.has_decay(propped_result)
            max_products = 10
            types_arr = zeros(Int32, max_products)
            energies_arr = zeros(Float64, max_products)
            dx_arr = zeros(Float64, max_products)
            dy_arr = zeros(Float64, max_products)
            dz_arr = zeros(Float64, max_products)

            n_products = PP.get_decay_products_to_array(
                propped_result, types_arr, energies_arr,
                dx_arr, dy_arr, dz_arr
            )

            for j in 1:n_products
                dp_dir = Direction([dx_arr[j], dy_arr[j], dz_arr[j]], cs)
                dp = Particle(
                    ParticleType(types_arr[j]),
                    energies_arr[j] * u"MeV",
                    final_state.position,
                    dp_dir,
                    final_state.time
                )
                push!(secondaries, dp)
            end
            decayed = true
            break
        end

        accrued_d += PP.get_propagated_distance(pp_final_state) * u"cm"
        accrued_t += T(PP.get_time(pp_final_state)) * u"s"
    end

    # If the tau survived through all rock segments up to the air interface, record it
    if !decayed && !isnothing(last_rock_idx)
        air_entry_state = final_state
    end

    return losses, continuous_e, secondaries, final_state, air_entry_state
end
