struct ParticleDefinition{T}
    mass::Quantity{T,mdim}
    lifetime::Quantity{T,tdim}
    charge::Quantity{T,qdim}
end

const tauminus = ParticleDefinition(1.77686*u"GeVc2", 2.903e-13*u"s", -1u"e")
const tauplus = ParticleDefinition(1.77686*u"GeVc2", 2.903e-13*u"s", 1u"e")
const muminus = ParticleDefinition(105.6583755*u"MeVc2", 2.196981e-6*u"s", -1u"e")
const muplus = ParticleDefinition(105.6583755*u"MeVc2", 2.196981e-6*u"s", 1u"e")
const eminus = ParticleDefinition(105.6583755*u"MeVc2", 2.196981e-6*u"s", -1u"e")
const eplus = ParticleDefinition(105.6583755*u"MeVc2", 2.196981e-6*u"s", 1u"e")
