"""
PROPOSAL.jl interface for TAMBO

This module interfaces with the Julia PROPOSAL.jl package for charged lepton
propagation through matter.
"""

import PROPOSAL as PP
using JSON3

# Check if PROPOSAL library is available
const _proposal_available = Ref(false)
const _proposal_initialized = Ref(false)

# Cached propagators for different particle types and media
const _propagator_cache = Dict{Tuple{Int, String}, Any}()

# Propagator cache for the deep-Earth charged-lepton leg of neutrino injection,
# built with coarse energy-scaling cuts (absolute e_cut disabled, v_cut = 1e-3,
# matching TauRunner). Selected via `_run_proposal_segments(...; deep = true)`.
#
# Keyed by (lepton_id, density) rather than by medium name: the
# deep leg crosses PREM shells from crust (~2.6) to inner core (~13), and a
# propagator built on StandardRock's nominal 2.65 g/cm³ would under-count the
# column depth in the mantle and core by a factor of a few. Each entry carries
# the shell's density as an explicit `density_distribution` override.
#
# Built lazily, on first use of each (lepton, shell) pair. Interpolation tables
# depend only on medium composition and cuts, so only the first propagator per
# medium pays table-generation cost; the rest are ~0.1 s each. Lazy also means
# `init_proposal` does not need TauRunner's Earth to exist yet.
const _deep_propagator_cache = Dict{Tuple{Int, Float64}, Any}()
const _DEEP_ECUT = -1      # GeV; negative => absolute cut disabled (v_cut governs)
const _DEEP_VCUT = 1e-3
const _DEEP_CONT_RAND = true

# Cross-section parametrizations captured by `init_proposal`, so lazily built
# deep propagators use the same ones as the eager near-detector cache.
const _deep_cross_sections = Ref{Any}(nothing)

"""
    deep_propagator(lepton_id, mass_density) -> propagator

Deep-Earth propagator for `lepton_id` in a medium of density `mass_density`
(g/cm³), building and caching it on first use. Densities are rounded to six
significant digits before keying — relative rather than absolute, so air
(~1.2e-3 g/cm³) is resolved as sharply as inner core (~13). Callers pass PREM
shell averages, of which there are nine, so the cache stays small.
"""
function deep_propagator(lepton_id::Int, mass_density::Real)
    rho = Float64(mass_density)
    key = (lepton_id, round(rho, sigdigits=6))
    return get!(_deep_propagator_cache, key) do
        medium = rho > 1.0 ? "StandardRock" : "Air"
        path = generate_config(
            lepton_id, medium, _DEEP_ECUT, _DEEP_VCUT, _DEEP_CONT_RAND;
            cross_sections=_deep_cross_sections[], mass_density=rho,
        )
        create_propagator(lepton_id, path)
    end
end

# Config file paths (generated at runtime)
const _config_dir = Ref{String}("")

