using PyCall
using StaticArrays
using Rotations

# This PyNULL business is necessary to load PyOjects as constants
# This adds a significant speed up
const pp = PyNULL()
const TauMinusDef = PyNULL()
const TauPlusDef = PyNULL()
const MuMinusDef = PyNULL()
const MuPlusDef = PyNULL()
const EMinusDef = PyNULL()
const EPlusDef = PyNULL()
const EPlusAirCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL(), PyNULL()]
const EMinusAirCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL()]
const MuPlusAirCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL()]
const MuMinusAirCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL()]
const TauPlusAirCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL()]
const TauMinusAirCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL()]
const EPlusRockCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL(), PyNULL()]
const EMinusRockCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL()]
const MuPlusRockCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL()]
const MuMinusRockCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL()]
const TauPlusRockCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL()]
const TauMinusRockCross = [PyNULL(), PyNULL(), PyNULL(), PyNULL()]

#Base.@kwdef mutable struct ProposalConfig
#    ecut::Float64 = Inf
#    vcut::Float64 = 1e-2
#    do_interpolate::Bool = true
#    do_continuous::Bool = true
#    tablespath::String = realpath(
#        "$(@__DIR__)/../..//resources/proposal_tables/"
#    )
#end

struct ProposalPropagator
    particledef_dict::Dict
    crosssection_dict::Dict
end

struct Loss
    int_type::Int64
    energy::Float64
    position::SVector{3,Float64}
end

struct ProposalResult
    event_id::Int64
    stochastic_losses::Vector{Loss}
    continuous_losses::Loss
    did_decay::Bool
    decay_products::Vector{Particle}
    propped_state::Particle
end

function ProposalPropagator(config::Dict{String, Any})
    particledef_dict, crosssections_dict = (
        make_proposal_dicts(config)
    )
    return ProposalPropagator(particledef_dict, crosssections_dict)
end

function Loss(int_type::Int, e::Float64, pp_position::PyObject)
    position = position_from_pp_vector(pp_position)
    return Loss(int_type, e, position)
end

function (prop::ProposalPropagator)(
    event_id::Int64,
    particle::Particle,
    geo::Geometry,
    proposal_seed::Int
)

    @assert particle.pdg_mc in [15, 13, 11, -11, -13, -15] "$(particle) is not a charged lepton"
    pp.RandomGenerator.get().set_seed(proposal_seed)
    t = Track(particle.position, particle.direction, geo.box)
    segments = computesegments(t, geo)
    secondaries = propagate(
        event_id,
        particle,
        getfield.(segments, :medium_name),
        getfield.(segments, :density),
        getfield.(segments, :length),
        prop.crosssection_dict,
        prop.particledef_dict,
    )
    return ProposalResult(event_id, secondaries, particle)
end


#function (prop::ProposalPropagator)(
#    events::Vector{InjectionEvent},
#    geo::Geometry;
#    track_progress::Bool=true
#)
#    if track_progress
#        events = ProgressBar(events)
#    end
#    return [prop(event.final_state, geo) for event in events]
#end

function ProposalResult(event_id, secondaries, parent_particle)
    if typeof(secondaries)==ProposalResult
        return secondaries
    end
    r = LinearMap(RotY(-parent_particle.direction.θ) * RotZ(-parent_particle.direction.ϕ))
    t = Translation(-parent_particle.position)
    shift = inv(r ∘ t)
    losses = Loss[]
    for sec in secondaries.stochastic_losses()
        int_type = sec.type
        sec_e = sec.energy
        sec_e = sec.energy * units.MeV
        position = shift(position_from_pp_vector(sec.position))
        l = Loss(int_type, sec_e, position)
        push!(losses, l)
    end
    children = Particle[]
    for product in secondaries.decay_products()
        pdg_code = product.type
        energy = product.energy * units.MeV
        position = shift(position_from_pp_vector(product.position))
        direction = Direction(
            inv(r)(SVector{3}(product.direction.x, product.direction.y, product.direction.z))
        )
        #parent = parent_particle
        child = Particle(pdg_code, energy, position, direction)
        push!(children, child)
    end
    continuous_total = Loss(
        secondaries.continuous_losses()[1].type,
        sum([l.energy for l in secondaries.continuous_losses()]) * units.MeV,
        parent_particle.position
    )
    did_decay = length(children) > 0
    p = secondaries.final_state().position
    final_pos = shift(position_from_pp_vector(p))
    final_e = secondaries.final_state().energy * units.MeV
    final_state = Particle(
        parent_particle.pdg_mc,
        final_e,
        final_pos,
        parent_particle.direction,
    )
    return ProposalResult(
        event_id, losses, continuous_total, did_decay,
        children, final_state#, final_pos, final_e
    )
