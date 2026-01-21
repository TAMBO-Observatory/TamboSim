"""
Tests for the geometry module including CoordinateSystem, Coordinate, Direction,
Triangle, Sphere, OBB, Plane, and related utilities.

These tests use the actual Tambo types from src/ to ensure code coverage.
"""

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
    cs = CoordinateSystem(origin, rotation)

    @test cs.origin == origin
    @test cs.rotation == rotation
    @test eltype(cs) == Float64
end

# Coordinate tests
function test_coordinate_construction()
    cs = ecefcoordinates

    # Test construction from vector
    c1 = Coordinate([1.0u"m", 2.0u"m", 3.0u"m"], cs)
    @test c1[1] == 1.0u"m"
    @test c1[2] == 2.0u"m"
    @test c1[3] == 3.0u"m"

    # Test construction from x, y, z
    c2 = Coordinate(1.0u"m", 2.0u"m", 3.0u"m", cs)
    @test c2[1] == 1.0u"m"
    @test c2[2] == 2.0u"m"
    @test c2[3] == 3.0u"m"
end

function test_coordinate_arithmetic()
    cs = ecefcoordinates
    c1 = Coordinate([1.0u"m", 2.0u"m", 3.0u"m"], cs)
    c2 = Coordinate([4.0u"m", 5.0u"m", 6.0u"m"], cs)

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
    cs = ecefcoordinates
    c = Coordinate([1.0u"m", 2.0u"m", 3.0u"m"], cs)

    @test length(c) == 3
    @test size(c) == (3,)

    # Test iteration by iterating manually
    count = 0
    for (i, val) in enumerate(c)
        count += 1
        @test val == c[i]
    end
    @test count == 3
end

# Direction tests
function test_direction_construction()
    cs = ecefcoordinates

    # Test construction - should normalize
    d = Direction([1.0, 0.0, 0.0], cs)
    @test d[1] ≈ 1.0
    @test d[2] ≈ 0.0
    @test d[3] ≈ 0.0
end

function test_direction_normalization()
    cs = ecefcoordinates

    # Test that direction is automatically normalized
    d = Direction([2.0, 0.0, 0.0], cs)
    @test norm(d.point) ≈ 1.0

    d2 = Direction([1.0, 1.0, 1.0], cs)
    @test norm(d2.point) ≈ 1.0
end

function test_direction_operations()
    cs = ecefcoordinates
    d1 = Direction([1.0, 0.0, 0.0], cs)
    d2 = Direction([0.0, 1.0, 0.0], cs)

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
    @test coord isa Coordinate
    @test coord[1] == 10.0u"m"
end

# Triangle tests
function test_triangle_construction()
    cs = ecefcoordinates
    v1 = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    v2 = Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
    v3 = Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)

    tri = Triangle(v1, v2, v3)

    @test tri.v1 == v1
    @test tri.v2 == v2
    @test tri.v3 == v3
    @test length(tri) == 3
end

function test_triangle_normal()
    cs = ecefcoordinates
    v1 = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    v2 = Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
    v3 = Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)

    tri = Triangle(v1, v2, v3)
    n = normal(tri)

    # Normal should point in z direction
    @test abs(n[3]) ≈ 1.0
end

function test_triangle_area()
    cs = ecefcoordinates
    v1 = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    v2 = Coordinate([2.0u"m", 0.0u"m", 0.0u"m"], cs)
    v3 = Coordinate([0.0u"m", 2.0u"m", 0.0u"m"], cs)

    tri = Triangle(v1, v2, v3)
    a = area(tri)

    # Area should be 0.5 * base * height = 0.5 * 2 * 2 = 2 m^2
    @test a ≈ 2.0u"m^2"
end

function test_triangle_iteration()
    cs = ecefcoordinates
    v1 = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    v2 = Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
    v3 = Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)

    tri = Triangle(v1, v2, v3)

    vertices = collect(tri)
    @test vertices[1] == v1
    @test vertices[2] == v2
    @test vertices[3] == v3
end

# Sphere tests
function test_sphere_construction()
    cs = ecefcoordinates
    center = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    radius = 100.0u"m"

    sphere = Sphere(center, radius)

    @test sphere.center == center
    @test sphere.radius == radius
end

# Plane tests
function test_plane_construction()
    cs = ecefcoordinates
    point = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    normal_dir = Direction([0.0, 0.0, 1.0], cs)

    plane = Plane(point, normal_dir)

    @test plane.point == point
    @test plane.normal == normal_dir
end

# OBB tests
function test_obb_construction()
    cs = ecefcoordinates
    center = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    axes = AngleAxis(0.0, 0.0, 0.0, 1.0)
    half_extents = SVector{3}([1.0u"m", 1.0u"m", 1.0u"m"])

    obb = OBB(center, axes, half_extents)

    @test obb.center == center
    @test length(obb.half_extents) == 3
    @test length(obb.vertices) == 8
end

function test_obb_vertices()
    cs = ecefcoordinates
    center = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    axes = AngleAxis(0.0, 0.0, 0.0, 1.0)
    half_extents = SVector{3}([1.0u"m", 1.0u"m", 1.0u"m"])

    obb = OBB(center, axes, half_extents)

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
    cart = longlat_to_cart(0.0, 0.0)
    @test cart[1] ≈ 1.0
    @test cart[2] ≈ 0.0
    @test cart[3] ≈ 0.0

    # Test north pole
    cart_pole = longlat_to_cart(0.0, π/2)
    @test cart_pole[3] ≈ 1.0

    # Round trip
    longlat = cart_to_longlat(cart...)
    @test longlat[1] ≈ 0.0 atol=1e-10
    @test longlat[2] ≈ 0.0 atol=1e-10
end

function test_sph_cart_conversion()
    # Test theta=0 (along z-axis)
    cart = sph_to_cart(0.0, 0.0)
    @test cart[3] ≈ 1.0

    # Test theta=pi/2, phi=0 (along x-axis)
    cart2 = sph_to_cart(π/2, 0.0)
    @test cart2[1] ≈ 1.0 atol=1e-10
    @test cart2[3] ≈ 0.0 atol=1e-10
end