"""
    init_proposal(config)

Initializes the PROPOSAL.jl library and pre-computes propagator objects.

# Arguments
- `config`: A dictionary containing configuration parameters:
  - `tablespath`: Path for interpolation tables (used for config file storage)
  - `ecut`: Energy cut in GeV (default: 0.5)
  - `vcut`: Velocity cut fraction (default: 0.05)
  - `do_continuous`: Whether to use continuous randomization (default: true)
  - `brems_parametrization`: Bremsstrahlung parametrization (default: "KelnerKokoulinPetrukhin")
  - `brems_lpm`: Enable LPM effect for bremsstrahlung (default: true)
  - `epair_parametrization`: Pair production parametrization (default: "KelnerKokoulinPetrukhin")
  - `epair_lpm`: Enable LPM effect for pair production (default: true)
  - `ioniz_parametrization`: Ionization parametrization (default: "BetheBlochRossi")
  - `photo_parametrization`: Photonuclear parametrization (default: "AbramowiczLevinLevyMaor97")
  - `photo_shadow`: Photonuclear shadow effect (default: "ButkevichMikheyev")
"""
function init_proposal(config)
    # Check if PROPOSAL library is available
    if !PP.is_library_available()
        @warn """
        PROPOSAL.jl library not available. Charged lepton propagation will not work.
        See PROPOSAL.jl documentation for installation instructions.
        """
        _proposal_available[] = false
        return
    end

    _proposal_available[] = true

    # Set tables directory. ENV["PROPOSAL_TABLES_PATH"] must be set before calling
    # _sync_taurunner_to_proposal_path! so TauRunner's SphericalBodyPropagator bakes
    # in the correct path when it is rebuilt.
    _config_dir[] = get(config, "tablespath", joinpath(get(ENV, "TAMBO_DATA_PATH", tempdir()), "proposal_tables"))
    mkpath(_config_dir[])
    PP.set_tables_path(_config_dir[])
    ENV["PROPOSAL_TABLES_PATH"] = _config_dir[]
    _sync_taurunner_to_proposal_path!()

    # Generate and cache propagators for all particle types and media
    pdg_lepton_ids = [11, 13, 15, -11, -13, -15]
    media = ["Air", "StandardRock"]

    ecut = get(config, "ecut", 0.5)  # GeV
    vcut = get(config, "vcut", 0.05)
    do_continuous = get(config, "do_continuous", true)

    brems_param = get(config, "brems_parametrization", "KelnerKokoulinPetrukhin")
    brems_lpm = get(config, "brems_lpm", true)
    epair_param = get(config, "epair_parametrization", "KelnerKokoulinPetrukhin")
    epair_lpm = get(config, "epair_lpm", true)
    ioniz_param = get(config, "ioniz_parametrization", "BetheBlochRossi")
    photo_param = get(config, "photo_parametrization", "AbramowiczLevinLevyMaor97")
    photo_shadow = get(config, "photo_shadow", "ButkevichMikheyev")

    cross_sections = Dict(
        "brems" => Dict("parametrization" => brems_param, "lpm" => brems_lpm),
        "epair" => Dict("parametrization" => epair_param, "lpm" => epair_lpm),
        "ioniz" => Dict("parametrization" => ioniz_param),
        "photo" => Dict("parametrization" => photo_param, "shadow" => photo_shadow)
    )

    # Deep-Earth propagators are built on demand by `deep_propagator`, one per
    # (lepton, PREM shell density) actually traversed; stash the parametrizations
    # they need. Clear the cache so a re-init cannot serve propagators built with
    # a previous call's cross sections.
    _deep_cross_sections[] = cross_sections
    empty!(_deep_propagator_cache)

    for lepton_id in pdg_lepton_ids
        for medium in media
            config_path = generate_config(lepton_id, medium, ecut, vcut, do_continuous; cross_sections=cross_sections)
            propagator = create_propagator(lepton_id, config_path)
            _propagator_cache[(lepton_id, medium)] = propagator
        end
    end

    _proposal_initialized[] = true
end

