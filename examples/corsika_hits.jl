using JLD2
using LinearAlgebra
using ProgressMeter
using Rotations
using Tambo
using Unitful

basedir = ARGS[1]

function intersect_module_signed(event, bvh)
    ray = Tambo.Ray(event.particle)
    ixs = Tambo.intersect_all(bvh, reverse(ray))
    length(ixs)==0 || return (last(ixs), -1)
    ixs = Tambo.intersect_all(bvh, ray)
    length(ixs)==0 || return (first(ixs), +1)
    return nothing
end

earth = Tambo.Earth("../resources/geometry/colca_valley.h5:colca_valley_30000", "detector1")
cs = Tambo.CoordinateSystem(earth)
bvh = Tambo.BVHTree(earth.topography[earth.detector_region])

sim = jldopen("$(basedir)/simfile_corsika.jld2") do file
    file["sim"]
end

Δy = 125.0u"m"
point = Tambo.Coordinate(sim.config["corsika"]["plane_coordinates"].*u"m", Tambo.ecefcoordinates)
point = convert(cs, point)
direction = Tambo.Direction(sim.config["corsika"]["plane_orientation"], Tambo.ecefcoordinates)
direction = convert(cs, direction)
plane = Tambo.Plane(point, direction)
up = Tambo.Direction([0.0, 0.0, 1.0], Tambo.CoordinateSystem(earth))
Δx = dot(up, plane.normal) * Δy * sqrt(3) / 2

ps = Tambo.Coordinate[]
base_xs = collect(-1000u"m":Δx:750u"m")
base_ys = collect(-2000u"m":Δy:2000u"m")

for (idx, y) in enumerate(base_ys)
   xoffset = mod(idx, 2)==0 ? 0.0u"m" : Δx / 2
   xs = base_xs .+ xoffset
   coords = [Tambo.Coordinate(x, y, 0.0u"m", cs) for x in xs]
   rays = Tambo.Ray.(coords, Ref(up))
   for ray in rays
       ixs = Tambo.intersect_all(bvh, ray)
       if length(ixs)==0
           continue
       end
       push!(ps, ray.origin)
   end
end

detection_units = Tambo.OBB{Float64}[]
half_lengths = [1.0u"m", 1.0u"m", 0.125u"m"]
for p in ps
    ray = Tambo.Ray(p, up)
    ixs = Tambo.intersect_all(bvh, ray)
    n̂ = cross(up, ixs[1].normal)
    ψ = acos(dot(ixs[1].normal, up))
    rot = AngleAxis(ψ, n̂...)
    center = ixs[1].point
    obb = Tambo.OBB(center, rot, half_lengths)
    push!(detection_units, obb)
end
detection_unit_bvh = Tambo.BVHTree(detection_units)

@showprogress for frame in sim.results
    d = "$(basedir)/event_$(lpad(frame["event_id"], 6, "0"))/"
    q = NamedTuple{(:particle, :module_index, :weight), Tuple{Tambo.Particle{Float64}, Int, Float64}}[]
    events = nothing
    try
        events = Tambo.read_corsika(d, cs)
    catch
        continue
    end

    for event in events
        result = intersect_module_signed(event, detection_unit_bvh)
        isnothing(result) && continue
        ix, sign = result
        p = event.particle
        corrected_time = p.time + sign * ix.distance / p.speed
        corrected_particle = Tambo.Particle(p.pdg, p.energy, ix.point, p.direction, corrected_time, p.speed)
        push!(q, (particle=corrected_particle, module_index=ix.index, weight=event.weight))
    end
    frame["corsika_hits_corrected"] = q
end

jldopen("$(basedir)/simfile_corsika.jld2", "w") do file
    file["sim"] = sim
end
