"""
Tests for the geometry module including CoordinateSystem, Coordinate, Direction,
Triangle, Sphere, OBB, Plane, and related utilities.
"""

# ============================================================================
# Type definitions for testing (self-contained)
# ============================================================================

"""CoordinateSystem defines a reference frame with an origin and rotation matrix."""
struct TestCoordinateSystem{T<:Real}
    origin::SVector{3, Quantity{T, ldim, typeof(u"m")}}
    rotation::SMatrix{3,3,T,9}
end

Base.eltype(::TestCoordinateSystem{T}) where {T} = T

const test_ecef = TestCoordinateSystem(
    SVector{3}([0.0u"m", 0.0u"m", 0.0u"m"]),
    SMatrix{3, 3, Float64, 9}([1.0 0.0 0.0; 0.0 1.0 0.0; 0.0 0.0 1.0])
)

"""Coordinate represents a point in 3D space with an associated coordinate system."""
struct TestCoordinate{T<:Real}
    point::SVector{3, Quantity{T, ldim, typeof(u"m")}}
    coordinate_system::TestCoordinateSystem{T}
end

function TestCoordinate(v::Vector, cs::TestCoordinateSystem{T}) where {T}
    return TestCoordinate{T}(SVector{3}(v), cs)
end

function TestCoordinate(x, y, z, cs::TestCoordinateSystem{T}) where {T}
    return TestCoordinate{T}(SVector{3}([x, y, z]), cs)
end

Base.getindex(c::TestCoordinate, i) = c.point[i]
Base.length(::TestCoordinate) = 3
Base.size(::TestCoordinate) = (3,)
Base.iterate(c::TestCoordinate) = iterate(c.point)
Base.iterate(c::TestCoordinate, state) = iterate(c.point, state)

function Base.:+(c1::TestCoordinate{T}, c2::TestCoordinate{T}) where {T}
    return TestCoordinate{T}(c1.point + c2.point, c1.coordinate_system)
end

function Base.:-(c1::TestCoordinate{T}, c2::TestCoordinate{T}) where {T}
    return TestCoordinate{T}(c1.point - c2.point, c1.coordinate_system)
end

function Base.:*(c::TestCoordinate{T}, s::Real) where {T}
    return TestCoordinate{T}(c.point * s, c.coordinate_system)
end

function Base.:/(c::TestCoordinate{T}, s::Real) where {T}
    return TestCoordinate{T}(c.point / s, c.coordinate_system)
end

"""Direction represents a unit vector in 3D space."""
struct TestDirection{T<:Real}
    point::SVector{3, T}
    coordinate_system::TestCoordinateSystem{T}
end

function TestDirection(v::Vector, cs::TestCoordinateSystem{T}) where {T}
    n = norm(v)
    normalized = SVector{3}(v ./ n)
    return TestDirection{T}(normalized, cs)
end

Base.getindex(d::TestDirection, i) = d.point[i]

function LinearAlgebra.dot(d1::TestDirection, d2::TestDirection)
    return dot(d1.point, d2.point)
end

function LinearAlgebra.cross(d1::TestDirection{T}, d2::TestDirection{T}) where {T}
    return cross(d1.point, d2.point)
end

function Base.reverse(d::TestDirection{T}) where {T}
    return TestDirection{T}(-d.point, d.coordinate_system)
end

function Base.:*(d::TestDirection{T}, q::Quantity) where {T}
    return TestCoordinate{T}(d.point * q, d.coordinate_system)
end

"""Triangle represents a triangle defined by three vertices."""
struct TestTriangle{T<:Real}
    v1::TestCoordinate{T}
    v2::TestCoordinate{T}
    v3::TestCoordinate{T}
end

Base.length(::TestTriangle) = 3

function Base.iterate(t::TestTriangle)
    return (t.v1, 1)
end

function Base.iterate(t::TestTriangle, state)
    if state == 1
        return (t.v2, 2)
    elseif state == 2
        return (t.v3, 3)
    else
        return nothing
    end
end

function test_normal(t::TestTriangle{T}) where {T}
    e1 = t.v2.point - t.v1.point
    e2 = t.v3.point - t.v1.point
    n = cross(ustrip.(e1), ustrip.(e2))
    n = n / norm(n)
    return TestDirection{T}(n, t.v1.coordinate_system)
end

function test_area(t::TestTriangle)
    e1 = t.v2.point - t.v1.point
    e2 = t.v3.point - t.v1.point
    return 0.5 * norm(cross(e1, e2))
end

"""Sphere represents a sphere with center and radius."""
struct TestSphere{T<:Real}
    center::TestCoordinate{T}
    radius::Quantity{T, ldim, typeof(u"m")}
end

"""Plane represents a plane defined by a point and normal vector."""
struct TestPlane{T<:Real}
    point::TestCoordinate{T}
    normal::TestDirection{T}
end

"""OBB represents an Oriented Bounding Box."""
struct TestOBB{T<:Real}
    center::TestCoordinate{T}
    axes::SMatrix{3,3,T,9}
    half_extents::SVector{3, Quantity{T, ldim, typeof(u"m")}}
    vertices::Vector{TestCoordinate{T}}
