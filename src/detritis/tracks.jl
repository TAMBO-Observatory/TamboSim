struct Track{T<:Number}
    ipoint::SVector{3,T}
    fpoint::SVector{3,T}
    direction::Direction
    norm::Float64
    function Track(ipoint::T, fpoint::U, d::Direction, norm::Float64) where {T,U}
        ipoint, fpoint = promote(ipoint, fpoint)
        return new{eltype(ipoint)}(ipoint, fpoint, d, norm)
    end
end

struct TrackStartsOutsideBoxError <: Exception
    message::String
end

function Track(fpoint::SVector{3})
    ipoint = SVector{3}([0, 0, 0])
    d = Direction(fpoint, ipoint)
    l = norm(fpoint .- ipoint)
    return Track(ipoint, fpoint, d, l)
end

function Track(ipoint::SVector{3,T}, fpoint::SVector{3,U}) where {T,U}
    promote(ipoint, fpoint)
    d = Direction(fpoint, ipoint)
    l = norm(fpoint .- ipoint)
    return Track(ipoint, fpoint, d, l)
end

function Track(ipoint::SVector{3}, d::Direction, b::Box)
    fpoint = intersect(ipoint, d, b)
    l = norm(fpoint .- ipoint)
    return Track(ipoint, fpoint, d, l)
end

function (t::Track)(λ)
    return t.ipoint .+ λ * t.norm * t.direction
end

struct Segment
    λstart::Float64
    λwidth::Float64
    pstart::SVector{3}
    length::Float64
    density::Float64
    medium_name::String
end

function Segment(λstart::Float64, λwidth::Float64, t::Track, density::Float64)
    pstart = t(λstart)
    width = t.norm * λwidth
    medium_name = density / (units.gr / units.cm^3) > 1 ? "StandardRock" : "Air"
    range = Segment(λstart, λwidth, pstart, width, density, medium_name)
    return range
end

function Base.show(io::IO, r::Segment)
    print(
        io,
        """
        λstart: $(r.λstart)
        λwidth: $(r.λwidth)
        pstart (m): $(r.pstart / units.m)
        width (m): $(r.length / units.m)
        density (g/cm^3): $(r.density / (units.gr / units.cm^3))
        medium_name: $(r.medium_name)
        """,
    )
end

function Base.intersect(p::SVector{3}, d::Direction, box::Box)
    if !inside(p, box)
        throw(TrackStartsOutsideBoxError("Track does not start inside the box"))
    end
    edges = [box.c1, box.c2]
    λf = Inf
    # Iterate over points which define box
    for edge in edges
        # Points where track shares coordinate with box edges
        prop_λs = Vector((edge .- p) ./ d.proj)
        # Negative λ are backwards moving which is not what we want
        prop_λs[prop_λs .<= 0] .= Inf
        λf = minimum((λf, minimum(prop_λs)))
    end
    return λf * d .+ p
end

"""
    Base.intersect(p0::SVector{3}, d::Direction, plane::Plane)

TBW
"""
function Base.intersect(p0::SVector{3}, d::Direction, plane::Plane)
    norm = sum(plane.n̂.proj .* (plane.x0 .- p0)) / sum(plane.n̂.proj .* d.proj)
    pt = norm * d.proj .+ p0
    dot = sum(d.proj.*plane.n̂.proj) 
    return norm,pt,dot
end

"""
    Base.intersect(t::Track, plane::Plane)

TBW
"""
function Base.intersect(t::Track, plane::Plane)
    return intersect(t.ipoint, t.direction, plane)
end

"""
    Base.intersect(t::Track, b::Box)

TBW
"""
function Base.intersect(t::Track, b::Box)
    return intersect(t.ipoint, t.direction, b)
end

"""
    Base.intersect(t::Track, z::Float64)

TBW
"""
function Base.intersect(t::Track, z::Float64)
    Δz = t.fpoint.z - t.ipoint.z
    root = (z - t.ipoint.z) / Δz
    if root < 0
        root = Inf
    elseif root > 1
        root = Inf
    end
    return root
end

