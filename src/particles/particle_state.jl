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
- `Particle(pdg::ParticleType, e::Quantity{T,edim}, pos::Coordinate{T}, dir::Direction{T}, time::Quantity{T, tdim})`: Creates a particle with a given PDG type, energy, position, direction, and time (speed defaults to 0).
- `Particle(pdg::ParticleType, e::Quantity{T,edim}, pos::Coordinate{T}, dir::Direction{T}, time::Quantity{T, tdim}, speed::Quantity{T})`: Creates a particle with a given PDG type, energy, position, direction, time, and speed.
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
    function Particle(pdg::ParticleType, e::Quantity{T,edim}, pos::Coordinate{T}, dir::Direction{T}, time::Quantity{T, tdim}, speed::Quantity{T}) where{T<:Real}
        return new{T}(0, pdg, uconvert(u"GeV", e), pos, dir, uconvert(u"s", time), NotSet, Null, uconvert(u"m/s", speed))
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
Mass values for common particles in GeV/c². PDG 2024 values.
"""
const particle_masses = Dict{ParticleType, typeof(1.0u"GeV"/speedoflight^2)}(
    # Leptons
    EMinus => 0.00051099895 * u"GeV"/speedoflight^2,
    EPlus => 0.00051099895 * u"GeV"/speedoflight^2,
    MuMinus => 0.1056583755 * u"GeV"/speedoflight^2,
    MuPlus => 0.1056583755 * u"GeV"/speedoflight^2,
    TauMinus => 1.77686 * u"GeV"/speedoflight^2,
    TauPlus => 1.77686 * u"GeV"/speedoflight^2,
    # Neutrinos (effectively massless)
    NuE => 0.0 * u"GeV"/speedoflight^2,
    NuEBar => 0.0 * u"GeV"/speedoflight^2,
    NuMu => 0.0 * u"GeV"/speedoflight^2,
    NuMuBar => 0.0 * u"GeV"/speedoflight^2,
    NuTau => 0.0 * u"GeV"/speedoflight^2,
    NuTauBar => 0.0 * u"GeV"/speedoflight^2,
    # Photon
    Gamma => 0.0 * u"GeV"/speedoflight^2,
    # Pions
    PiPlus => 0.13957039 * u"GeV"/speedoflight^2,
    PiMinus => 0.13957039 * u"GeV"/speedoflight^2,
    Pi0 => 0.1349768 * u"GeV"/speedoflight^2,
    # Kaons
    KPlus => 0.493677 * u"GeV"/speedoflight^2,
    KMinus => 0.493677 * u"GeV"/speedoflight^2,
    K0_Short => 0.497611 * u"GeV"/speedoflight^2,
    K0_Long => 0.497611 * u"GeV"/speedoflight^2,
    K0 => 0.497611 * u"GeV"/speedoflight^2,
    # Nucleons
    PPlus => 0.93827208816 * u"GeV"/speedoflight^2,  # Proton
    PMinus => 0.93827208816 * u"GeV"/speedoflight^2,  # Antiproton
    Neutron => 0.93956542052 * u"GeV"/speedoflight^2,
    NeutronBar => 0.93956542052 * u"GeV"/speedoflight^2,
    # Eta mesons
    Eta => 0.547862 * u"GeV"/speedoflight^2,
    EtaPrime958 => 0.95778 * u"GeV"/speedoflight^2,
    # Lambda and hyperons
    Lambda => 1.115683 * u"GeV"/speedoflight^2,
    LambdaBar => 1.115683 * u"GeV"/speedoflight^2,
    SigmaPlus => 1.18937 * u"GeV"/speedoflight^2,
    Sigma0 => 1.192642 * u"GeV"/speedoflight^2,
    SigmaMinus => 1.197449 * u"GeV"/speedoflight^2,
    SigmaMinusBar => 1.18937 * u"GeV"/speedoflight^2,
    Sigma0Bar => 1.192642 * u"GeV"/speedoflight^2,
    SigmaPlusBar => 1.197449 * u"GeV"/speedoflight^2,
)

"""
    particle_mass(pdg::ParticleType) -> Quantity

