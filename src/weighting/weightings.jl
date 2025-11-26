function p_mc(
    egen::Real,
    ein::Real,
    eout::Real,
    θ::Real,
    ϕ::Real,
    pos::SVector{3},
    genX::Real,
    pl::PowerLaw,
    xs::CrossSection,
    anglesampler::UniformAngularSampler,
    injectionvolume::SymmetricInjectionCylinder,
    geo::Geometry
)
    p = probability(pl, egen)
    p *= probability(xs, ein, eout)
    p *= probability(anglesampler, θ, ϕ)
    p *= probability(injectionvolume)
    p *= density(pos, geo) / genX
end

function p_mc(
    event::InjectionEvent,
    pl::PowerLaw,
    xs::CrossSection,
    anglesampler::UniformAngularSampler,
    injectionvolume::SymmetricInjectionCylinder,
    geo::Geometry
)
    p = probability(anglesampler, event)
    p *= probability(injectionvolume, event)
    p *= density(event.final_state.position, geo) / event.genX
    p *= probability(xs, event)
    p *= probability(pl, event)
    return p
end

function p_phys(
    ein::Real,
    eout::Real,
    physX::Real,
    pos::SVector{3},
    xs::CrossSection,
    geo::Geometry
)
    Miso = (938.27208816units.MeV + 939.5654133units.MeV) / 2
    p = physX / Miso
    p *= density(pos, geo) / physX
    p *= xs.differential_xs(ein, eout)
    return p
end

function p_phys(
    event::InjectionEvent,
    xs::CrossSection,
    geo::Geometry
)
    Miso = (938.27208816units.MeV + 939.5654133units.MeV) / 2
    p = event.genX / Miso
    p *= density(event.final_state.position, geo) / event.genX
    p *= xs.differential_xs(event.entry_state.energy, event.final_state.energy)
    return p
end

function oneweight(
    event::InjectionEvent,
    xsgen::CrossSection,
    xsphys::CrossSection,
    pl::PowerLaw,
    anglesampler::UniformAngularSampler,
    injectionvolume::SymmetricInjectionCylinder,
    geo::Geometry
)
    n = p_phys(event, xsphys, geo)
    d = p_mc(event, pl, xsgen, anglesampler, injectionvolume, geo)
    if n==0
        return 0
    end
    w = n / d
    return w
end

function oneweight(
    event::InjectionEvent,
    injector::Injector,
    xsphys::CrossSection,
)
    return oneweight(event, injector.xs, xsphys, injector.powerlaw, injector.anglesampler, injector.injectionvolume, injector.geo)
end

function oneweight(
    event::InjectionEvent,
    injectors::Vector{Injector},
    xsphyss::Vector{CrossSection},
)
    weights=Vector{Float64}([])
    for (injector,xsphys) in zip(injectors, xsphyss)

        n = p_phys(event, xsphys, injector.geo)
        d = p_mc(event, injector.powerlaw, injector.xs, injector.anglesampler, injector.injectionvolume, injector.geo)
        if n==0
            return 0
        end
        push!(weights, d / n)
    end 
    w = sum(weights)
    return 1 / w 
end
