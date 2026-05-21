# Custom display methods for TamboSim types
# These provide nice, descriptive output when printing TamboSim structures

# ============================================================================
# Geometry Types
# ============================================================================

"""
    Base.show(io::IO, cs::CoordinateSystem)

Displays a CoordinateSystem with its origin location.
"""
function Base.show(io::IO, cs::CoordinateSystem{T}) where {T}
    origin = cs.origin
    ox, oy, oz = ustrip.(u"km", origin)
    print(io, "CoordinateSystem{$T}(origin: [$(round(ox, digits=3)), $(round(oy, digits=3)), $(round(oz, digits=3))] km)")
end

"""
    Base.show(io::IO, c::Coordinate)

Displays a Coordinate with its x, y, z components.
"""
function Base.show(io::IO, c::Coordinate{T}) where {T}
    x, y, z = ustrip.(u"m", c.point)
    print(io, "Coordinate{$T}([$(round(x, digits=2)), $(round(y, digits=2)), $(round(z, digits=2))] m)")
end

"""
    Base.show(io::IO, ::MIME"text/plain", c::Coordinate)

Multi-line display for Coordinate showing full details.
"""
function Base.show(io::IO, ::MIME"text/plain", c::Coordinate{T}) where {T}
    x, y, z = ustrip.(u"m", c.point)
    println(io, "Coordinate{$T}:")
    println(io, "  x: $(round(x, digits=6)) m")
    println(io, "  y: $(round(y, digits=6)) m")
    print(io, "  z: $(round(z, digits=6)) m")
end

"""
    Base.show(io::IO, d::Direction)

Displays a Direction with its normalized components.
"""
function Base.show(io::IO, d::Direction{T}) where {T}
    dx, dy, dz = d.point
    print(io, "Direction{$T}([$(round(dx, digits=4)), $(round(dy, digits=4)), $(round(dz, digits=4))])")
end

"""
    Base.show(io::IO, ::MIME"text/plain", d::Direction)

Multi-line display for Direction showing zenith and azimuth angles.
"""
function Base.show(io::IO, ::MIME"text/plain", d::Direction{T}) where {T}
    dx, dy, dz = d.point
    println(io, "Direction{$T}:")
    println(io, "  components: [$(round(dx, digits=6)), $(round(dy, digits=6)), $(round(dz, digits=6))]")
    println(io, "  zenith (θ):  $(round(u"°", d.θ, digits=2))")
    print(io,   "  azimuth (ϕ): $(round(u"°", d.ϕ, digits=2))")
end

"""
    Base.show(io::IO, t::Triangle)

Displays a Triangle with its centroid location.
"""
function Base.show(io::IO, t::Triangle{T}) where {T}
    centroid = (t.v1.point + t.v2.point + t.v3.point) / 3
    cx, cy, cz = ustrip.(u"m", centroid)
    print(io, "Triangle{$T}(centroid: [$(round(cx, digits=1)), $(round(cy, digits=1)), $(round(cz, digits=1))] m)")
end

"""
    Base.show(io::IO, s::Sphere)

Displays a Sphere with its center and radius.
"""
function Base.show(io::IO, s::Sphere{T}) where {T}
    r = ustrip(u"km", s.radius)
    print(io, "Sphere{$T}(radius: $(round(r, digits=3)) km)")
end

"""
    Base.show(io::IO, ::MIME"text/plain", s::Sphere)

Multi-line display for Sphere with center and radius details.
"""
function Base.show(io::IO, ::MIME"text/plain", s::Sphere{T}) where {T}
    cx, cy, cz = ustrip.(u"km", s.center.point)
    r = ustrip(u"km", s.radius)
    println(io, "Sphere{$T}:")
    println(io, "  center: [$(round(cx, digits=3)), $(round(cy, digits=3)), $(round(cz, digits=3))] km")
    print(io, "  radius: $(round(r, digits=3)) km")
end

