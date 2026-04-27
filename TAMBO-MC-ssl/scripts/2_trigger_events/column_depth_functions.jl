using StaticArrays
using Rotations
using Random

function compute_column_depth(viewpoint, direction, geo, medium_name)
    track = Tambo.Track(viewpoint, direction, geo.box)
    segments = Tambo.computesegments(track, geo)

    column_depth = 0.0
    for segment in segments
        if segment.medium_name == medium_name
            column_depth += segment.length
        end
    end

    return column_depth
end

function compute_column_depth(event::Tambo.InjectionEvent, geo::Tambo.Geometry, medium_name)
    reversed_event_direction = reverse(Tambo.Direction(event.final_state.direction.θ, event.final_state.direction.ϕ))
    _, obs_plane_intersection_point, _ = Tambo.intersect(event.final_state.position, reversed_event_direction, plane)
    return compute_column_depth(obs_plane_intersection_point, reversed_event_direction, geo, medium_name)
end

# TODO: This should also work for taus that decay inside the mountain. Will need to revamp this function for that
function compute_column_depth_probability(sim_file, event, resolution, thresold_column_depth, medium_name="StandardRock")
    resolution = deg2rad(resolution)
    
    geo = Tambo.Geometry(sim_file["config"]["geometry"])
    #tambo_coordinates = geo.tambo_coordinates
    #plane = Tambo.Plane(Tambo.Direction(sim_file["config"]["geometry"]["plane_orientation"]...), tambo_coordinates, geo)
    plane = geo.plane
    #tambo_coord_degrees = Tambo.Coord((deg2rad.(config.config["geometry"]["tambo_coordinates"]))...)
    #plane = Tambo.Plane(Tambo.Direction(config.config["geometry"]["plane_orientation"]...), tambo_coord_degrees, geo)

    reversed_event_direction = reverse(Tambo.Direction(event.final_state.direction.θ, event.final_state.direction.ϕ))
    _, obs_plane_intersection_point, _ = Tambo.intersect(event.final_state.position, reversed_event_direction, plane)

    # In case that resolution is 0, we can just compute the column depth directly
    if resolution == 0
        column_depth = 0.0
        try
            column_depth = compute_column_depth(obs_plane_intersection_point, reversed_event_direction, geo, medium_name)
        catch e
            if isa(e, Tambo.TrackStartsOutsideBoxError)
                return -1.0 # TODO: Fix this to treat this case in a reasonable way
            end
        end
        probability_over_threshold = Int(column_depth >= thresold_column_depth)
        return probability_over_threshold
    end

    # Generate N random points on the sphere, Gaussian distributed in theta and flat in phi .
    # These are being distributed around the z-axis, and will later be rotated to be distributed around the direction of the event
    N = 100
    gaussian = Normal(0, resolution)
    thetas = rand(gaussian, N)
    phis = rand(0:2π, N) 
    

    weighted_average_numerator = zeros(N)
    weighted_average_denominator = zeros(N)
    for i in 1:N


        # Rotate random vector so distribution is centered around the direction of the event
        x = sin(thetas[i]) * cos(phis[i])
        y = sin(thetas[i]) * sin(phis[i])
        z = cos(thetas[i])
        v = SVector(x, y, z)

        # Rotate the vector so the distribution of generated vectors is centered around the direction of the event
        # I.e. perform the rotation on this vector that would rotate [0, 0, 1] to the direction of the event
        R = RotZ(reversed_event_direction.ϕ) * RotY(reversed_event_direction.θ)
        rotated_v = R * v

        # Convert back to spherical coordinates
        theta = acos(rotated_v[3])
        phi = atan(rotated_v[2], rotated_v[1])
        smeared_direction = Tambo.Direction(theta, phi)

        column_depth = 0.0
        try
            column_depth = compute_column_depth(obs_plane_intersection_point, smeared_direction, geo, medium_name)
        catch e
            if isa(e, Tambo.TrackStartsOutsideBoxError)
            return -1.0 # TODO: Fix this to treat this case in a reasonable way
            end
        end

        # Computed weighted probability with angular distribution based on resolution as the weights
        weighted_average_numerator[i] = pdf(gaussian, thetas[i]) * (column_depth >= thresold_column_depth)
        weighted_average_denominator[i] = pdf(gaussian, thetas[i])
    end
    
    probability_over_threshold = sum(weighted_average_numerator) / sum(weighted_average_denominator)

    return probability_over_threshold
end
