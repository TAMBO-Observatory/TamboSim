# =============================================================================
# Particle Definitions
# Mass, lifetime, and charge for common particles (PDG 2024 values)
# =============================================================================

# -----------------------------------------------------------------------------
# Leptons
# -----------------------------------------------------------------------------
# Electrons (PDG ID: 11, -11)
const eminus = ParticleDefinition(0.51099895*u"MeVc2", Inf*u"s", -1u"e")
const eplus = ParticleDefinition(0.51099895*u"MeVc2", Inf*u"s", 1u"e")

# Muons (PDG ID: 13, -13)
const muminus = ParticleDefinition(105.6583755*u"MeVc2", 2.1969811e-6*u"s", -1u"e")
const muplus = ParticleDefinition(105.6583755*u"MeVc2", 2.1969811e-6*u"s", 1u"e")

# Taus (PDG ID: 15, -15)
const tauminus = ParticleDefinition(1776.86*u"MeVc2", 2.903e-13*u"s", -1u"e")
const tauplus = ParticleDefinition(1776.86*u"MeVc2", 2.903e-13*u"s", 1u"e")

# Neutrinos (PDG ID: 12, 14, 16 and antiparticles)
# Neutrino masses are effectively zero for simulation purposes
const nu_e = ParticleDefinition(0.0*u"MeVc2", Inf*u"s", 0u"e")
const nu_e_bar = ParticleDefinition(0.0*u"MeVc2", Inf*u"s", 0u"e")
const nu_mu = ParticleDefinition(0.0*u"MeVc2", Inf*u"s", 0u"e")
const nu_mu_bar = ParticleDefinition(0.0*u"MeVc2", Inf*u"s", 0u"e")
const nu_tau = ParticleDefinition(0.0*u"MeVc2", Inf*u"s", 0u"e")
const nu_tau_bar = ParticleDefinition(0.0*u"MeVc2", Inf*u"s", 0u"e")

# -----------------------------------------------------------------------------
# Photon (PDG ID: 22)
# -----------------------------------------------------------------------------
const photon = ParticleDefinition(0.0*u"MeVc2", Inf*u"s", 0u"e")

# -----------------------------------------------------------------------------
# Pions (PDG ID: 211, -211, 111)
# -----------------------------------------------------------------------------
const piplus = ParticleDefinition(139.57039*u"MeVc2", 2.6033e-8*u"s", 1u"e")
const piminus = ParticleDefinition(139.57039*u"MeVc2", 2.6033e-8*u"s", -1u"e")
const pizero = ParticleDefinition(134.9768*u"MeVc2", 8.43e-17*u"s", 0u"e")

# -----------------------------------------------------------------------------
# Kaons (PDG ID: 321, -321, 310, 130, 311, -311)
# -----------------------------------------------------------------------------
const Kplus = ParticleDefinition(493.677*u"MeVc2", 1.2380e-8*u"s", 1u"e")
const Kminus = ParticleDefinition(493.677*u"MeVc2", 1.2380e-8*u"s", -1u"e")
const K0_S = ParticleDefinition(497.611*u"MeVc2", 8.954e-11*u"s", 0u"e")  # K-short
const K0_L = ParticleDefinition(497.611*u"MeVc2", 5.116e-8*u"s", 0u"e")   # K-long
const K0 = ParticleDefinition(497.611*u"MeVc2", Inf*u"s", 0u"e")          # Flavor eigenstate (mixes to K_S/K_L)
const K0bar = ParticleDefinition(497.611*u"MeVc2", Inf*u"s", 0u"e")       # Flavor eigenstate

# -----------------------------------------------------------------------------
# Eta mesons (PDG ID: 221, 331)
# -----------------------------------------------------------------------------
const eta = ParticleDefinition(547.862*u"MeVc2", 5.0e-19*u"s", 0u"e")
const eta_prime = ParticleDefinition(957.78*u"MeVc2", 3.2e-21*u"s", 0u"e")

