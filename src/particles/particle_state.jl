"""
    Particle{T<:Real}

Represents the state of a particle in a simulation.

This struct encapsulates various physical properties of a particle, including its
identity (PDG ID), kinematic state (energy, position, direction, time, speed),
and simulation-specific attributes (ID, fit status, shape).

# Fields
- `id::Int`: A unique identifier for the particle instance.
- `pdg::ParticleType`: The Particle Data Group (PDG) ID, defining the particle type.
- `energy::Quantity{T,edim,typeof(u"GeV")}`: The kinetic energy of the particle, in GeV.
- `position::Coordinate{T}`: The `Coordinate` of the particle's current position.
- `direction::Direction{T}`: The `Direction` of the particle's momentum.
- `time::Quantity{T,tdim,typeof(u"s")}`: The simulation time at which this state is recorded, in seconds.
- `status::FitStatus`: The fit status of the particle (e.g., for reconstruction purposes).
- `shape::ParticleShape`: The geometric shape associated with the particle (e.g., for visualization or interaction volume).
- `speed::Quantity{T,ldim/tdim,typeof(u"m/s")}`: The speed of the particle, in meters per second.

# Constructors
- `Particle(id::Int, T::Type)`: Creates a particle with a given `id` and type `T`, initialized with NaN/default values.
- `Particle(T::Type)`: Creates a particle with `id=0` and type `T`, initialized with NaN/default values.
- `Particle(pdg::ParticleType, e::Quantity{T,edim}, pos::Coordinate{T}, dir::Direction{T})`: Creates a particle with a given PDG type, energy, position, and direction.
- `Particle(id::Int, pdg::ParticleType, e::Quantity{T,edim}, pos::Coordinate{T}, dir::Direction{T})`: Creates a particle with a given ID, PDG type, energy, position, and direction.
- `Particle(pdg::ParticleType, e::Quantity{T,edim}, pos::Coordinate{T}, dir::Direction{T}, time::Quantity{T, tdim})`: Creates a particle with a given PDG type, energy, position, direction, and time.
"""
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

const particle_parameters = Dict{ParticleType, Tuple}(
    TauMinus => (1.77686 * u"GeV"/speedoflight^2, 2.903e-13 * u"s"),
    TauPlus => (1.77686 * u"GeV"/speedoflight^2, 2.903e-13 * u"s"),
    MuMinus => (0.1056583745 * u"GeV"/speedoflight^2, 2.1969811e-6 * u"s"),
    MuPlus => (0.1056583745 * u"GeV"/speedoflight^2, 2.1969811e-6 * u"s"),
    EMinus => (0.00051099895000 * u"GeV"/speedoflight^2, Inf * u"s"),
    EPlus => (0.00051099895000 * u"GeV"/speedoflight^2, Inf * u"s"),
)


"""
    Ray(p::Particle) -> Ray

Constructs a `Ray` object from a `Particle`'s position and direction.

# Arguments
- `p::Particle`: The `Particle` object.

# Returns
- A `Ray` object.
"""
function Ray(p::Particle)
    return Ray(p.position, p.direction)
end

"""
    gamma(ke::Quantity{T,edim}, m::Quantity{T,mdim}) -> T

Calculates the relativistic Lorentz factor (gamma) for a particle.

# Arguments
- `ke::Quantity{T,edim}`: The kinetic energy of the particle.
- `m::Quantity{T,mdim}`: The rest mass of the particle.

# Returns
- `T`: The Lorentz factor (unitless).
"""
function gamma(
    ke::Quantity{T,edim},
    m::Quantity{T,mdim}
)::T where {T<:Real}
    return ke / m / speedoflight^2
end

"""
    particle_vacuum_range(
        pdg::ParticleType,
        energy::Quantity{T,edim,typeof(u"GeV")},
        epsilon::Float64=1e-3
    ) -> Quantity{T,ldim,typeof(u"m")}

Calculates the vacuum decay length (range) for an unstable particle.

This function uses the particle's rest mass, lifetime (`tau`), energy, and a
random `epsilon` value to simulate a decay in vacuum.

# Arguments
- `pdg::ParticleType`: The PDG ID of the particle.
- `energy::Quantity{T,edim,typeof(u"GeV")}`: The kinetic energy of the particle.
- `epsilon::Float64`: A random number (between 0 and 1) representing the decay probability. Defaults to 1e-3.

# Returns
- `Quantity{T,ldim,typeof(u"m")}`: The vacuum decay length (range) in meters.
"""
function particle_vacuum_range(
    pdg::ParticleType,
    energy::Quantity{T,edim,typeof(u"GeV")},
    epsilon::Float64=1e-3
)::Quantity{T,ldim,typeof(u"m")} where {T<:Real}
    m, tau = particle_parameters[pdg]
    return -gamma(energy, m) * speedoflight * tau * log(epsilon)
end

"""
    particle_rock_range(e::Quantity, pdg_code::Int) -> Quantity

Calculates the range of a particle in rock, based on its energy and PDG code.

This function uses parameters (`α`, `β`) from `range_parameters` to compute the
particle's range in a dense medium like rock.

# Arguments
- `e::Quantity`: The energy of the particle.
- `pdg_code::Int`: The PDG ID of the particle.

# Returns
- `Quantity`: The range of the particle in rock.
"""
function particle_rock_range(e::Quantity, pdg_code::Int)
    α, β = range_parameters[pdg_code]
    range = log(1 + e * β / α) / β
    return range
end

"""
    particle_vacuum_range(particle::Particle{T}, epsilon::Float64=1e-3) -> Quantity{T,ldim,typeof(u"m")}

Calculates the vacuum decay length (range) for a `Particle` object.

This is a convenience method that extracts the PDG ID and energy from the `Particle`
object and then calls the primary `particle_vacuum_range` function.

# Arguments
- `particle::Particle{T}`: The `Particle` object.
- `epsilon::Float64`: A random number (between 0 and 1) representing the decay probability. Defaults to 1e-3.

# Returns
- `Quantity{T,ldim,typeof(u"m")}`: The vacuum decay length (range) in meters.
"""
function particle_vacuum_range(
    particle::Particle{T},
    epsilon::Float64=1e-3
)::Quantity{T,ldim,typeof(u"m")} where {T}
    return particle_vacuum_range(particle.pdg, particle.energy, epsilon)
end
