"""
    CrossSection{T}

Represents particle interaction cross-sections using interpolated spline functions.

This struct stores one-dimensional (total) and two-dimensional (differential) cross-sections
as `Spline1D` and `Spline2D` objects, respectively. It also includes an `inverter` spline
for efficient sampling of outgoing energies.

# Fields
- `total_xs::Spline1D`: A 1D spline representing the total cross-section as a function of energy.
- `differential_xs::Spline2D`: A 2D spline representing the differential cross-section as a function of incoming energy and `z` (a normalized outgoing energy parameter).
- `inverter::Spline2D`: A 2D spline used to invert the cumulative distribution function for sampling outgoing energies.
- `es::Vector{Quantity{T,edim,typeof(u"GeV")}}`: A vector of energies (in GeV) for which the cross-sections are defined.
- `emin::Quantity{T,edim,typeof(u"GeV")}`: The minimum energy (in GeV) considered for interactions.
"""
struct CrossSection{T}
    total_xs::Spline1D
    differential_xs::Spline2D
    inverter::Spline2D
    es::Vector{Quantity{T,edim,typeof(u"GeV")}}
    emin::Quantity{T,edim,typeof(u"GeV")}
end

"""
    CrossSection(location::String, epsilon::Float64=1e-6) -> CrossSection

Constructs a `CrossSection` object by loading and interpolating cross-section data from an HDF5 file.

This constructor reads total and differential cross-section data, along with energy and `z` values,
from the specified HDF5 location. It then creates `Spline1D` and `Spline2D` objects for interpolation
and constructs an `inverter` spline for efficient sampling of outgoing energies.

# Arguments
- `location::String`: A string indicating the path to the HDF5 file and the group name
  within it (e.g., "cross_sections.h5:neutrino_nu_e").
- `epsilon::Float64`: A small value used for numerical stability during CDF inversion. Defaults to 1e-6.

# Returns
- A new `CrossSection` object.
"""
function CrossSection(location::String, epsilon::Float64=1e-6)
    filename, groupname = split(location, ":")
    es, zs, tot_xs, diff_xs, emin = h5open(filename) do file
        group = file[groupname]
        es = read(group["energies"]) .* u"GeV"
        zs = read(group["zs"])
        tot_xs = read(group["total_xs"]) .* u"cm^2"
        diff_xs = read(group["differential_xs"]) .* u"cm^2"
        emin = read(group["emin"]) * u"GeV"
        es, zs, tot_xs, diff_xs, emin
    end
    tot_itp = Spline1D(log.(ustrip.(es)), log.(ustrip.(tot_xs)); s=0.0)
    diff_itp = Spline2D(log.(ustrip.(es)), zs, log.(ustrip.(diff_xs)); s=0.5, ky=2)

    int_zs = LinRange(minimum(zs), maximum(zs), 1000)
    u_targets = LinRange(0, 1, 1001)
    
    out = zeros((size(diff_xs, 1), length(u_targets)))
    
    for idx in 1:size(diff_xs, 1)
        slice = diff_xs[idx, :]
        slice = ustrip.(slice)
        lidx, ridx = find_trim_idxs(slice)
        itp = Spline1D(zs[lidx:ridx], log.(slice[lidx:ridx]); s=0.0)
        f(u, p) = exp(itp(u))
    
        ## Subroutine 1 ##
        cdfs = Float64[]
        for z in int_zs
            if z < zs[lidx] || zs[ridx] < z
                push!(cdfs, NaN)
                continue
            end
    
            domain = (minimum(zs[lidx:ridx]), z)
            prob = IntegralProblem(f, domain)
            sol = solve(prob, HCubatureJL(); reltol = 1e-10, abstol = 1e-10)
            push!(cdfs, minimum([epsilon, sol.u]))
        end
        nan_mask = .~isnan.(cdfs)
        cdfs ./= cdfs[nan_mask][end]
    
        ## Subroutine 2 ##
        inverter = Spline1D(cdfs[nan_mask], int_zs[nan_mask]; s=0.0)
        t = Float64[]
    
        for u in u_targets
            if u==0
                push!(t, 0.0)
                continue
            end
            if u==1
                push!(t, 1.0)
                continue
            end
            push!(t, inverter(u))
        end
        out[idx, :] = t
    end
    inverter = Spline2D(log.(ustrip.(es .|> u"GeV")), u_targets, out; s=0)
    return CrossSection(tot_itp, diff_itp, inverter, es, emin)
end

"""
    (xs::CrossSection)(e::Quantity{T, edim, typeof(u"GeV")}) -> Quantity{T,ldim^2,typeof(u"cm^2")}

Evaluates the total cross-section for a given incoming energy.

This method uses the `total_xs` spline to interpolate the total cross-section
at the specified energy `e`. It performs a log-interpolation on the energy axis.

# Arguments
- `e::Quantity{T, edim, typeof(u"GeV")}`: The incoming particle energy.

# Returns
- `Quantity{T,ldim^2,typeof(u"cm^2")}`: The total cross-section in square centimeters.
"""
function (xs::CrossSection)(
    e::Quantity{T, edim, typeof(u"GeV")}
) where {T<:Real}
    # Epsilon for floating point precision issues
    e - minimum(xs.es) > -1e-6u"GeV" || throw(ArgumentError("Energy $(e) out of range for splines"))
    egev = ustrip(e |> u"GeV")
    v = exp(xs.total_xs(log(egev))) * u"cm^2"
    return v
