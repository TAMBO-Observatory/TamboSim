"""
    UniformAngularSampler

Represents a sampler for generating direction angles uniformly within specified zenith (`θ`) and azimuthal (`ϕ`) ranges.

The sampling is uniform in phase space (i.e., uniform in `cos(θ)` and `ϕ`).
Assertions ensure the validity of the provided angle ranges.

# Fields
- `θmin::Float64`: The minimum zenith angle in radians.
- `θmax::Float64`: The maximum zenith angle in radians.
- `ϕmin::Float64`: The minimum azimuthal angle in radians.
- `ϕmax::Float64`: The maximum azimuthal angle in radians.

# Constructors
- `UniformAngularSampler(θmin, θmax, ϕmin, ϕmax)`: Primary constructor that validates the angle ranges.
"""
struct UniformAngularSampler
    θmin::Float64
    θmax::Float64
    ϕmin::Float64
    ϕmax::Float64
    function UniformAngularSampler(θmin, θmax, ϕmin, ϕmax)
        @assert ϕmin <= ϕmax "ϕmin greater than ϕmax"
        @assert θmin <= θmax "θmin greater than θmax"
        @assert ϕmax - ϕmin <= 2π "Azimuthal range is greater than one period"
        return new(θmin, θmax, ϕmin, ϕmax)
    end
end

"""
    Base.rand(sampler::UniformAngularSampler) -> Tuple{Float64, Float64}

Randomly samples a zenith and azimuthal angle pair from the sampler's defined range.

Zenith angle (`θ`) is sampled uniformly in `cos(θ)`, and azimuthal angle (`ϕ`) is sampled uniformly.

# Arguments
- `sampler::UniformAngularSampler`: The angular sampler object.

# Returns
- `Tuple{Float64, Float64}`: A tuple `(θ, ϕ)` representing the sampled zenith and azimuthal angles in radians.
"""
function Base.rand(sampler::UniformAngularSampler)
    # Randomly sample zenith uniform in phase space
    θ = acos(rand(Uniform(cos(sampler.θmax), cos(sampler.θmin))))
    # Randomly sample azimuth
    ϕ = rand(Uniform(sampler.ϕmin, sampler.ϕmax))
    return θ, ϕ
end

"""
    Base.rand(sampler::UniformAngularSampler, cs::CoordinateSystem) -> Direction

Randomly samples a `Direction` object from the sampler's defined angular range within a specified `CoordinateSystem`.

This function first samples `θ` and `ϕ` using `rand(sampler)` and then converts these spherical
coordinates to a `Direction` vector in the given `CoordinateSystem`.

# Arguments
- `sampler::UniformAngularSampler`: The angular sampler object.
- `cs::CoordinateSystem`: The target coordinate system for the `Direction`.

# Returns
- `Direction`: A randomly sampled `Direction` object.
"""
function Base.rand(sampler::UniformAngularSampler, cs::CoordinateSystem)
    theta, phi = rand(sampler)
    d = sph_to_cart(theta, phi)
    return Direction(d, cs)
end

"""
    probability(sampler::UniformAngularSampler, θ::Number, ϕ::Number) -> Float64

Calculates the probability density of sampling a specific (θ, ϕ) angle pair from the sampler.

This function asserts that the given angles are within the sampler's defined range
and returns the inverse of the solid angle `Ω` covered by the sampler.

# Arguments
- `sampler::UniformAngularSampler`: The angular sampler object.
- `θ::Number`: The zenith angle in radians.
- `ϕ::Number`: The azimuthal angle in radians.

# Returns
- `Float64`: The probability density.
"""
function probability(sampler::UniformAngularSampler, θ::Number, ϕ::Number)
    @assert sampler.θmin <= θ && θ <= sampler.θmax "Zenith angle out of phase space"
    @assert sampler.ϕmin <= ϕ && ϕ <= sampler.ϕmax "Azimuth angle out of phase space"
    Ω = (sampler.ϕmax - sampler.ϕmin) * (cos(sampler.θmin) - cos(sampler.θmax))
    return 1 / Ω
end

"""
    probability(sampler::UniformAngularSampler, event) -> Float64

Calculates the probability density of sampling the direction of an event's initial state.

This is a convenience method that extracts the zenith and azimuthal angles from the
`event`'s `initial_state.direction` and then calls the primary `probability` function.

# Arguments
- `sampler::UniformAngularSampler`: The angular sampler object.
- `event`: An event object (e.g., `InjectionEvent`) that has an `initial_state` field,
  which in turn has a `direction` field.

# Returns
- `Float64`: The probability density.
"""
function probability(sampler::UniformAngularSampler, event)
    return probability(sampler, event.initial_state.direction.θ, event.initial_state.direction.ϕ)
end
