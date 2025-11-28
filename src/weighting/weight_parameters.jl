struct WeightParameters{T<:Real}
    area::Quantity{T,ldim^2, typeof(u"m^2")}
    emin::Quantity{T,edim, typeof(u"GeV")}
    emax::Quantity{T,edim, typeof(u"GeV")}
    gamma::T
    thetamin::T
    thetamax::T
    phimin::T
    phimax::T
    # Exists for all non-null events
    generated_initial_e::Quantity{T,edim,typeof(u"GeV")}
    # Exists for neutrinos only
    generated_final_e::Quantity{T,edim,typeof(u"GeV")}
    generated_cd::Quantity{T,mdim/ldim^2,typeof(u"g/cm^2")}
    generated_density::Quantity{T,mdim/ldim^3,typeof(u"g/cm^3")}
    generated_xs::Quantity{T,ldim^2,typeof(u"cm^2")}
    generated_diff_xs::Quantity{T,ldim^2,typeof(u"cm^2")}
end

const null_params = WeightParameters(
    NaN * u"m^2",
    NaN * u"GeV",
    NaN * u"GeV",
    NaN,
    NaN,
    NaN,
    NaN,
    NaN,
    NaN * u"GeV",
    NaN * u"GeV",
    NaN * u"g/cm^2",
    NaN * u"g/cm^3",
    NaN * u"cm^2",
    NaN * u"cm^2",
)

function WeightParameters(
    area::Quantity{T,ldim^2,typeof(u"m^2")},
    pl::UnitfulPowerLawSampler{T},
    as::UniformAngularSampler,
    xs::CrossSection{T},
    generated_initial_e::Quantity{T,edim,typeof(u"GeV")},
    generated_final_e::Quantity{T,edim,typeof(u"GeV")},
    generated_cd::Quantity{T,mdim/ldim^2,typeof(u"g/cm^2")},
    generated_density::Quantity{T,mdim/ldim^3,typeof(u"g/cm^3")}
) where {T<:Real}
    generated_xs = xs(generated_initial_e)
    generated_diff_xs = xs(generated_initial_e, generated_final_e)
    return WeightParameters(
        area,
        pl.emin,
        pl.emax,
        pl.γ,
        as.θmin,
        as.θmax,
        as.ϕmin,
        as.ϕmax,
        generated_initial_e,
        generated_final_e,
        generated_cd,
        generated_density,
        generated_xs,
        generated_diff_xs
    )
end
