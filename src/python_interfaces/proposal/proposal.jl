const pp = PyNULL()
const particle_def_dict = Dict(
    11 => PyNULL(),
    13 => PyNULL(),
    15 => PyNULL(),
    -11 => PyNULL(),
    -13 => PyNULL(),
    -15 => PyNULL(),
)

const cross_section_dict = Dict(
    (11, "Air") => [PyNULL(), PyNULL(), PyNULL(), PyNULL()],
    (13, "Air") => [PyNULL(), PyNULL(), PyNULL(), PyNULL()],
    (15, "Air") => [PyNULL(), PyNULL(), PyNULL(), PyNULL()],
    (-11, "Air") => [PyNULL(), PyNULL(), PyNULL(), PyNULL(), PyNULL()],
    (-13, "Air") => [PyNULL(), PyNULL(), PyNULL(), PyNULL()],
    (-15, "Air") => [PyNULL(), PyNULL(), PyNULL(), PyNULL()],
    (11, "StandardRock") => [PyNULL(), PyNULL(), PyNULL(), PyNULL()],
    (13, "StandardRock") => [PyNULL(), PyNULL(), PyNULL(), PyNULL()],
    (15, "StandardRock") => [PyNULL(), PyNULL(), PyNULL(), PyNULL()],
    (-11, "StandardRock") => [PyNULL(), PyNULL(), PyNULL(), PyNULL(), PyNULL()],
    (-13, "StandardRock") => [PyNULL(), PyNULL(), PyNULL(), PyNULL()],
    (-15, "StandardRock") => [PyNULL(), PyNULL(), PyNULL(), PyNULL()],
)
const prop_cache = Dict()

function init_proposal(config)
    copy!(pp, pyimport("proposal"))
    pp.InterpolationSettings.tables_path = config["tablespath"]
    copy!(particle_def_dict[11], pp.particle.EMinusDef())
    copy!(particle_def_dict[13], pp.particle.MuMinusDef())
    copy!(particle_def_dict[15], pp.particle.TauMinusDef())
    copy!(particle_def_dict[-11], pp.particle.EPlusDef())
    copy!(particle_def_dict[-13], pp.particle.MuPlusDef())
    copy!(particle_def_dict[-15], pp.particle.TauPlusDef())

    pdg_lepton_ids = [11, 13, 15, -11, -13, -15]
    media = ["Air", "StandardRock"]
    for lepton_id in pdg_lepton_ids
        pdef = particle_def_dict[lepton_id]
        for medium in media
            xs = make_pp_crosssection(pdef, medium, config)
            ys = cross_section_dict[(lepton_id, medium)]
            for (x, y) in zip(xs, ys)
                copy!(y, x)
            end
            add_propagator_to_cache!(prop_cache, lepton_id, medium)
        end
    end
end

function make_pp_crosssection(particle_def, mediumname, config=config)
    ecut = config["ecut"] > 0 ? config["ecut"]*u"GeV" : Inf*u"GeV"
    cuts = pp.EnergyCutSettings(
        ustrip(ecut |> u"MeV"),
        config["vcut"],
        config["do_continuous"]
    )
    target = getproperty(pp.medium, mediumname)()
    cross = pp.crosssection.make_std_crosssection(;
        particle_def=particle_def,
        target=target,
        interpolate=config["do_interpolate"],
        cuts=cuts
    )
    return cross
end
function add_propagator_to_cache!(
    cache::Dict,
    lepton_id::Int,
    medium::String,
    density::Union{Quantity{T,mdim/ldim^3,typeof(u"g/cm^3")},Nothing}=nothing,
) where {T<:Real}
    if isnothing(density)
        pp_medium = getproperty(pp.medium, medium)()
        density = getproperty(pp_medium, "mass_density")
        density = convert(Float64, density) * u"g/cm^3"
    end

    particle_def = particle_def_dict[lepton_id]
    geometry = pp.geometry.Sphere(pp.Cartesian3D(), 1e20, 0)
    pp_density = pp.density_distribution.density_homogeneous(ustrip(density))
    pp_cross_section = cross_section_dict[(lepton_id, medium)]
    utility = make_pp_utility(particle_def, pp_cross_section)
    prop = pp.Propagator(particle_def, [(geometry, utility, pp_density)])
    cache[(lepton_id, medium)] = prop
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

include("loss.jl")
include("propagation.jl")
include("utilities.jl")