"""
    generate_config(lepton_id, medium, ecut, vcut, do_continuous; cross_sections=nothing,
                    mass_density=nothing) -> String

Generates a PROPOSAL configuration JSON file for the given parameters.

`mass_density` (g/cm³), when given, is written as a homogeneous
`density_distribution` override on the sector, so the medium supplies the
composition while the density comes from the caller. This is how the deep-Earth
leg represents PREM shells whose density is nothing like StandardRock's nominal
2.65 g/cm³, and mirrors what TauRunner's own `generate_sphere_config` does.
Interpolation tables depend on composition and cuts but not on this override, so
overridden propagators reuse the tables built for the nominal one.

# Returns
- Path to the generated configuration file.
"""
function generate_config(
    lepton_id::Int, medium::String, ecut::Real, vcut::Real, do_continuous::Bool;
    cross_sections=nothing, mass_density=nothing
)
    # Map medium name to PROPOSAL format
    medium_name = lowercase(medium)
    if medium_name == "standardrock"
        medium_name = "standardrock"
    elseif medium_name == "air"
        medium_name = "air"
    end

    sector = Dict{String,Any}(
        "medium" => medium_name,
        "geometries" => [
            Dict(
                "hierarchy" => 0,
                "shape" => "sphere",
                "origin" => [0, 0, 0],
                "outer_radius" => 1e20
            )
        ]
    )

    if mass_density !== nothing
        sector["density_distribution"] =
            Dict("type" => "homogeneous", "mass_density" => Float64(mass_density))
    end

    config = Dict(
        "global" => Dict(
            "cuts" => Dict(
                "e_cut" => ecut < 0 ? 1e18 : ecut * 1000,  # Convert GeV to MeV; negative means continuous only (use large value)
                "v_cut" => vcut,
                "cont_rand" => do_continuous
            ),
            "tablesdir" => _config_dir[]
        ),
        "sectors" => [sector]
    )

    if cross_sections !== nothing
        config["CrossSections"] = cross_sections
    end

    # Write config to a temp dir (not _config_dir[], which may be read-only).
    # The filename must encode every parameter that changes the config: two
    # configs differing only in cuts or density would otherwise collide on one
    # path, and whichever was written last would silently win.
    particle_name = pdg_to_name(lepton_id)
    rho_tag = mass_density === nothing ? "nominal" : "rho$(round(Float64(mass_density), digits=4))"
    config_filename = "proposal_config_$(particle_name)_$(medium)_" *
                      "e$(ecut)_v$(vcut)_c$(do_continuous)_$(rho_tag).json"
    config_path = joinpath(tempdir(), config_filename)

    open(config_path, "w") do io
        JSON3.write(io, config)
    end

    return config_path
end

"""
    pdg_to_name(pdg_id) -> String

Converts a PDG ID to a particle name string.
"""
function pdg_to_name(pdg_id::Int)
    names = Dict(
        11 => "eminus",
        -11 => "eplus",
        13 => "muminus",
        -13 => "muplus",
        15 => "tauminus",
        -15 => "tauplus"
    )
    return get(names, pdg_id, "unknown")
end

"""
    create_propagator(lepton_id, config_path)

Creates a PROPOSAL propagator for the given particle type.
"""
function create_propagator(lepton_id::Int, config_path::String)
    if lepton_id == 11
        return PP.create_propagator_eminus(config_path)
    elseif lepton_id == -11
        return PP.create_propagator_eplus(config_path)
    elseif lepton_id == 13
        return PP.create_propagator_muminus(config_path)
    elseif lepton_id == -13
        return PP.create_propagator_muplus(config_path)
    elseif lepton_id == 15
        return PP.create_propagator_tauminus(config_path)
    elseif lepton_id == -15
        return PP.create_propagator_tauplus(config_path)
    else
        error("Unknown lepton PDG ID: $lepton_id")
    end
end

"""
    pdg_to_proposal_type(pdg_id) -> Int

Converts a PDG ID to a PROPOSAL particle type constant.
"""
function pdg_to_proposal_type(pdg_id::Int)
    type_map = Dict(
        11 => PP.PARTICLE_TYPE_EMINUS,
        -11 => PP.PARTICLE_TYPE_EPLUS,
        13 => PP.PARTICLE_TYPE_MUMINUS,
        -13 => PP.PARTICLE_TYPE_MUPLUS,
        15 => PP.PARTICLE_TYPE_TAUMINUS,
        -15 => PP.PARTICLE_TYPE_TAUPLUS
    )
    return get(type_map, pdg_id, PP.PARTICLE_TYPE_NONE)
end

"""
    is_proposal_available() -> Bool

Returns whether the PROPOSAL library is available and initialized.
"""
is_proposal_available() = _proposal_available[] && _proposal_initialized[]

include("loss.jl")
include("propagation.jl")
include("utilities.jl")
