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

function Base.show(io::IO, sampler::UniformAngularSampler)
    s = "UniformAngularSampler("
    s *= "θmin=$(sampler.θmin / π * 180)∘, "
    s *= "θmax=$(sampler.θmax / π * 180)∘, "
    s *= "ϕmin=$(sampler.ϕmin / π * 180)∘, "
    s *= "ϕmax=$(sampler.ϕmax / π * 180)∘"
    s *= ")"
    print(io, s)
end

"""
    Base.rand(sampler::UniformAngularSampler)

Return zenith (θ) and azimuth (ϕ) angles sampled uniformly on a sphere

TBW
"""
function Base.rand(sampler::UniformAngularSampler)
    # Randomly sample zenith uniform in phase space
    θ = acos(rand(Uniform(cos(sampler.θmax), cos(sampler.θmin))))
    # Randomly sample azimuth
    ϕ = rand(Uniform(sampler.ϕmin, sampler.ϕmax))
    return θ, ϕ
end

function probability(sampler::UniformAngularSampler, θ::Number, ϕ::Number)
    @assert sampler.θmin <= θ && θ <= sampler.θmax "Zenith angle out of phase space"
    @assert sampler.ϕmin <= ϕ && ϕ <= sampler.ϕmax "Azimuth angle out of phase space"
    Ω = (sampler.ϕmax - sampler.ϕmin) * (cos(sampler.θmin) - cos(sampler.θmax))
    return 1 / Ω
end

function probability(sampler::UniformAngularSampler, event)
    return probability(sampler, event.initial_state.direction.θ, event.initial_state.direction.ϕ)
end