Returns the rest mass of a particle given its PDG type.

# Arguments
- `pdg::ParticleType`: The particle type (PDG ID).

# Returns
- `Quantity`: The rest mass in GeV/c².

# Throws
- `KeyError` if the particle type is not in the mass dictionary.
"""
function particle_mass(pdg::ParticleType)
    return particle_masses[pdg]
end

"""
    particle_speed(ke::Quantity, pdg::ParticleType) -> Quantity

Calculates the relativistic speed of a particle given its kinetic energy and PDG type.

# Arguments
- `ke::Quantity`: The kinetic energy of the particle.
- `pdg::ParticleType`: The particle type (PDG ID).

# Returns
- `Quantity`: The speed of the particle in m/s.
"""
function particle_speed(ke::Quantity, pdg::ParticleType)
    m = particle_mass(pdg)
    return particle_speed(ke, m)
end


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
    lorentz_gamma(ke::Quantity{T,edim}, m::Quantity{T,mdim}) -> T

Calculates the relativistic Lorentz factor (γ) for a particle given its kinetic energy and mass.

The Lorentz factor is: γ = 1 + ke/(mc²)

# Arguments
- `ke::Quantity{T,edim}`: The kinetic energy of the particle.
- `m::Quantity{T,mdim}`: The rest mass of the particle.

# Returns
- `T`: The Lorentz factor (unitless, ≥ 1).
"""
function lorentz_gamma(
    ke::Quantity{T,edim},
    m::Quantity{T,mdim}
)::T where {T<:Real}
    return 1 + ustrip(uconvert(u"J", ke) / uconvert(u"J", m * speedoflight^2))
end

# Keep old function name for backwards compatibility but mark as deprecated
"""
    gamma(ke, m)

**DEPRECATED**: Use `lorentz_gamma` instead. This function returns γ-1, not γ.
"""
function gamma(
    ke::Quantity{T,edim},
    m::Quantity{T,mdim}
)::T where {T<:Real}
    return ke / m / speedoflight^2
end

"""
    particle_speed(ke::Quantity, m::Quantity) -> Quantity

Calculates the relativistic speed of a particle given its kinetic energy and rest mass.

Uses the relativistic relations:
- γ = 1 + ke/(mc²)
- β = √(1 - 1/γ²)
- v = βc

# Arguments
- `ke::Quantity`: The kinetic energy of the particle.
- `m::Quantity`: The rest mass of the particle.

# Returns
- `Quantity`: The speed of the particle in m/s.

# Examples
```julia
# Speed of a 1 GeV electron
v = particle_speed(1u"GeV", 0.511u"MeV"/speedoflight^2)
```
"""
function particle_speed(ke::Quantity, m::Quantity)
    # Handle massless particles (photons)
    if ustrip(m) == 0
        return speedoflight
    end

    γ = lorentz_gamma(ke, m)

    # For very low γ (particle at rest), avoid numerical issues
    if γ ≤ 1.0
        return 0.0u"m/s"
    end

    β² = 1 - 1/γ^2
    β = sqrt(β²)

    return β * speedoflight
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
    particle_rock_range(e::Quantity, pdg::ParticleType) -> Quantity

Calculates the range of a particle in rock, based on its energy and particle type.

This function uses parameters (`α`, `β`) from `range_parameters` to compute the
particle's range in a dense medium like rock.

# Arguments
- `e::Quantity`: The energy of the particle.
- `pdg::ParticleType`: The particle type (e.g., MuMinus, TauMinus).

# Returns
- `Quantity`: The range of the particle in rock.
"""
function particle_rock_range(e::Quantity, pdg::ParticleType)
    α, β = range_parameters[pdg]
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
