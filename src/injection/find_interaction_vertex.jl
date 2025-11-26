air_density = 1.2e-3 * u"g"/u"cm"^3
rock_density = 2.6 * u"g"/u"cm"^3

function find_vertex_distance(
    direction::Direction{T,U},
    distance::Quantity{T,U},
    intersections::Vector{Intersection{T,U}},
    epsilon::Float64=1e-3
) where {T,U}

    prem_densities = [2.9u"g"/u"cm"^3, rock_density, rock_density]
    prev_distance = 0.0u"km"
    column_depth = 0.0u"g/cm^2"
    seen_rock = false
    for intersection in intersections
        density = nothing
        if typeof(intersection)==TriangleIntersection{T,U}
            entering_rock = dot(direction, intersection.normal) < 0
            #@show entering_rock
            density = entering_rock ? rock_density : air_density
            if entering_rock
                seen_rock = true
            end
        elseif typeof(intersection)==SphereIntersection{T,U}
            seen_rock = true
            density = pop!(prem_densities)
        end
        if ~seen_rock
            @show "We didn't see rock!!"
            continue
        end
        section_length = intersection.distance - prev_distance
        if section_length > distance
            column_depth += distance * density
            distance = 0.0u"m"
            break
        end
        column_depth += section_length * density
        distance -= section_length
        prev_distance = intersection.distance
    end
    if distance > 0.0u"m"
        println("Distance budget not used up.")
        @show direction.point
    end
    #if column_deptI#h==0.0u""

    idx = 1
    prem_densities = [2.9u"g"/u"cm"^3, rock_density, rock_density]
    target_column_depth = rand(Uniform(0, ustrip(column_depth |> u"g/cm^2"))) * u"g/cm^2"
    tot_cd = target_column_depth
    prev_distance = 0.0u"km"
    tot_distance = 0.0u"km"
    while target_column_depth > 0.0u"g/cm^2"
        intersection = intersections[idx]
        density = nothing
        if typeof(intersection)==TriangleIntersection{T,U}
            density = dot(direction, intersection.normal) < 0 ? rock_density : air_density
        elseif typeof(intersection)==SphereIntersection{T,U}
            density = pop!(prem_densities)
        end
        section_length = intersection.distance - prev_distance
        section_column_depth = section_length * density
        if section_column_depth > target_column_depth
            tot_distance += section_length * target_column_depth / section_column_depth
            target_column_depth = 0.0u"g"/u"cm"^2
        end
        target_column_depth -= section_column_depth
        tot_distance += section_length
        idx += 1
    end
    return tot_distance, tot_cd
end
