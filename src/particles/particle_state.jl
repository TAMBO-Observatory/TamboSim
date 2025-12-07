struct Particle{T<:Real}
    pdg_id::Int
    energy::Quantity{T,edim,typeof(u"GeV")}
    position::Coordinate{T}
    direction::Direction{T}
    function Particle(
        a::Int,
        b::Q,
        c::Coordinate{T},
        d::Direction{T}
    ) where {T<:Real, Q<:Quantity{T,edim}}
        return new{T}(a, b|> u"GeV", c, d)
    end
end

const null_particle = Particle(
    -1, 
    NaN * u"GeV",
    Coordinate([NaN * u"m", NaN * u"m",  NaN*u"m"], ecefcoordinates),
    Direction([0.0, 0.0, -1.0], ecefcoordinates)
)

const range_parameters = Dict(
    13 => (1.76666667e-1 * u"GeV*cm^3/m/g", 2.0916666667e-4 * u"cm^3/m/g"),
    -13 => (1.76666667e-1 * u"GeV*cm^3/m/g", 2.0916666667e-4 * u"cm^3/m/g"),
    15 => (1.473684210526e3 * u"GeV*cm^3/m/g", 2.63e-5 * u"cm^3/m/g"),
    -15 => (1.473684210526e3 * u"GeV*cm^3/m/g", 2.63e-5 * u"cm^3/m/g"),
)

particle_parameters = Dict{Int, Tuple}(
    15 => (1.77686 * u"GeV"/speedoflight^2, 2.903e-13 * u"s"),
    -15 => (1.77686 * u"GeV"/speedoflight^2, 2.903e-13 * u"s"),
    13 => (0.1056583745 * u"GeV"/speedoflight^2, 2.1969811e-6 * u"s"),
    -13 => (0.1056583745 * u"GeV"/speedoflight^2, 2.1969811e-6 * u"s"),
    11 => (0.00051099895000 * u"GeV"/speedoflight^2, Inf * u"s"),
    -11 => (0.00051099895000 * u"GeV"/speedoflight^2, Inf * u"s"),
)


function Ray(p::Particle)
    return Ray(p.position, p.direction)
end

function gamma(
    ke::Quantity{T,edim},
    m::Quantity{T,mdim}
)::T where {T<:Real}
    return ke / m / speedoflight^2
end

function particle_vacuum_range(
    pdg_id::Int,
    energy::Quantity{T,edim,typeof(u"GeV")},
    epsilon::Float64=1e-3
)::Quantity{T,ldim,typeof(u"m")} where {T<:Real}
    m, tau = particle_parameters[pdg_id]
    return -gamma(energy, m) * speedoflight * tau * log(epsilon)
end

function particle_rock_range(e::Quantity, pdg_code::Int)
    α, β = range_parameters[pdg_code]
    range = log(1 + e * β / α) / β
    return range
end

function particle_vacuum_range(
    particle::Particle{T},
    epsilon::Float64=1e-3
)::Quantity{T,ldim,typeof(u"m")} where {T}
    return particle_vacuum_range(particle.pdg_id, epsilon)
end

#const range_parameters = Dict(
#    13 => (1.76666667e-1 * units.GeV / units.mwe, 2.0916666667e-4 / units.mwe),
#    15 => (1.473684210526e3 * units.GeV / units.mwe, 2.63e-5 / units.mwe),
#    -13 => (1.76666667e-1 * units.GeV / units.mwe, 2.0916666667e-4 / units.mwe),
#    -15 => (1.473684210526e3 * units.GeV / units.mwe, 2.63e-5 / units.mwe)