# -----------------------------------------------------------------------------
# Rho and Omega mesons (PDG ID: 113, 213, -213, 223)
# These are resonances with very short lifetimes
# -----------------------------------------------------------------------------
const rho0 = ParticleDefinition(775.26*u"MeVc2", 4.5e-24*u"s", 0u"e")
const rhoplus = ParticleDefinition(775.11*u"MeVc2", 4.5e-24*u"s", 1u"e")
const rhominus = ParticleDefinition(775.11*u"MeVc2", 4.5e-24*u"s", -1u"e")
const omega = ParticleDefinition(782.66*u"MeVc2", 7.75e-23*u"s", 0u"e")

# -----------------------------------------------------------------------------
# D mesons (PDG ID: 411, -411, 421, -421, 431, -431)
# -----------------------------------------------------------------------------
const Dplus = ParticleDefinition(1869.66*u"MeVc2", 1.040e-12*u"s", 1u"e")
const Dminus = ParticleDefinition(1869.66*u"MeVc2", 1.040e-12*u"s", -1u"e")
const D0 = ParticleDefinition(1864.84*u"MeVc2", 4.101e-13*u"s", 0u"e")
const D0bar = ParticleDefinition(1864.84*u"MeVc2", 4.101e-13*u"s", 0u"e")
const Ds_plus = ParticleDefinition(1968.35*u"MeVc2", 5.04e-13*u"s", 1u"e")
const Ds_minus = ParticleDefinition(1968.35*u"MeVc2", 5.04e-13*u"s", -1u"e")

# -----------------------------------------------------------------------------
# Nucleons (PDG ID: 2212, -2212, 2112, -2112)
# -----------------------------------------------------------------------------
const proton = ParticleDefinition(938.27208816*u"MeVc2", Inf*u"s", 1u"e")
const antiproton = ParticleDefinition(938.27208816*u"MeVc2", Inf*u"s", -1u"e")
const neutron = ParticleDefinition(939.56542052*u"MeVc2", 878.4*u"s", 0u"e")  # Free neutron lifetime
const antineutron = ParticleDefinition(939.56542052*u"MeVc2", 878.4*u"s", 0u"e")

# -----------------------------------------------------------------------------
# Lambda baryons (PDG ID: 3122, -3122)
# -----------------------------------------------------------------------------
const Lambda0 = ParticleDefinition(1115.683*u"MeVc2", 2.632e-10*u"s", 0u"e")
const Lambda0bar = ParticleDefinition(1115.683*u"MeVc2", 2.632e-10*u"s", 0u"e")

# -----------------------------------------------------------------------------
# Sigma baryons (PDG ID: 3222, 3212, 3112 and antiparticles)
# -----------------------------------------------------------------------------
const Sigma_plus = ParticleDefinition(1189.37*u"MeVc2", 8.018e-11*u"s", 1u"e")
const Sigma0 = ParticleDefinition(1192.642*u"MeVc2", 7.4e-20*u"s", 0u"e")
const Sigma_minus = ParticleDefinition(1197.449*u"MeVc2", 1.479e-10*u"s", -1u"e")
const Sigma_plus_bar = ParticleDefinition(1189.37*u"MeVc2", 8.018e-11*u"s", -1u"e")
const Sigma0bar = ParticleDefinition(1192.642*u"MeVc2", 7.4e-20*u"s", 0u"e")
const Sigma_minus_bar = ParticleDefinition(1197.449*u"MeVc2", 1.479e-10*u"s", 1u"e")

# -----------------------------------------------------------------------------
# Xi baryons (PDG ID: 3322, 3312 and antiparticles)
# -----------------------------------------------------------------------------
const Xi0 = ParticleDefinition(1314.86*u"MeVc2", 2.90e-10*u"s", 0u"e")
const Xi_minus = ParticleDefinition(1321.71*u"MeVc2", 1.639e-10*u"s", -1u"e")
const Xi0bar = ParticleDefinition(1314.86*u"MeVc2", 2.90e-10*u"s", 0u"e")
const Xi_plus = ParticleDefinition(1321.71*u"MeVc2", 1.639e-10*u"s", 1u"e")

# -----------------------------------------------------------------------------
# Omega baryon (PDG ID: 3334, -3334)
# -----------------------------------------------------------------------------
const Omega_minus = ParticleDefinition(1672.45*u"MeVc2", 8.21e-11*u"s", -1u"e")
const Omega_plus = ParticleDefinition(1672.45*u"MeVc2", 8.21e-11*u"s", 1u"e")
