struct Injector
    nu_pdg::Int
    powerlaw::PowerLaw
    xs::CrossSection
    anglesampler::UniformAngularSampler
    injectionshape::AbstractInjectionShape
    geo::Geometry
end

struct InjectionEvent
    event_id::Int
    entry_state::Particle
    initial_state::Particle
    final_state::Particle
    genX::Float64
    mc_weight::Float64
    oneweight::Float64
end

function Injector(config::Dict, geo::Geometry)
    pl = PowerLaw(
        config["gamma"],
        config["emin"] * units.GeV,
        config["emax"] * units.GeV
    )
    xs = CrossSection(
        config["xs_dir"],
        config["xs_model"],
        config["nu_pdg"],
        config["interaction"]
    )
    anglesampler = UniformAngularSampler(
        deg2rad(config["thetamin"]),
        deg2rad(config["thetamax"]),
        deg2rad(config["phimin"]),
        deg2rad(config["phimax"])
    )

    if "r_injection" in keys(config) && "l_endcap" in keys(config)
        injectionshape = SymmetricInjectionCylinder(
            config["r_injection"] * units.m,
            config["l_endcap"] * units.m
        )
    elseif "length" in keys(config) && "width" in keys(config)
        injectionshape = InjectionPlane(
            config["length"] * units.m,
            config["width"] * units.m,
            geo.tambo_normal.proj
        )
    else
        error("Unknown options for loading injection shape")
    end
    return Injector(config["nu_pdg"], pl, xs, anglesampler, injectionshape, geo)
end

function inject_event(injector::Injector, event_id::Int, tr_seed::Int)
    event = inject_event(
        event_id,
        injector.nu_pdg,
        injector.powerlaw,
        injector.xs,
        injector.anglesampler,
        injector.injectionshape,
        injector.geo,
        tr_seed
    )
    return event
end

function sample_interaction_vertex(
    endcap_distance::Float64,
    closest_approach::SVector{3},
    d::Direction,
    range::Float64,
    geo::Geometry
)
    track = Track(closest_approach, reverse(d), geo.box)
    segments = computesegments(track, geo)
    tot_X = endcapcolumndepth(track, endcap_distance, range, segments)
    X = rand(Uniform(0.0, tot_X))
    λ_int = inversecolumndepth(track, X, geo, segments)
    p_int = track(λ_int)
    return p_int, tot_X
end

"""
    endcapcolumndepth(t::Track, l_endcap::Float64, range::Float64, segments::Vector{Segment})

TBW
"""
function endcapcolumndepth(
    t::Track,
    l_endcap::Float64,
    range::Float64,
    segments::Vector{Segment}
)
    cd = totalcolumndepth(t, segments)
    if t.norm <= l_endcap
        return cd
    end
    cd_endcap = minimum([columndepth(t, l_endcap / t.norm, segments) + range, cd])
    return cd_endcap
end

function determine_injection_start(
    closest_approach::SVector{3},
    boundary::SVector{3},
    geo::Geometry
)
    track = Track(closest_approach, boundary)
    segments = computesegments(track, geo)
    if length(segments)==1
        return closest_approach, false
    end

    start = closest_approach
    saw_air, no_endcap = false, false
    for segment in segments
        saw_air = saw_air || segment.medium_name=="Air"
        is_rock = segment.medium_name=="StandardRock"
        right_side = dot(geo.plane.n̂.proj, segment.pstart) > 0
        if saw_air && is_rock && right_side
            start = segment.pstart
            break
        end
    end
    return start, no_endcap
end

"""

TBW
"""
function inject_event(
    event_id::Int,
    ν_pdg::Int,
    power_law::PowerLaw,
    xs::CrossSection,
    anglesampler::UniformAngularSampler,
    cylinder::SymmetricInjectionCylinder,
    geo::Geometry,
    tr_seed::Int
)
    # Randomly sample direction
    direction = Direction(rand(anglesampler)...)
    # Rotation to plane perpindicular to direction
    rotator = (RotX(direction.θ) * RotZ(π / 2 - direction.ϕ))'
    # Find point of closest approach
    closest_approach = rotator * rand(cylinder)
    # Find where the particle entered the TAMBO region
    xb = intersect(closest_approach, reverse(direction), geo.box)

    # Sample initial neutrino energy
    proposed_e_init = rand(power_law)
    proposed_particle = Particle(ν_pdg, proposed_e_init, xb, direction)
    particle_entry, physX = tr_propagate(proposed_particle, geo.tambo_offset.z, tr_seed)
    # Set energy of neutrino when enters the box
    e_final = rand(xs, particle_entry.energy)

    # Find where to start counting CD from
    injection_start, no_endcap = determine_injection_start(closest_approach, xb, geo)
    l_endcap = cylinder.l_endcap
    if no_endcap
        l_endcap = 0.0
    end
    range = lepton_range(e_final, ν_pdg - sign(ν_pdg))
    if range > 0
        p_int, genX = sample_interaction_vertex(l_endcap, closest_approach, direction, range, geo)
    else
        p_int, genX = closest_approach, floatmin()
    end
    final_state = Particle(ν_pdg - sign(ν_pdg), e_final, p_int, direction)

    mc_weight = 1 / p_mc(
        proposed_e_init,
        particle_entry.energy,
        e_final,
        direction.theta,
        direction.phi,
        p_int,
        genX,
        power_law,
        xs,
        anglesampler,
        cylinder,
        geo
    )
    oneweight = mc_weight * p_phys(
        particle_entry.energy,
        e_final,
        genX,
        p_int,
        xs,
        geo
    )
    if isnan(oneweight)
        oneweight = 0.0
    end

    event = InjectionEvent(
        event_id,
        particle_entry,
        proposed_particle,
        final_state,
        genX,
        mc_weight,
        oneweight
    )
    return event
end