end

"""
    (xs::CrossSection)(ein::Quantity{T,edim,typeof(u"GeV")}, eout::Quantity{T,edim,typeof(u"GeV")}) -> Quantity{T,ldim^2,typeof(u"cm^2")}

Evaluates the differential cross-section for given incoming and outgoing energies.

This method uses the `differential_xs` spline to interpolate the differential cross-section.
The outgoing energy `eout` is normalized to `z` for the interpolation.

# Arguments
- `ein::Quantity{T,edim,typeof(u"GeV")}`: The incoming particle energy.
- `eout::Quantity{T,edim,typeof(u"GeV")}`: The outgoing particle energy.

# Returns
- `Quantity{T,ldim^2,typeof(u"cm^2")}`: The differential cross-section in square centimeters.
"""
function (xs::CrossSection)(
    ein::Quantity{T,edim,typeof(u"GeV")},
    eout::Quantity{T,edim,typeof(u"GeV")}
)::Quantity{T,ldim^2, typeof(u"cm^2")} where {T}
    ein >= eout || throw(ArgumentError("Outgoing energy cannot be greater than incoming energy"))
    eingev = ustrip(ein |> u"GeV")
    eoutgev = ustrip(eout |> u"GeV")
    emin = ustrip(xs.emin)
    z = ustrip((eoutgev - emin)/(eingev - emin))
    v = max(exp(xs.differential_xs(log(eingev), z)), 1e-50) * u"cm^2"
    return v
end

"""
    Base.rand(xs::CrossSection{T}, ein::Quantity{T,edim,typeof(u"GeV")}) -> Quantity{T,edim,typeof(u"GeV")}

Randomly samples an outgoing energy from the differential cross-section distribution.

This method uses the `inverter` spline to perform an inverse transform sampling,
generating an `eout` value corresponding to a random `u` between 0 and 1.

# Arguments
- `xs::CrossSection{T}`: The `CrossSection` object.
- `ein::Quantity{T,edim,typeof(u"GeV")}`: The incoming particle energy.

# Returns
- `Quantity{T,edim,typeof(u"GeV")}`: A randomly sampled outgoing particle energy.
"""
function Base.rand(
    xs::CrossSection{T},
    ein::Quantity{T,edim,typeof(u"GeV")}
)::Quantity{T,edim,typeof(u"GeV")} where {T<:Real}
    # Epsilon for floating point precision issues
    ein - minimum(xs.es) > -1e-6u"GeV" || throw(ArgumentError("Energy $(ein) out of range for splines"))
    u = rand()
    # Catch numerical instabilities for u~1e-20.
    z = max(0, xs.inverter(log(ustrip(ein |> u"GeV")), u))
    return z * (ein - xs.emin) + xs.emin
end

"""
    Base.rand(xs::CrossSection{T}, ein::Quantity{T,edim,typeof(u"GeV")}, n::Int) -> Vector{Quantity{T,edim,typeof(u"GeV")}}

Randomly samples `n` outgoing energies from the differential cross-section distribution.

This method calls `rand(xs, ein)` `n` times to generate multiple outgoing energy samples.

# Arguments
- `xs::CrossSection{T}`: The `CrossSection` object.
- `ein::Quantity{T,edim,typeof(u"GeV")}`: The incoming particle energy.
- `n::Int`: The number of samples to generate.

# Returns
- `Vector{Quantity{T,edim,typeof(u"GeV")}}`: A vector of randomly sampled outgoing particle energies.
"""
function Base.rand(
    xs::CrossSection{T},
    ein::Quantity{T,edim,typeof(u"GeV")},
    n::Int
)::Vector{Quantity{T,edim,typeof(u"GeV")}} where {T<:Real}
    return [rand(xs, ein) for _ in 1:n]
end

"""
    probability(
        xs::CrossSection{T},
        ein::Quantity{T,edim,typeof(u"GeV")},
        eout::Quantity{T,edim,typeof(u"GeV")}
    ) -> T

Calculates the probability of an interaction resulting in a specific outgoing energy.

This is calculated as the ratio of the differential cross-section to the total cross-section.

# Arguments
- `xs::CrossSection{T}`: The `CrossSection` object.
- `ein::Quantity{T,edim,typeof(u"GeV")}`: The incoming particle energy.
- `eout::Quantity{T,edim,typeof(u"GeV")}`: The outgoing particle energy.

# Returns
- `T`: The probability (unitless).
"""
function probability(
    xs::CrossSection{T},
    ein::Quantity{T,edim,typeof(u"GeV")},
    eout::Quantity{T,edim,typeof(u"GeV")}
)::T where {T<:Real}
    @assert eout <= ein "Energy out of range"
    tot_xs = xs(ein)
    diff_xs = xs(ein, eout)
    return diff_xs / tot_xs
end

"""
    probability(xs::CrossSection, event) -> Real

Calculates the probability of an interaction for a given `InjectionEvent`.

This is a convenience method that extracts the incoming and outgoing energies
from the `event` and calls the primary `probability` function.

# Arguments
- `xs::CrossSection`: The `CrossSection` object.
- `event`: An object (e.g., `InjectionEvent`) that has `entry_state` and `final_state` fields,
  each containing an `energy` field.

# Returns
- `Real`: The probability (unitless).
"""
function probability(xs::CrossSection, event)
    return probability(xs, event.entry_state.energy, event.final_state.energy)
end
