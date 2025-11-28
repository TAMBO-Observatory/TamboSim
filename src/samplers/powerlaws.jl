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

function UnitfulPowerLawSampler(γ, emin, emax)

    norm = pl_norm(γ, emin, emax)
    return UnitfulPowerLawSampler(γ, emin, emax, norm)
end

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

function Base.rand(pl::UnitfulPowerLawSampler{T}, n::Int)::Vector{Quantity{T, edim, typeof(u"GeV")}} where {T<:Real}
    return [rand(pl) for _ in 1:n]
end

function (pl::UnitfulPowerLawSampler{T})(
    e::Quantity{T, edim, typeof(u"GeV")}
)::Quantity{T, edim^-1, typeof(u"GeV^-1")} where {T<:Real}
    return pl.norm * (e / pl.emin)^(-pl.γ)
end

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
