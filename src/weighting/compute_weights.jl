"""
    p_mc(
        area::Quantity{T,ldim^2},
        emin::Quantity{T,edim},
        emax::Quantity{T,edim},
        gamma::T,
        thetamin::T,
        thetamax::T,
        phimin::T,
        phimax::T,
        generated_initial_e::Quantity{T,edim},
        generated_cd::Quantity{T,mdim/ldim^2},
        generated_density::Quantity{T,mdim/ldim^3},
        generated_xs::Quantity{T,ldim^2},
        generated_diff_xs::Quantity{T,ldim^2},
       )::Quantity{T,ldim^-3 * edim^-1,typeof(u"GeV^-1 * m^-3")}

Calculates the Monte Carlo probability density for a generated event.

This function combines factors from the phase space of the injected particles (energy, angular, spatial)
and, if applicable, interaction probabilities (cross-sections, column depth) to determine the likelihood
of generating a specific event.

# Arguments
- `area::Quantity{T,ldim^2}`: The effective area from which particles are sampled.
- `emin::Quantity{T,edim}`: Minimum energy of the injected power law.
- `emax::Quantity{T,edim}`: Maximum energy of the injected power law.
- `gamma::T`: Spectral index of the injected power law.
- `thetamin::T`: Minimum zenith angle of the injected angular distribution.
- `thetamax::T`: Maximum zenith angle of the injected angular distribution.
- `phimin::T`: Minimum azimuthal angle of the injected angular distribution.
- `phimax::T`: Maximum azimuthal angle of the injected angular distribution.
- `generated_initial_e::Quantity{T,edim}`: The energy of the generated particle.
- `generated_cd::Quantity{T,mdim/ldim^2}`: The column depth traversed by the generated particle (if interaction forced).
- `generated_density::Quantity{T,mdim/ldim^3}`: The density at the interaction point (if interaction forced).
- `generated_xs::Quantity{T,ldim^2}`: The total cross-section at the generated energy.
- `generated_diff_xs::Quantity{T,ldim^2}`: The differential cross-section at the generated energy.

# Returns
- `Quantity{T,ldim^-3 * edim^-1,typeof(u"GeV^-1 * m^-3")}`: The Monte Carlo probability density.
"""
function p_mc(
    area::Quantity{T,ldim^2},
    emin::Quantity{T,edim},
    emax::Quantity{T,edim},
    gamma::T,
    thetamin::T,
    thetamax::T,
    phimin::T,
    phimax::T,
    generated_initial_e::Quantity{T,edim},
    generated_cd::Quantity{T,mdim/ldim^2},
    generated_density::Quantity{T,mdim/ldim^3},
    generated_xs::Quantity{T,ldim^2},
    generated_diff_xs::Quantity{T,ldim^2},
   )::Quantity{T,ldim^-3 * edim^-1,typeof(u"GeV^-1 * m^-3")} where {T<:Real}

    if generated_initial_e==0.0u"GeV" || isnan(ustrip(generated_initial_e))
        return 0.0 * u"GeV^-1 * m^-3"
    end
    norm = pl_norm(gamma, emin, emax)
    p = norm * (generated_initial_e / emin) ^ -gamma
    Ω = (cos(thetamin) - cos(thetamax)) * (phimax - phimin)
    p /= Ω
    p /= area
    # This only applies when interadtion forced
    # This only applies when interaction forced
    if !isnan(ustrip(generated_cd))
        p *= generated_density / generated_cd
        p *= generated_diff_xs / generated_xs
    else
        p /= u"cm"
    end
    return p
end

"""
    p_mc(wp::WeightParameters{T}) -> Quantity{T,ldim^-3 * edim^-1,typeof(u"GeV^-1 * m^-3")}

Calculates the Monte Carlo probability density for a generated event using `WeightParameters`.

This is a convenience method that unpacks the relevant parameters from a `WeightParameters`
object and calls the primary `p_mc` function.

# Arguments
- `wp::WeightParameters{T}`: An object containing all necessary parameters for Monte Carlo weight calculation.

# Returns
- `Quantity{T,ldim^-3 * edim^-1,typeof(u"GeV^-1 * m^-3")}`: The Monte Carlo probability density.
"""
function p_mc(wp::WeightParameters{T}) where {T<:Real}
    return p_mc(
        wp.area,
        wp.emin,
        wp.emax,
        wp.gamma,
        wp.thetamin,
        wp.thetamax,
        wp.phimin,
        wp.phimax,
        wp.generated_initial_e,
        wp.generated_cd,
        wp.generated_density,
        wp.generated_xs,
        wp.generated_diff_xs
    )
end

"""
    p_phys(
        physical_cd::Quantity{T,mdim/ldim^2},
        physical_density::Quantity{T,mdim/ldim^3},
        physical_diff_xs::Quantity{T,ldim^2}
    ) -> Quantity{T,ldim^-1,typeof(u"m^-1")}

Calculates the physical interaction probability density.

This function computes the probability of an interaction occurring given the
physical column depth, material density, and differential cross-section.

# Arguments
- `physical_cd::Quantity{T,mdim/ldim^2}`: The physical column depth.
- `physical_density::Quantity{T,mdim/ldim^3}`: The physical density of the medium.
- `physical_diff_xs::Quantity{T,ldim^2}`: The physical differential cross-section.

# Returns
- `Quantity{T,ldim^-1,typeof(u"m^-1")}`: The physical interaction probability density.
"""
function p_phys(
    physical_cd::Quantity{T,mdim/ldim^2},
    physical_density::Quantity{T,mdim/ldim^3},
    physical_diff_xs::Quantity{T,ldim^2}
#) where {T<:Real}
)::Quantity{T,ldim^-1,typeof(u"m^-1")} where {T<:Real}
    miso = speedoflight^(-2) * (938.27208816u"MeV" + 939.5654133u"MeV")/2
    if isnan(ustrip(physical_cd))
        return 0.0 * u"m^-1"
    end
    p = physical_cd / miso
    p *= physical_density / physical_cd
    p *= physical_diff_xs
    return p
end

