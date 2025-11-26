struct Particle{T <: Real, U, V}
    pdg_id::Int
    energy::Quantity{T,V,typeof(u"GeV")}
    position::Coordinate{T,U}
    direction::Direction{T,U}
end

const null_particle = Particle(
    0, 
    0.0u"GeV",
    Coordinate([0.0u"m", 0.0u"m",  0.0u"m"], ecefcoordinates),
    Direction([0.0, 0.0, -1.0], ecefcoordinates)
)

# This is a bad place for this
const c = 299_792_458.0 * u"m" / u"s"

particle_parameters = Dict{Int, Tuple}(
    15 => (1776.86 * u"MeV"/c^2, 2.903e-13 * u"s"),
    -15 => (1776.86 * u"MeV"/c^2, 2.903e-13 * u"s"),
)

function gamma(
    ke::Quantity{T,U,typeof(u"GeV")},
    m::Quantity{T,V}
)::T where {T,U,V}
    return ke / m / c^2
end

function particle_range(
    pdg_id::Int,
    energy::Quantity{T,U},
    epsilon::Float64=1e-3
)::Quantity{T,Unitful.𝐋,typeof(u"m")} where {T,U}
    m, tau = particle_parameters[pdg_id]
    return -gamma(energy, m) * c * tau * log(epsilon)
end

function particle_range(
    particle::Particle{T,U,V},
    epsilon::Float64=1e-3
)::Quantity{T,U,typeof(u"m")} where {T,U,V}
    return particle_range(particle_range.pdg_id, epsilon)
end

#const range_parameters = Dict(
#    13 => (1.76666667e-1 * units.GeV / units.mwe, 2.0916666667e-4 / units.mwe),
#    15 => (1.473684210526e3 * units.GeV / units.mwe, 2.63e-5 / units.mwe),
#    -13 => (1.76666667e-1 * units.GeV / units.mwe, 2.0916666667e-4 / units.mwe),
#    -15 => (1.473684210526e3 * units.GeV / units.mwe, 2.63e-5 / units.mwe)