end

### Functions for showing structs

function position_from_pp_vector(pp_vector)
    return SVector{3}([pp_vector.x, pp_vector.y, pp_vector.z]) .* units.cm
end

function make_propagator(
    particle::Particle,
    media::Vector{String},
    densities::Vector{Float64},
    lengths::Vector{Float64},
    pp_crosssections_dict::Dict{Tuple{Int64, String}, Vector{PyObject}},
    pp_particle_dict::Dict{Int, PyObject}
)
    particle_def = pp_particle_dict[particle.pdg_mc]
    geometries =  make_pp_geometry_list(lengths)
    density_distributions = [make_pp_density_distribution(d) for d in densities]
    push!(
        density_distributions,
        make_pp_density_distribution(units.ρair0),
    )
    crosses = [pp_crosssections_dict[(particle.pdg_mc, m)] for m in media]
    push!(crosses, pp_crosssections_dict[(particle.pdg_mc, "Air")])
    utilities = [make_pp_utility(particle_def, cross) for cross in crosses]
    dumb_list = [x for x in zip(geometries, utilities, density_distributions)]
    prop = pp.Propagator(particle_def, dumb_list)
    return prop 
end

function propagate(
    event_id::Int64,
    chargedlepton::Particle,
    media::Vector{String},
    densities::Vector{Float64},
    lengths::Vector{Float64},
    pp_crosssections_dict::Dict{Tuple{Int64, String}, Vector{PyObject}},
    pp_particle_dict::Dict{Int, PyObject}
)
    # Double hack. We should fix this
    if chargedlepton.energy==0
        return ProposalResult(
            event_id,
            Loss[],
            Loss(-1, 0.0, SVector{3}([0,0,0])),
            false,
            Particle[],
            chargedlepton
        )
    end
    prop = make_propagator(
        chargedlepton,
        media,
        densities,
        lengths,
        pp_crosssections_dict,
        pp_particle_dict,
    )
    lepton = pp.particle.ParticleState()
    lepton.position = make_pp_vector(SVector{3}([0,0,0]))
    lepton.direction = make_pp_direction(Direction(0, 0, 1))
    lepton.energy = chargedlepton.energy / units.MeV
    lepton.propagated_distance = 0.0
    lepton.time = 0.0
    secondaries = prop.propagate(lepton)
    return secondaries
end

### Helper functions necessary for PROPOSAL ###
# These contain very little interesting logic
"""
    make_pp_vector(v::SVector{3})

TBW
"""
function make_pp_vector(v::SVector{3})
    v = v ./ units.cm
    return pp.Cartesian3D(v)
end

function make_pp_direction(d::Direction)
    return pp.Cartesian3D(d.proj)
end

function make_pp_utility(particle_def, cross)
    collection = pp.PropagationUtilityCollection()
    collection.displacement = pp.make_displacement(cross, true)
    collection.interaction = pp.make_interaction(cross, true)
    collection.time = pp.make_time(cross, particle_def, true)
    collection.decay = pp.make_decay(cross, particle_def, true)
    utility = pp.PropagationUtility(; collection=collection)
    return utility
end