"""
    Base.show(io::IO, aabb::AABB)

Displays an AABB with its extent.
"""
function Base.show(io::IO, aabb::AABB{T}) where {T}
    extent = aabb.max.point - aabb.min.point
    ex, ey, ez = ustrip.(u"m", extent)
    print(io, "AABB{$T}(extent: [$(round(ex, digits=1)), $(round(ey, digits=1)), $(round(ez, digits=1))] m)")
end

"""
    Base.show(io::IO, obb::OBB)

Displays an OBB with its half-extents.
"""
function Base.show(io::IO, obb::OBB{T}) where {T}
    hx, hy, hz = ustrip.(u"m", obb.half_extents)
    print(io, "OBB{$T}(half_extents: [$(round(hx, digits=2)), $(round(hy, digits=2)), $(round(hz, digits=2))] m)")
end

"""
    Base.show(io::IO, node::BVHNode)

Displays a BVHNode indicating if it's a leaf and how many objects it contains.
"""
function Base.show(io::IO, node::BVHNode{T}) where {T}
    if node.is_leaf
        print(io, "BVHNode{$T}(leaf, $(length(node.indices)) objects)")
    else
        print(io, "BVHNode{$T}(internal)")
    end
end

"""
    Base.show(io::IO, bvh::BVHTree)

Displays a BVHTree with object count.
"""
function Base.show(io::IO, bvh::BVHTree{T,S}) where {T,S}
    print(io, "BVHTree{$T}($(length(bvh.triangles)) objects)")
end

"""
    Base.show(io::IO, ::MIME"text/plain", bvh::BVHTree)

Multi-line display for BVHTree with more details.
"""
function Base.show(io::IO, ::MIME"text/plain", bvh::BVHTree{T,S}) where {T,S}
    println(io, "BVHTree{$T}:")
    println(io, "  object type: $S")
    print(io, "  object count: $(length(bvh.triangles))")
end

"""
    Base.show(io::IO, p::Plane)

Displays a Plane with its normal direction.
"""
function Base.show(io::IO, p::Plane{T}) where {T}
    nx, ny, nz = p.normal.point
    print(io, "Plane{$T}(normal: [$(round(nx, digits=3)), $(round(ny, digits=3)), $(round(nz, digits=3))])")
end

# ============================================================================
# Ray Tracing Types
# ============================================================================

"""
    Base.show(io::IO, r::Ray)

Displays a Ray with its origin and direction.
"""
function Base.show(io::IO, r::Ray{T}) where {T}
    ox, oy, oz = ustrip.(u"m", r.origin.point)
    dx, dy, dz = r.direction.point
    print(io, "Ray{$T}(origin: [$(round(ox, digits=1)), $(round(oy, digits=1)), $(round(oz, digits=1))] m, dir: [$(round(dx, digits=3)), $(round(dy, digits=3)), $(round(dz, digits=3))])")
end

"""
    Base.show(io::IO, ::MIME"text/plain", r::Ray)

Multi-line display for Ray.
"""
function Base.show(io::IO, ::MIME"text/plain", r::Ray{T}) where {T}
    ox, oy, oz = ustrip.(u"m", r.origin.point)
    dx, dy, dz = r.direction.point
    println(io, "Ray{$T}:")
    println(io, "  origin:    [$(round(ox, digits=3)), $(round(oy, digits=3)), $(round(oz, digits=3))] m")
    print(io, "  direction: [$(round(dx, digits=6)), $(round(dy, digits=6)), $(round(dz, digits=6))]")
end

"""
    Base.show(io::IO, ix::TriangleIntersection)

Displays a TriangleIntersection with distance and triangle index.
"""
function Base.show(io::IO, ix::TriangleIntersection{T}) where {T}
    d = ustrip(u"m", ix.distance)
    print(io, "TriangleIntersection{$T}(distance: $(round(d, digits=2)) m, index: $(ix.index))")
end

"""
    Base.show(io::IO, ix::SphereIntersection)

Displays a SphereIntersection with distance.
"""
function Base.show(io::IO, ix::SphereIntersection{T}) where {T}
    d = ustrip(u"m", ix.distance)
    print(io, "SphereIntersection{$T}(distance: $(round(d, digits=2)) m)")
