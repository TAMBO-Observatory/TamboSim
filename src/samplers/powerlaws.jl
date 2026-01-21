"""
    UnitfulPowerLawSampler{T<:Real}

Represents a power law distribution sampler for energies, supporting Unitful quantities.

This struct allows for sampling energies `E` from a distribution proportional to `E^(-γ)`
between a minimum (`emin`) and maximum (`emax`) energy. The distribution is normalized.

# Fields
- `γ::T`: The spectral index (exponent) of the power law.
- `emin::Quantity{T, edim, typeof(u"GeV")}`: The minimum energy of the distribution, in GeV.
- `emax::Quantity{T, edim, typeof(u"GeV")}`: The maximum energy of the distribution, in GeV.
- `norm::Quantity{T, edim^-1, typeof(u"GeV^-1")}`: The normalization constant for the power law, in inverse GeV.

# Constructors
- `UnitfulPowerLawSampler(γ, emin, emax, norm)`: Primary constructor that performs an assertion if `γ >= 1` and `emax` is infinite.
"""
struct UnitfulPowerLawSampler{T <: Real}
    γ::T
    emin::Quantity{T, edim, typeof(u"GeV")}
    emax::Quantity{T, edim, typeof(u"GeV")}
    norm::Quantity{T, edim^-1, typeof(u"GeV^-1")}
    function UnitfulPowerLawSampler(γ, emin, emax, norm)
        """
        Returns a normalized PowerLaw
        """
        if γ >= 1
            @assert !isinf(emax)
        end
        T = Float64
        return new{T}(γ, emin, emax, norm)
    end
end

"""
    UnitfulPowerLawSampler(γ, emin, emax) -> UnitfulPowerLawSampler

Constructs a `UnitfulPowerLawSampler` by automatically calculating the normalization constant.

This is a convenience constructor that computes `norm` using `pl_norm` before
calling the primary constructor.

# Arguments
- `γ`: The spectral index (exponent) of the power law.
- `emin`: The minimum energy of the distribution.
- `emax`: The maximum energy of the distribution.

# Returns
- A new `UnitfulPowerLawSampler` object.
"""
function UnitfulPowerLawSampler(γ, emin, emax)

    norm = pl_norm(γ, emin, emax)
    return UnitfulPowerLawSampler(γ, emin, emax, norm)
end

"""
    pl_norm(γ::Real, emin::Quantity, emax::Quantity) -> Quantity

Calculates the normalization constant for a power law distribution.

This function handles the special case where `γ = 1` (logarithmic distribution)
and the general case for `γ != 1`.

# Arguments
- `γ::Real`: The spectral index of the power law.
- `emin::Quantity`: The minimum energy.
- `emax::Quantity`: The maximum energy.

# Returns
- `Quantity`: The normalization constant.
"""
function pl_norm(γ, emin, emax)
    if γ == 1
        norm = 1 / (emin * log(emax / emin))
        return norm
    else
        γ > 1
        mg = 1 - γ
        norm = mg / (emin^γ * (emax^mg - emin^mg))
        return norm
    end
end

"""
    Base.rand(pl::UnitfulPowerLawSampler{T}) -> Quantity{T,edim,typeof(u"GeV")}

Randomly samples an energy from the `UnitfulPowerLawSampler` distribution.

This function uses inverse transform sampling to generate a random energy value
following the specified power law. It handles both `γ = 1` and `γ != 1` cases.

# Arguments
- `pl::UnitfulPowerLawSampler{T}`: The power law sampler object.

# Returns
- `Quantity{T,edim,typeof(u"GeV")}`: A randomly sampled energy value in GeV.
"""
function Base.rand(
    pl::UnitfulPowerLawSampler{T}
)::Quantity{T,edim,typeof(u"GeV")} where {T<:Real}
    u = rand()
    if pl.γ==1
        return pl.emin * exp(u / (pl.norm * pl.emin))
    else
        α = 1 - pl.γ
        return (u * α / pl.norm / pl.emin^pl.γ + pl.emin^α)^(1/α)
    end
end

"""
    Base.rand(pl::UnitfulPowerLawSampler{T}, n::Int) -> Vector{Quantity{T, edim, typeof(u"GeV")}}

Randomly samples `n` energies from the `UnitfulPowerLawSampler` distribution.

This is a convenience method that calls `rand(pl)` `n` times to generate multiple energy samples.

# Arguments
- `pl::UnitfulPowerLawSampler{T}`: The power law sampler object.
- `n::Int`: The number of samples to generate.

# Returns
- `Vector{Quantity{T, edim, typeof(u"GeV")}}`: A vector of randomly sampled energy values.
"""
function Base.rand(pl::UnitfulPowerLawSampler{T}, n::Int)::Vector{Quantity{T, edim, typeof(u"GeV")}} where {T<:Real}
    return [rand(pl) for _ in 1:n]
end

"""
    (pl::UnitfulPowerLawSampler{T})(e::Quantity{T, edim, typeof(u"GeV")}) -> Quantity{T, edim^-1, typeof(u"GeV^-1")}

Evaluates the probability density function (PDF) of the power law at a given energy.

# Arguments
- `e::Quantity{T, edim, typeof(u"GeV")}`: The energy at which to evaluate the PDF.

# Returns
- `Quantity{T, edim^-1, typeof(u"GeV^-1")}`: The PDF value at energy `e`, in inverse GeV.
"""
function (pl::UnitfulPowerLawSampler{T})(
    e::Quantity{T, edim, typeof(u"GeV")}
)::Quantity{T, edim^-1, typeof(u"GeV^-1")} where {T<:Real}
    return pl.norm * (e / pl.emin)^(-pl.γ)
end

"""
    probability(pl::UnitfulPowerLawSampler{T}, e::Quantity{T, edim, typeof(u"GeV")}) -> T

Calculates the normalized probability of observing a particle with a specific energy `e`.

This function returns a probability value based on the power law distribution,
considering the specific case for `γ = 1`.

# Arguments
- `pl::UnitfulPowerLawSampler{T}`: The power law sampler object.
- `e::Quantity{T, edim, typeof(u"GeV")}`: The energy at which to calculate the probability.

# Returns
- `T`: The normalized probability (unitless).
"""
function probability(
    pl::UnitfulPowerLawSampler{T},
    e::Quantity{T, edim, typeof(u"GeV")}
)::T where {T}
    @assert pl.emin < e && e < pl.emax
    if pl.γ==1
        return pl(e) / (pl.norm * log(pl.emax / pl.emin))
    end
    p = pl(e) * ((1-pl.γ) / (pl.norm * (pl.emax^(1-pl.γ) - pl.emin^(1-pl.γ))))
    return p
end
