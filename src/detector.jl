struct SquareDetectionModule
  pos::SVector{3, Float64}
  rot::Rotation
  extent::SVector{3, Float64}
  idx::Int
end

struct CircularDetectionModule
  pos::SVector{3, Float64}
  rot::Rotation
  extent::SVector{2, Float64}
  idx::Int
end

DetectionModule = Union{SquareDetectionModule, CircularDetectionModule}

# TODO add option for bounding box
function inside(pt::SVector{3}, m::SquareDetectionModule)
  offset = m.rot * (m.pos - pt)
  return all(abs.(offset) .< m.extent / 2)
end

function inside(pt::SVector{3}, m::SquareDetectionModule, rmax::Real)
    if any(abs.(pt .- m.pos) .> rmax)
        return false
    end
    #@show "Phase 2"
    return inside(pt, m)
end

function inside(x_pt, y_pt, z_pt, m::SquareDetectionModule, rmax::Real)
    if any(abs.(x_pt .- m.pos[1]) .> rmax) || any(abs.(y_pt .- m.pos[2]) .> rmax) || any(abs.(z_pt .- m.pos[3]) .> rmax)
        return false
    end
    return inside(SVector{3}([x_pt,y_pt,z_pt]), m)
end

function make_triangle_grid(x0::Real, x1::Real, y0::Real, y1::Real, ds::Real)
  dy = ds * sqrt(3) / 2
  ys = y0:dy:y1
  dx = ds
  xs = x0:dx:x1
  gridpoints = SVector{3, Float64}[]
  for x in xs for (idx, y) in enumerate(ys)
    offset = ds / 2
    if idx %2==0
       offset = 0
    end
    v = SVector{3}(x+offset, y, 0)
    push!(gridpoints, v)
  end end
  return gridpoints
end

function make_detector_array(
    array_length::Real,
    ds::Real,
    altmin::Real,
    altmax::Real,
    geo::Geometry,
    ext::SVector{3}
)

    # Make a triangular grid in xy-plane
    plane = geo.plane

    #leave this, something with rotation makes the lengths work out such that
    #the lengths along the x axis 
    xys = make_triangle_grid(-2units.km, 2units.km, -array_length/2, array_length/2, ds)

    # Rotate it to align with the mountain plain
    r = RotZ(geo.plane.n̂.ϕ) * RotY(geo.plane.n̂.θ)
    #RotY(-minesite_normal_vec.θ) * RotZ(-minesite_normal_vec.ϕ)
    xyzs = [r * xy for xy in xys]
    # Remove points that are too high in z
    zmin = altmin - geo.tambo_offset[3]
    zmax = altmax - geo.tambo_offset[3]
    xyzs = filter(xyz -> zmin < xyz[3] && xyz[3] < zmax, xyzs)
    # Make the module list
    modules = SquareDetectionModule[]
    rot = RotY(-geo.plane.n̂.θ) * RotZ(-geo.plane.n̂.ϕ) # This makes the
    #ext = SVector{3}([1.875, 0.8, 0.03]) * units.m
    for (idx, xyz) in enumerate(xyzs)
        push!(modules, SquareDetectionModule(xyz, rot, ext, idx))
    end
    return modules
end

function make_detector_array(
    length::Real,
    ds::Real,
    altmin::Real,
    altmax::Real,
    geo::Geometry,
)
    ext = SVector{3}([1.875, 0.8, 0.03]) * units.m
    return make_detector_array(length, ds, altmin, altmax, geo, ext)
end