end

# ============================================================================
# Particle Types
# ============================================================================

"""
    Base.show(io::IO, p::Particle)

Displays a Particle with its type and energy.
"""
function Base.show(io::IO, p::Particle{T}) where {T}
    e = ustrip(u"GeV", p.energy)
    if e >= 1e9
        estr = "$(round(e/1e9, digits=2)) EeV"
    elseif e >= 1e6
        estr = "$(round(e/1e6, digits=2)) PeV"
    elseif e >= 1e3
        estr = "$(round(e/1e3, digits=2)) TeV"
    else
        estr = "$(round(e, digits=2)) GeV"
    end
    print(io, "Particle{$T}($(p.pdg), E: $estr)")
end

"""
    Base.show(io::IO, ::MIME"text/plain", p::Particle)

Multi-line display for Particle with full state information.
"""
function Base.show(io::IO, ::MIME"text/plain", p::Particle{T}) where {T}
    e = ustrip(u"GeV", p.energy)
    if e >= 1e9
        estr = "$(round(e/1e9, digits=4)) EeV"
    elseif e >= 1e6
        estr = "$(round(e/1e6, digits=4)) PeV"
    elseif e >= 1e3
        estr = "$(round(e/1e3, digits=4)) TeV"
    else
        estr = "$(round(e, digits=4)) GeV"
    end

    px, py, pz = ustrip.(u"km", p.position.point)
    dx, dy, dz = p.direction.point
    t = ustrip(u"s", p.time)

    println(io, "Particle{$T}:")
    println(io, "  id:        $(p.id)")
    println(io, "  pdg:      $(p.pdg)")
    println(io, "  energy:    $estr")
    println(io, "  position:  [$(round(px, digits=3)), $(round(py, digits=3)), $(round(pz, digits=3))] km")
    println(io, "  direction: [$(round(dx, digits=6)), $(round(dy, digits=6)), $(round(dz, digits=6))]")
    println(io, "  time:      $(round(t, sigdigits=6)) s")
    println(io, "  status:    $(p.status)")
    print(io, "  shape:     $(p.shape)")
end

# ============================================================================
# Frame Types
# ============================================================================

"""
    Base.show(io::IO, f::Frame)

Displays a Frame with its stream type and key count.
"""
function Base.show(io::IO, f::Frame)
    n_keys = length(f.data)
    if isempty(f.parents)
        print(io, "Frame (stream='$(f.stream)', no parents, $(n_keys) keys)")
    else
        parent_streams = join(sort(collect(keys(f.parents))), ", ")
        print(io, "Frame (stream='$(f.stream)', parents: $(parent_streams), $(n_keys) keys)")
    end
end

"""
    Base.show(io::IO, ::MIME"text/plain", f::Frame)

Multi-line display for Frame listing stream, parents, and all keys.
"""
function Base.show(io::IO, ::MIME"text/plain", f::Frame)
    n_keys = length(f.data)
    parent_info = if isempty(f.parents)
        "no parents"
    else
        "parents: " * join(sort(collect(keys(f.parents))), ", ")
    end
    println(io, "Frame (stream='$(f.stream)', $parent_info)")
    print(io, "  keys ($n_keys):")
    for k in sort(collect(String, keys(f.data)))
        print(io, "\n    $k")
    end
end

# ============================================================================
# Sampler Types
# ============================================================================

"""
    Base.show(io::IO, pl::UnitfulPowerLawSampler)

Displays a UnitfulPowerLawSampler with energy range and spectral index.
"""
function Base.show(io::IO, pl::UnitfulPowerLawSampler{T}) where {T}
    emin = ustrip(u"GeV", pl.emin)
    emax = ustrip(u"GeV", pl.emax)

    function format_energy(e)
        if e >= 1e6
            return "$(round(e/1e6, digits=1)) PeV"
        elseif e >= 1e3
            return "$(round(e/1e3, digits=1)) TeV"
        else
            return "$(round(e, digits=1)) GeV"
        end
    end

    print(io, "UnitfulPowerLawSampler{$T}(E: $(format_energy(emin))-$(format_energy(emax)), γ: $(round(pl.γ, digits=2)))")
