air_density = 1.2e-3 * u"g"/u"cm"^3
rock_density = 2.6 * u"g"/u"cm"^3

function find_vertex_distance(
    direction::Direction{T},
    distance::Quantity{T},
    intersections::I,
    epsilon::Float64=1e-3
) where {T<:Real, I<:AbstractVector{Intersection{T}}}

    densities = compute_density(intersections, direction)
    distances = [ix2.distance-ix1.distance for (ix1, ix2) in zip(intersections, intersections[2:end])]
    @assert length(densities)==length(distances)
    column_depth = 0.0u"g/cm^2"
    d, cd = 0.0u"m", 0.0u"g/cm^2"
    for (dist, dens) in zip(distances, densities)
        if d + dist > distance
            cd += (distance - d) * dens
            break
        end
        cd += dist * dens
        d += dist
    end

    target_column_depth = rand(Uniform(0, ustrip(cd |> u"g/cm^2"))) * u"g/cm^2"
    accrued_cd = 0.0u"g/cm^2"
    accrued_d = 0u"m"
    for (dist, dens) in zip(distances, densities)
        segment_cd = dist * dens
        if segment_cd + accrued_cd > target_column_depth
            accrued_d += (target_column_depth - accrued_cd) / dens
            if dens < 1u"g/cm^3"
                println("Expect air")
            end
            break
        end
        accrued_d += dist
        accrued_cd += segment_cd
    end
    return accrued_d, target_column_depth
end

function compute_density(
    ixs::I,
    d::Direction{T}
) where {T<:Real,I<:AbstractVector{Intersection{T}}}

    #prem_densities = [rock_density, rock_density, rock_density]
    densities = Vector{Quantity{T, mdim/ldim^3}}(undef, length(ixs)-1)
    for (idx, ix) in enumerate(ixs[1:end-1])
        if typeof(ix)==TriangleIntersection{T}
            entering_rock = dot(d, ix.normal) < 0
            density = entering_rock ? rock_density : air_density
            densities[idx] = density
        elseif typeof(ix)==SphereIntersection{T}
            # This is not totally try, but I think it should be okay
            density = 2.6u"g/cm^3"
            densities[idx] = density
        end
    end
    return densities
end
