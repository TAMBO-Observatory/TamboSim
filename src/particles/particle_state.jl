struct Particle{T<:Real}
    id::Int
    pdg::ParticleType
    energy::Quantity{T,edim,typeof(u"GeV")}
    position::Coordinate{T}
    direction::Direction{T}
    time::Quantity{T,tdim,typeof(u"s")}
    status::FitStatus
    shape::ParticleShape
    speed::Quantity{T,ldim/tdim,typeof(u"m/s")}

    function Particle(id::Int, T::Type)
        return new{T}(
            id,
            Unknown,
            NaN*u"GeV",
            Coordinate([NaN * u"m", NaN * u"m",  NaN*u"m"], ecefcoordinates),
            Direction([0.0, 0.0, -1.0], ecefcoordinates),
            NaN*u"s",
            NotSet,
            Null,
            NaN*u"m/s"
        )
    end
    function Particle(T::Type)
        return new{T}(
            0,
            Unknown,
            NaN*u"GeV",
            Coordinate([NaN * u"m", NaN * u"m",  NaN*u"m"], ecefcoordinates),
            Direction([0.0, 0.0, -1.0], ecefcoordinates),
            NaN*u"s",
            NotSet,
            Null,
            NaN*u"m/s"
        )
    end
    function Particle(pdg::ParticleType, e::Quantity{T,edim}, pos::Coordinate{T}, dir::Direction{T}) where{T<:Real} 
        return new{T}(0, pdg, uconvert(u"GeV", e), pos, dir, 0u"s", NotSet, Null, 0.0u"m/s")
    end
    function Particle(id::Int, pdg::ParticleType, e::Quantity{T,edim}, pos::Coordinate{T}, dir::Direction{T}) where{T<:Real} 
        return new{T}(id, pdg, uconvert(u"GeV", e), pos, dir, 0u"s", NotSet, Null, 0.0u"m/s")
    end
    function Particle(pdg::ParticleType, e::Quantity{T,edim}, pos::Coordinate{T}, dir::Direction{T}, time::Quantity{T, tdim}) where{T<:Real} 
        return new{T}(0, pdg, uconvert(u"GeV", e), pos, dir, uconvert(u"s", time), NotSet, Null, 0.0u"m/s")
    end
end

const range_parameters = Dict(
    MuMinus => (1.76666667e-1 * u"GeV*cm^3/m/g", 2.0916666667e-4 * u"cm^3/m/g"),
    MuPlus => (1.76666667e-1 * u"GeV*cm^3/m/g", 2.0916666667e-4 * u"cm^3/m/g"),
    TauMinus => (1.473684210526e3 * u"GeV*cm^3/m/g", 2.63e-5 * u"cm^3/m/g"),
    TauPlus => (1.473684210526e3 * u"GeV*cm^3/m/g", 2.63e-5 * u"cm^3/m/g"),
)

particle_parameters = Dict{ParticleType, Tuple}(
    TauMinus => (1.77686 * u"GeV"/speedoflight^2, 2.903e-13 * u"s"),
    TauPlus => (1.77686 * u"GeV"/speedoflight^2, 2.903e-13 * u"s"),
    MuMinus => (0.1056583745 * u"GeV"/speedoflight^2, 2.1969811e-6 * u"s"),
    MuPlus => (0.1056583745 * u"GeV"/speedoflight^2, 2.1969811e-6 * u"s"),
    EMinus => (0.00051099895000 * u"GeV"/speedoflight^2, Inf * u"s"),
    EPlus => (0.00051099895000 * u"GeV"/speedoflight^2, Inf * u"s"),
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
    pdg::ParticleType,
    energy::Quantity{T,edim,typeof(u"GeV")},
    epsilon::Float64=1e-3
)::Quantity{T,ldim,typeof(u"m")} where {T<:Real}
    m, tau = particle_parameters[pdg]
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
    return particle_vacuum_range(particle.pdg, epsilon)
end

#const range_parameters = Dict(
#    13 => (1.76666667e-1 * units.GeV / units.mwe, 2.0916666667e-4 / units.mwe),
#    15 => (1.473684210526e3 * units.GeV / units.mwe, 2.63e-5 / units.mwe),
#    -13 => (1.76666667e-1 * units.GeV / units.mwe, 2.0916666667e-4 / units.mwe),
#    -15 => (1.473684210526e3 * units.GeV / units.mwe, 2.63e-5 / units.mwe)