end

function TestOBB(center::TestCoordinate{T}, rotation, half_extents) where {T}
    axes = SMatrix{3,3,T,9}(rotation)
    cs = center.coordinate_system
    he = SVector{3}(half_extents)

    # Generate 8 vertices
    vertices = TestCoordinate{T}[]
    for sx in [-1, 1], sy in [-1, 1], sz in [-1, 1]
        offset = axes * SVector{3}([sx * he[1], sy * he[2], sz * he[3]])
        v = TestCoordinate{T}(center.point + offset, cs)
        push!(vertices, v)
    end

    return TestOBB{T}(center, axes, he, vertices)
end

# Utility functions
function test_longlat_to_cart(lon, lat)
    x = cos(lat) * cos(lon)
    y = cos(lat) * sin(lon)
    z = sin(lat)
    return [x, y, z]
end

function test_cart_to_longlat(x, y, z)
    lon = atan(y, x)
    lat = atan(z, sqrt(x^2 + y^2))
    return [lon, lat]
end

function test_sph_to_cart(theta, phi)
    x = sin(theta) * cos(phi)
    y = sin(theta) * sin(phi)
    z = cos(theta)
    return [x, y, z]
end

# ============================================================================
# Test functions
# ============================================================================

function run_geometry_tests()
    @testset "CoordinateSystem" begin
        test_coordinate_system_construction()
    end

    @testset "Coordinate" begin
        test_coordinate_construction()
        test_coordinate_arithmetic()
        test_coordinate_iteration()
    end

    @testset "Direction" begin
        test_direction_construction()
        test_direction_normalization()
        test_direction_operations()
    end

    @testset "Triangle" begin
        test_triangle_construction()
        test_triangle_normal()
        test_triangle_area()
        test_triangle_iteration()
    end

    @testset "Sphere" begin
        test_sphere_construction()
    end

    @testset "Plane" begin
        test_plane_construction()
    end

    @testset "OBB" begin
        test_obb_construction()
        test_obb_vertices()
    end

    @testset "Geometry Utilities" begin
        test_longlat_cart_conversion()
        test_sph_cart_conversion()
    end
end

# CoordinateSystem tests
function test_coordinate_system_construction()
    origin = SVector{3}([0.0u"m", 0.0u"m", 0.0u"m"])
    rotation = SMatrix{3, 3, Float64, 9}([1.0 0.0 0.0; 0.0 1.0 0.0; 0.0 0.0 1.0])
    cs = TestCoordinateSystem(origin, rotation)

    @test cs.origin == origin
    @test cs.rotation == rotation
    @test eltype(cs) == Float64
end

# Coordinate tests
function test_coordinate_construction()
    cs = test_ecef

    # Test construction from vector
    c1 = TestCoordinate([1.0u"m", 2.0u"m", 3.0u"m"], cs)
    @test c1[1] == 1.0u"m"
    @test c1[2] == 2.0u"m"
    @test c1[3] == 3.0u"m"

    # Test construction from x, y, z
    c2 = TestCoordinate(1.0u"m", 2.0u"m", 3.0u"m", cs)
    @test c2[1] == 1.0u"m"
    @test c2[2] == 2.0u"m"
    @test c2[3] == 3.0u"m"
end

function test_coordinate_arithmetic()
    cs = test_ecef
    c1 = TestCoordinate([1.0u"m", 2.0u"m", 3.0u"m"], cs)
    c2 = TestCoordinate([4.0u"m", 5.0u"m", 6.0u"m"], cs)

    # Test addition
    c_sum = c1 + c2
    @test c_sum[1] == 5.0u"m"
    @test c_sum[2] == 7.0u"m"
    @test c_sum[3] == 9.0u"m"

    # Test subtraction
    c_diff = c2 - c1
    @test c_diff[1] == 3.0u"m"
    @test c_diff[2] == 3.0u"m"
    @test c_diff[3] == 3.0u"m"

    # Test scalar multiplication
    c_scaled = c1 * 2.0
    @test c_scaled[1] == 2.0u"m"
    @test c_scaled[2] == 4.0u"m"
    @test c_scaled[3] == 6.0u"m"

    # Test scalar division
    c_div = c1 / 2.0
    @test c_div[1] == 0.5u"m"
    @test c_div[2] == 1.0u"m"
    @test c_div[3] == 1.5u"m"
end

function test_coordinate_iteration()
    cs = test_ecef
    c = TestCoordinate([1.0u"m", 2.0u"m", 3.0u"m"], cs)

    @test length(c) == 3
    @test size(c) == (3,)

    # Test iteration
    values = collect(c)
    @test values == [1.0u"m", 2.0u"m", 3.0u"m"]
end

# Direction tests
function test_direction_construction()
    cs = test_ecef

    # Test construction - should normalize
    d = TestDirection([1.0, 0.0, 0.0], cs)
    @test d[1] ≈ 1.0
    @test d[2] ≈ 0.0
    @test d[3] ≈ 0.0