function make_pp_geometry_list(lengths)
    geometries = PyObject[]
    start = 0
    end_ = 0
    for l in lengths
        end_ += l
        geo = make_pp_geometry(start, end_)
        push!(geometries, geo)
        start = end_
    end
    push!(geometries, make_pp_geometry(end_, 1e10*units.km))
    return geometries
end

function make_pp_geometry(start, end_)
    return pp.geometry.Sphere(pp.Cartesian3D(), end_ / units.cm, start / units.cm)
end

function make_pp_density_distribution(density)
    return pp.density_distribution.density_homogeneous(density / (units.gr / units.cm^3))
end

function make_proposal_dicts(config::Dict{String, Any})
    copy!(pp, pyimport("proposal"))
    pp.InterpolationSettings.tables_path = config["tablespath"]
    copy!(TauMinusDef, pp.particle.TauMinusDef())
    copy!(TauPlusDef, pp.particle.TauPlusDef())
    copy!(MuMinusDef, pp.particle.MuMinusDef())
    copy!(MuPlusDef, pp.particle.MuPlusDef())
    copy!(EMinusDef, pp.particle.EMinusDef())
    copy!(EPlusDef, pp.particle.EPlusDef())
    function make_pp_crosssection(particle_def, name, config=config)
        ecut = config["ecut"] > 0 ? config["ecut"] * units.GeV / units.MeV : Inf
        cuts = pp.EnergyCutSettings(
            ecut,
            config["vcut"],
            config["do_continuous"]
        )
        target = getproperty(pp.medium, name)()
        cross = pp.crosssection.make_std_crosssection(;
            particle_def=particle_def,
            target=target,
            interpolate=config["do_interpolate"],
            cuts=cuts
        )

        return cross
    end
    xs = make_pp_crosssection(EMinusDef, "Air")
    ys = EMinusAirCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end
    xs = make_pp_crosssection(EPlusDef, "Air")
    ys = EPlusAirCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end
    xs = make_pp_crosssection(MuMinusDef, "Air")
    ys = MuMinusAirCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end
    xs = make_pp_crosssection(MuPlusDef, "Air")
    ys = MuPlusAirCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end
    xs = make_pp_crosssection(TauMinusDef, "Air")
    ys = TauMinusAirCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end
    xs = make_pp_crosssection(TauPlusDef, "Air")
    ys = TauPlusAirCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end
    xs = make_pp_crosssection(EMinusDef, "StandardRock")
    ys = EMinusRockCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end
    xs = make_pp_crosssection(EPlusDef, "StandardRock")
    ys = EPlusRockCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end
    xs = make_pp_crosssection(MuMinusDef, "StandardRock")
    ys = MuMinusRockCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end
    xs = make_pp_crosssection(MuPlusDef, "StandardRock")
    ys = MuPlusRockCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end
    xs = make_pp_crosssection(TauMinusDef, "StandardRock")
    ys = TauMinusRockCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end
    xs = make_pp_crosssection(TauPlusDef, "StandardRock")
    ys = TauPlusRockCross
    for (x, y) in zip(xs, ys)
        copy!(y, x)
    end

    pp_particledef_dict= Dict(
        11 => EMinusDef,
        -11 => EPlusDef,
        13 => MuMinusDef,
        -13 => MuPlusDef,
        15 => TauMinusDef,
        -15 => TauPlusDef,
    )

    pp_crosssections_dict = Dict(
        (11, "Air") => EMinusAirCross,
        (-11, "Air") => EPlusAirCross,
        (13, "Air") => MuMinusAirCross,
        (-13, "Air") => MuPlusAirCross,
        (15, "Air") => TauMinusAirCross,
        (-15, "Air") => TauPlusAirCross,
        (11, "StandardRock") => EMinusRockCross,
        (-11, "StandardRock") => EPlusRockCross,
        (13, "StandardRock") => MuMinusRockCross,
        (-13, "StandardRock") => MuPlusRockCross,
        (15, "StandardRock") => TauMinusRockCross,
        (-15, "StandardRock") => TauPlusRockCross,
    )
    return pp_particledef_dict, pp_crosssections_dict
end
