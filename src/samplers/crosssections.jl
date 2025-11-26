struct CrossSection{T}
    total_xs::Spline1D
    differential_xs::Spline2D
    inverter::Spline2D
    es::Vector{Quantity{T,edim,typeof(u"GeV")}}
    emin::Quantity{T,edim,typeof(u"GeV")}
end

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

function (xs::CrossSection)(
    e::Quantity{T, edim, typeof(u"GeV")}
) where {T<:Real}
    # Epsilon for floating point precision issues
    e - minimum(xs.es) > -1e-6u"GeV" || throw("Energy $(e) out of range for splines")
    egev = ustrip(e |> u"GeV")
    v = exp(xs.total_xs(log(egev))) * u"cm^2"
    return v
end

function (xs::CrossSection)(
    ein::Quantity{T,edim,typeof(u"GeV")},
    eout::Quantity{T,edim,typeof(u"GeV")}
)::Quantity{T,ldim^2, typeof(u"cm^2")} where {T}
    ein >= eout || throw("Outgoing energy cannot be greater than incoming energy")
    eingev = ustrip(ein |> u"GeV")
    eoutgev = ustrip(eout |> u"GeV")
    emin = ustrip(xs.emin)
    z = ustrip((eoutgev - emin)/(eingev - emin))
    v = max(exp(xs.differential_xs(log(eingev), z)), 1e-50) * u"cm^2"
    return v
end

function Base.rand(
    xs::CrossSection{T},
    ein::Quantity{T,edim,typeof(u"GeV")}
)::Quantity{T,edim,typeof(u"GeV")} where {T<:Real}
    # Epsilon for floating point precision issues
    ein - minimum(xs.es) > -1e-6u"GeV" || throw("Energy $(ein) out of range for splines")
    u = rand()
    # Catch numerical instabilities for u~1e-20.
    z = max(0, xs.inverter(log(ustrip(ein |> u"GeV")), u))
    return z * (ein - xs.emin) + xs.emin
end

function Base.rand(
    xs::CrossSection{T},
    ein::Quantity{T,edim,typeof(u"GeV")},
    n::Int
)::Vector{Quantity{T,edim,typeof(u"GeV")}} where {T<:Real}
    return [rand(xs, ein) for _ in 1:n]
end

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

function probability(xs::CrossSection, event)
    return probability(xs, event.entry_state.energy, event.final_state.energy)
end
