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
    p = norm * (generated_initial_e / emin)
    Ω = (cos(thetamin) - cos(thetamax)) * (phimax - phimin)
    p /= Ω
    p /= area
    # This only applies when interadtion forced
    # This only applies when interaction forced
    if ~isnan(ustrip(generated_cd))
        p *= generated_density / generated_cd
        p *= generated_diff_xs / generated_xs
    end
    return p
end

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

