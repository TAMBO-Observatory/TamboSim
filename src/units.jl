const speedoflight = 299_792_458u"m" / u"s"
const MeVc2 = u"MeV"/speedoflight^2
const GeVc2 = u"GeV"/speedoflight^2
const e = 1.602176634e-19 * u"C"

const ldim = Unitful.𝐋
const mdim = Unitful.𝐌
const tdim = Unitful.𝐓
const qdim = Unitful.𝐓 * Unitful.𝐈
const edim = Unitful.𝐌 * Unitful.𝐋^2 / Unitful.𝐓^2
