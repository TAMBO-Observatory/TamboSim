using Pkg
Pkg.activate("/n/home02/thomwg11/tambo/TAMBO-MC/Tambo")
using Tambo
using JLD2

function calc_triggered_event_rate(triggered_events)
           γ = 2.52
           norm = 1.8e-18 / units.GeV / units.cm^2 / units.second * (1 /(100units.TeV))^-γ
           pl = Tambo.PowerLaw(γ, 100units.GeV, 1e9units.GeV, norm)
           fluxes = pl.(map(t -> t.initial_state.energy, triggered_events))
           wgts = oneweight.(triggered_events, Ref(injector), Ref(injector.xs)) ./ 20000 # FIXME hack
           global_fit_rates = fluxes .* wgts
           return global_fit_rates
end

SIMULATION_FILE = "/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/will_misc/larger_valley/larger_valley_00000_00001.jld2"
sim = jldopen(SIMULATION_FILE)
config = Simulation("/n/home02/thomwg11/tambo/TAMBO-MC/resources/configuration_examples/larger_valley.toml")
geo = Tambo.Geometry(config.config["geometry"])
injector = Tambo.Injector(config.config["injection"], geo);

triggered_events_white_paper = load("/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/will_misc/larger_valley/triggered/00000_00001/2300_3700_5000_150/triggered_events_150_whitepaper/triggered_events_mod_3_event_30.jld2")["triggered_events"]
rates_white_paper = calc_triggered_event_rate(triggered_events_white_paper)
events_per_year_wp = sum(rates_white_paper) * 1 * (5000/702) * 1 * 10^7.5 * units.second

println("Events / year / 5000 modules: $(events_per_year_wp)")
