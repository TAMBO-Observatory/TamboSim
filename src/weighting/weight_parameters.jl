"""
    WeightParameters{T<:Real}

A struct to hold parameters related to event weighting.

# Fields
- `area`: The area of the injection surface.
- `emin`: The minimum energy of the power law sampler.
- `emax`: The maximum energy of the power law sampler.
- `gamma`: The spectral index of the power law sampler.
- `thetamin`: The minimum zenith angle of the angular sampler.
- `thetamax`: The maximum zenith angle of the angular sampler.
- `phimin`: The minimum azimuth angle of the angular sampler.
- `phimax`: The maximum azimuth angle of the angular sampler.
- `generated_initial_e`: The initial energy of the particle.
- `generated_final_e`: The final energy of the particle after interaction.
- `generated_cd`: The column depth traversed by the particle.
- `generated_density`: The density of the medium at the interaction point.
- `generated_xs`: The total cross-section for the interaction.
- `generated_diff_xs`: The differential cross-section for the interaction.
"""
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

"""
    null_params::WeightParameters

A constant `WeightParameters` object initialized with `NaN` values.

This is used to represent a default or invalid set of weighting parameters.
"""
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

"""
    WeightParameters(
        area::Quantity{T,ldim^2,typeof(u"m^2")},
        pl::UnitfulPowerLawSampler{T},
        as::UniformAngularSampler,
        xs::CrossSection{T},
        generated_initial_e::Quantity{T,edim,typeof(u"GeV")},
        generated_close_e::Quantity{T,edim,typeof(u"GeV")},
        generated_final_e::Quantity{T,edim,typeof(u"GeV")},
        generated_cd::Quantity{T,mdim/ldim^2,typeof(u"g/cm^2")},
        generated_density::Quantity{T,mdim/ldim^3,typeof(u"g/cm^3")}
    ) where {T<:Real}

Constructor for `WeightParameters` struct.

Calculates cross-sections based on the provided samplers and physical parameters,
and then constructs a `WeightParameters` object.

# Arguments
- `area`: The area of the injection surface.
- `pl`: A `UnitfulPowerLawSampler` object defining the energy distribution.
- `as`: A `UniformAngularSampler` object defining the angular distribution.
- `xs`: A `CrossSection` object for calculating cross-sections.
- `generated_initial_e`: The initial energy of the particle.
- `generated_close_e`: The energy of the particle at the closest point to the interaction.
- `generated_final_e`: The final energy of the particle after interaction.
- `generated_cd`: The column depth traversed by the particle.
- `generated_density`: The density of the medium at the interaction point.

# Returns
- A `WeightParameters` object.
"""
function WeightParameters(
    area::Quantity{T,ldim^2,typeof(u"m^2")},
    pl::UnitfulPowerLawSampler{T},
    as::UniformAngularSampler,
    xs::CrossSection{T},
    generated_initial_e::Quantity{T,edim,typeof(u"GeV")},
    generated_close_e::Quantity{T,edim,typeof(u"GeV")},
    generated_final_e::Quantity{T,edim,typeof(u"GeV")},
    generated_cd::Quantity{T,mdim/ldim^2,typeof(u"g/cm^2")},
    generated_density::Quantity{T,mdim/ldim^3,typeof(u"g/cm^3")}
) where {T<:Real}
    generated_xs, generated_diff_xs = NaN*u"cm^2", NaN*u"cm^2"
    if !isnan(generated_final_e)
        generated_xs = xs(generated_close_e)
        generated_diff_xs = xs(generated_close_e, generated_final_e)
    end
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