end

"""
    Base.show(io::IO, as::UniformAngularSampler)

Displays a UniformAngularSampler with angle ranges.
"""
function Base.show(io::IO, as::UniformAngularSampler)
    θmin_deg = round(rad2deg(as.θmin), digits=1)
    θmax_deg = round(rad2deg(as.θmax), digits=1)
    ϕmin_deg = round(rad2deg(as.ϕmin), digits=1)
    ϕmax_deg = round(rad2deg(as.ϕmax), digits=1)
    print(io, "UniformAngularSampler(θ: $(θmin_deg)°-$(θmax_deg)°, ϕ: $(ϕmin_deg)°-$(ϕmax_deg)°)")
end

"""
    Base.show(io::IO, xs::CrossSection)

Displays a CrossSection with energy range.
"""
function Base.show(io::IO, xs::CrossSection{T}) where {T}
    emin_gev = ustrip(u"GeV", minimum(xs.es))
    emax_gev = ustrip(u"GeV", maximum(xs.es))

    function format_energy(e)
        if e >= 1e6
            return "$(round(e/1e6, digits=1)) PeV"
        elseif e >= 1e3
            return "$(round(e/1e3, digits=1)) TeV"
        else
            return "$(round(e, digits=1)) GeV"
        end
    end

    print(io, "CrossSection{$T}(E: $(format_energy(emin_gev))-$(format_energy(emax_gev)), $(length(xs.es)) points)")
end

# ============================================================================
# CORSIKA Types
# ============================================================================

"""
    Base.show(io::IO, iter::MultiParquetIterator)

Compact single-line display for MultiParquetIterator.
"""
function Base.show(io::IO, iter::MultiParquetIterator{T}) where T
    n = length(iter.filenames)
    print(io, "MultiParquetIterator{$T}($n file$(n == 1 ? "" : "s"), chunk_size=$(iter.chunk_size))")
end

"""
    Base.show(io::IO, ::MIME"text/plain", iter::MultiParquetIterator)

Multi-line display for MultiParquetIterator showing progress and file listing.
"""
function Base.show(io::IO, ::MIME"text/plain", iter::MultiParquetIterator{T}) where T
    n = length(iter.filenames)
    opened = iter.current_file_idx - 1

    println(io, "MultiParquetIterator{$T}:")
    println(io, "  files     : $n")
    println(io, "  chunk_size: $(iter.chunk_size)")
    println(io, "  progress  : $opened / $n file$(n == 1 ? "" : "s") opened")
    if n > 0
        println(io, "  file list :")
        limit = min(n, 5)
        for i in 1:limit
            path = iter.filenames[i]
            parts = splitpath(path)
            label = joinpath(parts[max(1, end-3):end]...)
            status = i < opened  ? " (done)" :
                     i == opened ? " (current)" : ""
            println(io, "    [$i] …/$label$status")
        end
        if n > limit
            print(io, "    … and $(n - limit) more")
        end
    end
end

"""
    Base.show(io::IO, ce::CorsikaEvent)

Displays a CorsikaEvent with particle type and weight.
"""
function Base.show(io::IO, ce::CorsikaEvent{T}) where {T}
    e = ustrip(u"GeV", ce.particle.energy)
    if e >= 1e3
        estr = "$(round(e/1e3, digits=2)) TeV"
    else
        estr = "$(round(e, digits=2)) GeV"
    end
    print(io, "CorsikaEvent{$T}($(ce.particle.pdg), E: $estr, w: $(round(ce.weight, sigdigits=3)))")
end

# ============================================================================
# PhaseSpace / PhaseSpacePoint
# ============================================================================

function _format_energy(e_gev)
    if e_gev >= 1e9
        return "$(round(e_gev/1e9, digits=2)) EeV"
    elseif e_gev >= 1e6
        return "$(round(e_gev/1e6, digits=2)) PeV"
    elseif e_gev >= 1e3
        return "$(round(e_gev/1e3, digits=2)) TeV"
    else
        return "$(round(e_gev, digits=2)) GeV"
    end