"""
    Base.intersect(t::Track, v::Function)

TBW
"""
function Base.intersect(t::Track, geo::Geometry)
    oned_valley(λ) = geo(t(λ).x, t(λ).y)
    root_func(λ) = oned_valley(λ) - t(λ).z
    zeros = find_zeros(root_func, 0, 1)
    return zeros
end

"""
    Base.intersect(t::Track, geo::Geometry)

TBW
"""
#function Base.intersect(t::Track, geo::Geometry)
#    #ixs = intersect.(Ref(t), g.zboundaries)
#    ixs = intersect(t, geo)
#    ixs = ixs[ixs .<= 1]
#    return ixs = sort(ixs)
#end

"""
    Base.reverse(t::Track)

TBW
"""
function Base.reverse(t::Track)
    return Track(t.fpoint, t.ipoint)
end

#"""
#    reduce_f(t::Track, f)
#
#TBW
#"""
#function reduce_f(t::Track, f)
#    return 
#end

"""
    inversecolumndepth(tr::Track, cd::T, g::Geometry) where {T<:Number}

TBW
"""
function inversecolumndepth(tr::Track, cd::T, g::Geometry) where {T<:Number}
    segments = computesegments(tr, g)
    return inversecolumndepth(tr, cd, valley, segments)
end

"""
    inversecolumndepth(tr::Track, cd::T, g::Geometry, segments::Vector) where {T<:Number}

TBW
"""
function inversecolumndepth(tr::Track, cd::T, g::Geometry, segments::Vector) where {T<:Number}
    f(λ) = columndepth(tr, λ, segments) - cd
    λ_int = find_zero(f, (0, 1))
    return λ_int
end

"""
    computesegments(t::Track, g::Geometry, ixs)

TBW
"""
function computesegments(t::Track, g::Geometry, ixs)
    rgen = vcat(0, ixs, 1)
    segments = [
        Segment(
            x[1],
            x[2] - x[1],
            t,
            density(t((x[1] + x[2]) / 2), g)
        ) for x in zip(rgen[1:(end - 1)], rgen[2:end])
    ]
    return segments
end

"""
    computesegments(t::Track, g::Geometry)

TBW
"""
function computesegments(t::Track, g::Geometry)
    ixs = intersect(t, g)
    return computesegments(t, g, ixs)
end


"""
    columndepth(t::Track, λ::T, segments::Vector{Segment}) where {T<:Number}

TBW
"""
function columndepth(t::Track, λ::T, segments::Vector{Segment}) where {T<:Number}
    segments = [r for r in segments if r.λstart < λ]
    if length(segments) > 0
        endrange = segments[end]
        segments[end] = Segment(endrange.λstart, λ - endrange.λstart, t, endrange.density)
    end
    cd = 0units[:mwe]
    for r in segments
        cd += r.length * r.density
    end
    return cd
end

"""
    columndepth(t::Track, λ::T, g::Geometry) where {T<:Number}

TBW
"""
function columndepth(t::Track, λ::T, g::Geometry) where {T<:Number}
    segments = computesegments(t, g)
    return columndepth(t, λ, segments)
end

"""
    totalcolumndepth(t::Track, segments::Vector)

TBW
"""
function totalcolumndepth(t::Track, segments::Vector)
    return columndepth(t, 1, segments)
end

"""
    totalcolumndepth(t::Track, g::Geometry)

TBW
"""
function totalcolumndepth(t::Track, g::Geometry)
    segments = computesegments(t, g)
    return totalcolumndepth(t, segments)
end
"""

function has_unobstructed_path(i::SVector{3}, geo::Geometry)
    # Things to not have an unobstructed path if they are inside the mountain
    if inside(i, geo)
        return false
    end
    for idx in 1:size(geo.tambo_bounds,1)
        bound = geo.tambo_bounds[idx, :]
        f = SVector{3, Float64}(bound..., geo(bound))
        t = Track(i, f)
        intersections = intersect(t, geo)
        # By contruction, it intersects at the end of the Track
        if length(intersections) == 1
            return true
        end
    end
"""
