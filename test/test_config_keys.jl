# TamboSim rejects any config key it does not recognize: each stage checks the
# table it is given, and check_config checks a whole file. These tests cover
# the per-table key sets, that each stage rejects a bad key before it does any
# work, and that every config tracked in the repo passes.

# Every tracked config. Not a readdir of resources/configuration_examples/:
# local checkouts keep untracked scratch configs there, many with retired keys.
const _SHIPPED_CONFIGS = ("tau_neutrino_cc.toml", "muon_neutrino_cc.toml",
                          "cosmic_ray_proton.toml", "atmospheric_muon.toml")
# The corsika_binary suite's own top-level keys (HARNESS_KEYS in
# test/corsika_binary/1_plan.jl).
const _HARNESS_KEYS = ("name", "description", "max_showers", "determinism_check", "baseline")

_shipped_config(f) =
    TOML.parsefile(joinpath(_TAMBOSIM_PATH, "resources", "configuration_examples", f))

# A valid CosmicRayInjection table (test_run_corsika.jl's helper is not loaded
# when this suite runs alone).
_key_test_cr_config() = Dict{String,Any}(
    "strategy" => "CosmicRayInjection", "seed" => 42, "nevent" => 2, "pdg" => 2212,
    "gamma" => 2.7, "emin" => 1e3, "emax" => 1e7,
    "thetamin" => 91.0, "thetamax" => 130.0, "phimin" => 0.0, "phimax" => 360.0,
    "altitude" => 50.0,
)

# The message of the ErrorException `f` throws, or `nothing` if it returns.
function _config_error(f)
    try
        f()
    catch e
        e isa ErrorException && return e.msg
        rethrow()
    end
    return nothing
end

_rejects(f, needles...) = (msg = _config_error(f);
                           !isnothing(msg) && all(n -> occursin(n, msg), needles))

function run_config_key_tests()
    @testset "tracked configs pass" begin
        test_tracked_configs_pass()
    end
    @testset "check_config" begin
        test_check_config_rejects()
    end
    @testset "[injection]" begin
        test_injection_keys()
    end
    @testset "[proposal]" begin
        test_proposal_keys()
    end
end

function test_tracked_configs_pass()
    for f in _SHIPPED_CONFIGS
        @test isnothing(TamboSim.check_config(_shipped_config(f)))
    end
    suite = joinpath(_TAMBOSIM_PATH, "test", "corsika_binary", "configs")
    for f in filter(endswith(".toml"), readdir(suite))
        cfg = TOML.parsefile(joinpath(suite, f))
        @test isnothing(TamboSim.check_config(cfg; extra_keys=_HARNESS_KEYS))
    end
end

function test_check_config_rejects()
    cfg = _shipped_config("tau_neutrino_cc.toml")   # NeutrinoInjection

    # An unknown top-level table, unless the caller declares it.
    bad = deepcopy(cfg)
    bad["detector"] = Dict{String,Any}()
    @test _rejects(() -> TamboSim.check_config(bad), "top level", "\"detector\"")
    @test isnothing(TamboSim.check_config(bad; extra_keys=("detector",)))

    bad = deepcopy(cfg)
    bad["geometry"]["gc_path"] = "gcd.jld2"
    @test _rejects(() -> TamboSim.check_config(bad), "[geometry]", "\"gc_path\"")

    bad = deepcopy(cfg)
    bad["proposal"] = 1
    @test _rejects(() -> TamboSim.check_config(bad), "[proposal] must be a table")

    # Each stage table is checked as its stage would check it; `altitude` is
    # only read by CosmicRayInjection.
    for (section, key) in (("injection", "altitude"), ("proposal", "do_interpolate"),
                           ("corsika", "gammacut"))
        bad = deepcopy(cfg)
        bad[section][key] = 1
        @test _rejects(() -> TamboSim.check_config(bad), "[$section]", repr(key))
    end

    bad = deepcopy(cfg)
    delete!(bad["injection"], "strategy")
    @test _rejects(() -> TamboSim.check_config(bad), "missing `strategy`")
end

function test_injection_keys()
    check = TamboSim.check_injection_config
    # A strategy accepts its own keys and rejects keys only another one reads.
    @test isnothing(check(Dict("strategy" => "CosmicRayInjection", "A" => 56, "Z" => 26,
                               "altitude" => 10.0), "CosmicRayInjection"))
    @test _rejects(() -> check(Dict("xs_location" => "xs.h5"), "CosmicRayInjection"),
                   "\"xs_location\"", "CosmicRayInjection")
    @test _rejects(() -> check(Dict("altitude" => 10.0), "MuonNeutrinoInjection"),
                   "\"altitude\"")
    @test _rejects(() -> check(Dict{String,Any}(), "GlashowInjection"),
                   "unknown strategy")

    # inject! and the backends reject before adding a frame.
    frames = load_frames(_GEOMETRY_PATH)
    n_frames = length(frames)
    cr = merge(_key_test_cr_config(), Dict{String,Any}("pinecone" => 1))
    @test _rejects(() -> inject!(frames, cr), "\"pinecone\"")
    @test _rejects(() -> TamboSim.inject_cosmicrays!(frames, cr), "\"pinecone\"")
    nu = merge(_key_test_cr_config(), Dict{String,Any}("strategy" => "NeutrinoInjection"))
    @test _rejects(() -> inject!(frames, nu), "\"altitude\"", "NeutrinoInjection")
    # inject_neutrinos! serves both neutrino strategies; the error names the config's.
    mu = merge(nu, Dict{String,Any}("strategy" => "MuonNeutrinoInjection"))
    @test _rejects(() -> inject!(frames, mu), "\"altitude\"", "MuonNeutrinoInjection")
    @test length(frames) == n_frames
end

function test_proposal_keys()
    check = TamboSim.check_proposal_config
    @test isnothing(check(Dict("seed" => 1, "tablespath" => "tables", "ecut" => -1,
                               "vcut" => 0.01, "do_continuous" => true)))
    # Retired keys still found in older configs.
    for key in ("do_interpolate", "track_progress")
        @test _rejects(() -> check(Dict(key => true)), "[proposal]", repr(key))
    end

    # init_proposal rejects before it creates the tables directory.
    tables = joinpath(mktempdir(), "tables")
    @test _rejects(() -> TamboSim.init_proposal(Dict("tablespath" => tables,
                                                     "do_interpolate" => true)),
                   "\"do_interpolate\"")
    @test !ispath(tables)

    # proposal_propagation! rejects before it looks for (or stamps) an M frame:
    # these frames have none, so any later failure would read differently.
    frames = load_frames(_GEOMETRY_PATH)
    @test _rejects(() -> proposal_propagation!(frames, Dict{String,Any}("do_interpolate" => true)),
                   "\"do_interpolate\"")
end

if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Config Keys" begin
        run_config_key_tests()
    end
end