end

function Base.show(io::IO, ps::PhaseSpace)
    emin = _format_energy(ustrip(u"GeV", ps.emin))
    emax = _format_energy(ustrip(u"GeV", ps.emax))
    print(io, "$(nameof(typeof(ps)))(pdg=$(ps.pdg), E: $(emin)–$(emax), γ=$(round(ps.gamma, digits=2)), N=$(ps.nevent))")
end

function Base.show(io::IO, ::MIME"text/plain", ps::PhaseSpace)
    println(io, "$(nameof(typeof(ps))):")
    println(io, "  pdg:           $(ps.pdg)")
    emin = _format_energy(ustrip(u"GeV", ps.emin))
    emax = _format_energy(ustrip(u"GeV", ps.emax))
    println(io, "  energy:        $(emin) – $(emax)")
    println(io, "  gamma:         $(round(ps.gamma, digits=3))")
    println(io, "  zenith (θ):    $(round(rad2deg(ps.thetamin), digits=2))° – $(round(rad2deg(ps.thetamax), digits=2))°")
    println(io, "  azimuth (ϕ):   $(round(rad2deg(ps.phimin), digits=2))° – $(round(rad2deg(ps.phimax), digits=2))°")
    println(io, "  nevent:        $(ps.nevent)")
    print(io,   "  geometry_hash: $(ps.geometry_hash)")
end

function Base.show(io::IO, pt::PhaseSpacePoint)
    e   = _format_energy(ustrip(u"GeV", pt.E))
    θ   = round(rad2deg(pt.theta), digits=2)
    φ   = round(rad2deg(pt.phi),   digits=2)
    print(io, "$(nameof(typeof(pt)))(E: $(e), θ: $(θ)°, ϕ: $(φ)°)")
end

function _show_point_common!(io::IO, pt::PhaseSpacePoint)
    println(io, "  E:      $(_format_energy(ustrip(u"GeV", pt.E)))")
    println(io, "  theta:  $(round(rad2deg(pt.theta), digits=2))°")
    println(io, "  phi:    $(round(rad2deg(pt.phi),   digits=2))°")
    print(io,   "  area:   $(round(ustrip(u"m^2", pt.area), digits=1)) m²")
end

function Base.show(io::IO, ::MIME"text/plain", pt::PhaseSpacePoint)
    println(io, "$(nameof(typeof(pt))):")
    _show_point_common!(io, pt)
end

function Base.show(io::IO, ::MIME"text/plain", pt::ForcedNeutrinoInteractionPoint)
    println(io, "ForcedNeutrinoInteractionPoint:")
    _show_point_common!(io, pt)
    println(io)
    println(io, "  cd:     $(round(ustrip(u"g/cm^2", pt.cd),    digits=2)) g/cm²")
    println(io, "  rho:    $(round(ustrip(u"g/cm^3", pt.rho),   digits=3)) g/cm³")
    println(io, "  sigma:  $(@sprintf("%.3g", ustrip(u"cm^2", pt.sigma))) cm²")
    print(io,   "  dsigma: $(@sprintf("%.3g", ustrip(u"cm^2", pt.dsigma))) cm²")
end

# ============================================================================
# Stochastic Loss Type
# ============================================================================

"""
    Base.show(io::IO, loss::StochasticLoss)

Displays a StochasticLoss with energy and interaction type.
"""
function Base.show(io::IO, loss::StochasticLoss{T}) where {T}
    e = ustrip(u"GeV", loss.energy)
    if e >= 1e3
        estr = "$(round(e/1e3, digits=2)) TeV"
    elseif e >= 1
        estr = "$(round(e, digits=2)) GeV"
    else
        estr = "$(round(e*1e3, digits=2)) MeV"
    end
    print(io, "StochasticLoss{$T}(type: $(loss.int_type), E: $estr)")
end