end

function test_direction_normalization()
    cs = test_ecef

    # Test that direction is automatically normalized
    d = TestDirection([2.0, 0.0, 0.0], cs)
    @test norm(d.point) ≈ 1.0

    d2 = TestDirection([1.0, 1.0, 1.0], cs)
    @test norm(d2.point) ≈ 1.0
end

function test_direction_operations()
    cs = test_ecef
    d1 = TestDirection([1.0, 0.0, 0.0], cs)
    d2 = TestDirection([0.0, 1.0, 0.0], cs)

    # Test dot product
    @test dot(d1, d2) ≈ 0.0
    @test dot(d1, d1) ≈ 1.0

    # Test cross product
    c = cross(d1, d2)
    @test c[3] ≈ 1.0

    # Test reverse
    d_rev = reverse(d1)
    @test d_rev[1] ≈ -1.0

    # Test multiplication with quantity
    coord = d1 * 10.0u"m"
    @test coord isa TestCoordinate
    @test coord[1] == 10.0u"m"
end

# Triangle tests
function test_triangle_construction()
    cs = test_ecef
    v1 = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    v2 = TestCoordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
    v3 = TestCoordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)

    tri = TestTriangle(v1, v2, v3)

    @test tri.v1 == v1
    @test tri.v2 == v2
    @test tri.v3 == v3
    @test length(tri) == 3
end

function test_triangle_normal()
    cs = test_ecef
    v1 = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    v2 = TestCoordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
    v3 = TestCoordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)

    tri = TestTriangle(v1, v2, v3)
    n = test_normal(tri)

    # Normal should point in z direction
    @test abs(n[3]) ≈ 1.0
end

function test_triangle_area()
    cs = test_ecef
    v1 = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    v2 = TestCoordinate([2.0u"m", 0.0u"m", 0.0u"m"], cs)
    v3 = TestCoordinate([0.0u"m", 2.0u"m", 0.0u"m"], cs)

    tri = TestTriangle(v1, v2, v3)
    a = test_area(tri)

    # Area should be 0.5 * base * height = 0.5 * 2 * 2 = 2 m^2
    @test a ≈ 2.0u"m^2"
end

function test_triangle_iteration()
    cs = test_ecef
    v1 = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    v2 = TestCoordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
    v3 = TestCoordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)

    tri = TestTriangle(v1, v2, v3)

    vertices = collect(tri)
    @test vertices[1] == v1
    @test vertices[2] == v2
    @test vertices[3] == v3
end

# Sphere tests
function test_sphere_construction()
    cs = test_ecef
    center = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    radius = 100.0u"m"

    sphere = TestSphere(center, radius)

    @test sphere.center == center
    @test sphere.radius == radius
end

# Plane tests
function test_plane_construction()
    cs = test_ecef
    point = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    normal = TestDirection([0.0, 0.0, 1.0], cs)

    plane = TestPlane(point, normal)

    @test plane.point == point
    @test plane.normal == normal
end

# OBB tests
function test_obb_construction()
    cs = test_ecef
    center = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    axes = AngleAxis(0.0, 0.0, 0.0, 1.0)
    half_extents = [1.0u"m", 1.0u"m", 1.0u"m"]

    obb = TestOBB(center, axes, half_extents)

    @test obb.center == center
    @test length(obb.half_extents) == 3
    @test length(obb.vertices) == 8
end

function test_obb_vertices()
    cs = test_ecef
    center = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    axes = AngleAxis(0.0, 0.0, 0.0, 1.0)
    half_extents = [1.0u"m", 1.0u"m", 1.0u"m"]

    obb = TestOBB(center, axes, half_extents)

    # OBB should have 8 vertices
    @test length(obb.vertices) == 8

    # All vertices should be 1m away in each axis from center
    for v in obb.vertices
        @test abs(v[1]) ≈ 1.0u"m"
        @test abs(v[2]) ≈ 1.0u"m"
        @test abs(v[3]) ≈ 1.0u"m"
    end
end

# Utility tests
function test_longlat_cart_conversion()
    # Test equator at prime meridian
    cart = test_longlat_to_cart(0.0, 0.0)
    @test cart[1] ≈ 1.0
    @test cart[2] ≈ 0.0
    @test cart[3] ≈ 0.0

    # Test north pole
    cart_pole = test_longlat_to_cart(0.0, π/2)
    @test cart_pole[3] ≈ 1.0

    # Round trip
    longlat = test_cart_to_longlat(cart...)
    @test longlat[1] ≈ 0.0 atol=1e-10
    @test longlat[2] ≈ 0.0 atol=1e-10
end

function test_sph_cart_conversion()
    # Test theta=0 (along z-axis)
    cart = test_sph_to_cart(0.0, 0.0)
    @test cart[3] ≈ 1.0

    # Test theta=pi/2, phi=0 (along x-axis)
    cart2 = test_sph_to_cart(π/2, 0.0)
    @test cart2[1] ≈ 1.0 atol=1e-10
    @test cart2[3] ≈ 0.0 atol=1e-10
end
