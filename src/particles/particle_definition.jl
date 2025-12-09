struct ParticleDefinition{T}
    mass::Quantity{T,mdim}
    lifetime::Quantity{T,tdim}
    charge::Quantity{T,qdim}
    α
    β
end

particle_parameters = Dict{Int, Tuple}(
    15 => (1.77686 * u"GeV"/speedoflight^2, 2.903e-13 * u"s"),
    -15 => (1.77686 * u"GeV"/speedoflight^2, 2.903e-13 * u"s"),
    13 => (0.1056583745 * u"GeV"/speedoflight^2, 2.1969811e-6 * u"s"),
    -13 => (0.1056583745 * u"GeV"/speedoflight^2, 2.1969811e-6 * u"s"),
    11 => (0.00051099895000 * u"GeV"/speedoflight^2, Inf * u"s"),
    -11 => (0.00051099895000 * u"GeV"/speedoflight^2, Inf * u"s"),
)

const range_parameters = Dict(
    13 => (1.76666667e-1 * u"GeV*cm^3/m/g", 2.0916666667e-4 * u"cm^3/m/g"),
    -13 => (1.76666667e-1 * u"GeV*cm^3/m/g", 2.0916666667e-4 * u"cm^3/m/g"),
    15 => (1.473684210526e3 * u"GeV*cm^3/m/g", 2.63e-5 * u"cm^3/m/g"),
    -15 => (1.473684210526e3 * u"GeV*cm^3/m/g", 2.63e-5 * u"cm^3/m/g"),
)
const tauminus = ParticleDefinition(1.77686*u"GeVc2", 2.903e-13*u"s", -1u"e")
const tauplus = ParticleDefinition(1.77686*u"GeVc2", 2.903e-13*u"s", 1u"e")
const muminus = ParticleDefinition(105.6583755*u"MeVc2", 2.196981e-6*u"s", -1u"e")
const muplus = ParticleDefinition(105.6583755*u"MeVc2", 2.196981e-6*u"s", 1u"e")
const eminus = ParticleDefinition(105.6583755*u"MeVc2", 2.196981e-6*u"s", -1u"e")
const eplus = ParticleDefinition(0.00051099895000 * u"GeV"/speedoflight^2, Inf*u"s", 1u"e")

const particle_defs(
    eplus=ParticleDefinition(105.6583755*u"MeVc2", Inf*u"s", 1*electron_charge, )
)
