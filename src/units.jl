Unitful.register(@__MODULE__)

const speedoflight = 299_792_458u"m" / u"s"
@unit MeVc2 "MeVc2" MeVc2 u"MeV"/speedoflight^2 false
@unit GeVc2 "GeVc2" GeVc2 u"GeV"/speedoflight^2 false
@unit e "e" e 1.602176634e-19 * u"C" false

const ldim = Unitful.𝐋
const mdim = Unitful.𝐌
const tdim = Unitful.𝐓
const qdim = Unitful.𝐓 * Unitful.𝐈
const edim = Unitful.𝐌 * Unitful.𝐋^2 / Unitful.𝐓^2
