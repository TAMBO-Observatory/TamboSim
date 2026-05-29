include("testsetup.jl")
"""
Tests for the geometry module including CoordinateSystem, Coordinate, Direction,
Triangle, Sphere, OBB, Plane, and related utilities.

These tests use the actual TamboSim types from src/ to ensure code coverage.
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
        test_cart_to_longlat_coordinate()
        test_cart_to_sph_direction()
        test_validate_triangle()
        test_centroid()
        test_sample_triangle()
        test_compute_rotation()
    end

    @testset "CoordinateSystem from longlat" begin
        test_coordinate_system_from_longlat()
    end

    @testset "Direction Arithmetic" begin
        test_direction_scalar_multiplication()
        test_direction_quantity_multiplication()
    end

    @testset "Plane Conversion" begin
        test_plane_conversion_same_cs()
        test_plane_conversion_different_cs()
    end

    @testset "Geometry queries" begin
        test_upwards_ray_at_coordinate()
        test_upwards_ray_at_particle()
        test_is_above_topography_below()
        test_is_above_topography_above()
        test_is_above_topography_particle_overload()
    end

    @testset "Detector layout" begin
        test_place_detector_units_basic()
        test_place_detector_units_slope_filter()
        test_place_detector_units_spacing()
        test_place_detector_units_tilt_mode()
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
    cart = sph_to_cart(0.0, 0.0)
    @test cart[3] ≈ 1.0

    cart2 = sph_to_cart(π/2, 0.0)
    @test cart2[1] ≈ 1.0 atol=1e-10
    @test cart2[3] ≈ 0.0 atol=1e-10
end

function test_cart_to_longlat_coordinate()
    cs = ecefcoordinates
    c = Coordinate([6371.0e3u"m", 0.0u"m", 0.0u"m"], cs)
    ll = cart_to_longlat(c)
    @test length(ll) == 2
    @test isapprox(ll[1], 0.0, atol=1e-10)
    @test isapprox(ll[2], 0.0, atol=1e-10)
end

function test_cart_to_sph_direction()
    cs = ecefcoordinates
    d = Direction([0.0, 0.0, 1.0], cs)
    theta, _ = cart_to_sph(d)
    @test isapprox(theta, 0.0, atol=1e-10)
end

function test_validate_triangle()
    cs = ecefcoordinates
    v1 = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    v2 = Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
    v3 = Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)
    tri = Triangle(v1, v2, v3)
    center = Coordinate([0.0u"m", 0.0u"m", -1.0u"m"], cs)
    @test validate_triangle(tri, center) isa Bool
end

function test_centroid()
    cs = ecefcoordinates
    v1 = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    v2 = Coordinate([3.0u"m", 0.0u"m", 0.0u"m"], cs)
    v3 = Coordinate([0.0u"m", 3.0u"m", 0.0u"m"], cs)
    tri = Triangle(v1, v2, v3)
    cent = centroid(tri)
    @test cent isa Coordinate
    @test isapprox(cent[1], 1.0u"m")
    @test isapprox(cent[2], 1.0u"m")
end

function test_sample_triangle()
    cs = ecefcoordinates
    v1 = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    v2 = Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
    v3 = Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)
    tri = Triangle(v1, v2, v3)
    Random.seed!(42)
    s = sample(tri)
    @test s isa Coordinate
    # Point must lie within bounding box of triangle
    @test 0.0u"m" <= s[1] <= 1.0u"m"
    @test 0.0u"m" <= s[2] <= 1.0u"m"
end

function test_compute_rotation()
    R = compute_rotation((0.0, 0.0))
    @test size(R) == (3, 3)
    @test isapprox(det(R), 1.0, atol=1e-10)
end

function test_coordinate_system_from_longlat()
    cs_local = CoordinateSystem((0.0, 0.0), 6371.0e3u"m")
    @test cs_local isa CoordinateSystem
    @test eltype(cs_local) == Float64
end

function test_direction_scalar_multiplication()
    cs = ecefcoordinates
    d = Direction([1.0, 0.0, 0.0], cs)
    @test (2.0 * d) isa Direction
    @test (d * 2.0) isa Direction
end

function test_direction_quantity_multiplication()
    cs = ecefcoordinates
    d = Direction([1.0, 0.0, 0.0], cs)
    qc1 = 5.0u"m" * d
    @test qc1 isa Coordinate
    @test isapprox(ustrip(u"m", qc1.point[1]), 5.0, atol=1e-10)
    qc2 = d * 5.0u"m"
    @test qc2 isa Coordinate
end

function test_plane_conversion_same_cs()
    cs = ecefcoordinates
    p = Plane(Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
              Direction([0.0, 0.0, 1.0], cs))
    p2 = convert(cs, p)
    @test p2.point === p.point
end

function test_plane_conversion_different_cs()
    cs  = ecefcoordinates
    cs2 = CoordinateSystem((0.5, 0.5), 6371.0e3u"m")
    p   = Plane(Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs2),
                Direction([0.0, 0.0, 1.0], cs2))
    p2  = convert(cs, p)
    @test CoordinateSystem(p2.point) == cs
end

# Geometry-query tests

function test_upwards_ray_at_coordinate()
    cs  = ecefcoordinates
    pos = Coordinate([0.0u"m", 0.0u"m", 1.0u"m"], cs)   # on the +z axis
    ray = TamboSim.upwards_ray_at(pos)

    @test ray isa Ray
    @test ray.origin === pos
    # Radially outward from [0,0,1] is +z.
    @test isapprox(ray.direction.point, [0.0, 0.0, 1.0]; atol=1e-12)
end

function test_upwards_ray_at_particle()
    cs  = ecefcoordinates
    pos = Coordinate([0.0u"m", 0.0u"m", 1.0u"m"], cs)
    p   = Particle(NuTau, 1.0u"GeV", pos, Direction([1.0, 0.0, 0.0], cs))
    # The Particle overload should match the Coordinate overload, regardless
    # of the particle's direction (which is irrelevant — only position matters).
    @test TamboSim.upwards_ray_at(p).direction.point ==
          TamboSim.upwards_ray_at(pos).direction.point
end

# Construct a single horizontal triangle 5 m above the +z axis,
# spanning a wide enough patch to be hit by any near-vertical ray
# from the axis below.
function _topography_bvh_above()
    cs  = ecefcoordinates
    tri = Triangle(
        Coordinate([-10.0u"m", -10.0u"m", 5.0u"m"], cs),
        Coordinate([ 10.0u"m", -10.0u"m", 5.0u"m"], cs),
        Coordinate([  0.0u"m",  10.0u"m", 5.0u"m"], cs),
    )
    return BVHTree([tri])
end

function test_is_above_topography_below()
    cs  = ecefcoordinates
    bvh = _topography_bvh_above()
    pos = Coordinate([0.0u"m", 0.0u"m", 1.0u"m"], cs)   # below the triangle
    # Upwards ray from pos heads to +z and hits the triangle at z = 5 m.
    @test TamboSim.is_above_topography(pos, bvh) == false
end

function test_is_above_topography_above()
    cs  = ecefcoordinates
    bvh = _topography_bvh_above()
    pos = Coordinate([0.0u"m", 0.0u"m", 10.0u"m"], cs)  # above the triangle
    # Upwards ray from pos still heads to +z, never re-intersecting the triangle.
    @test TamboSim.is_above_topography(pos, bvh) == true
end

function test_is_above_topography_particle_overload()
    cs  = ecefcoordinates
    bvh = _topography_bvh_above()
    pos = Coordinate([0.0u"m", 0.0u"m", 10.0u"m"], cs)
    p   = Particle(NuTau, 1.0u"GeV", pos, Direction([0.0, 0.0, -1.0], cs))
    @test TamboSim.is_above_topography(p, bvh) == TamboSim.is_above_topography(pos, bvh)
end

# Detector-layout tests

# Build a synthetic g_frame/d_frame pair around a single horizontal detector
# triangle at z = 100 m, large enough that a default 125 m hex grid covers
# multiple points within its xy projection.
function _flat_detector_frames(; triangle_half_m=300.0, height_m=100.0, cs=ecefcoordinates)
    half = triangle_half_m
    z    = height_m
    tri  = Triangle(
        Coordinate([-half*u"m", -half*u"m", z*u"m"], cs),
        Coordinate([ half*u"m", -half*u"m", z*u"m"], cs),
        Coordinate([ 0.0u"m",    half*u"m", z*u"m"], cs),
    )
    bvh    = BVHTree([tri])
    g_frame = Frame('G', Dict{String,Any}("cs" => cs))
    d_frame = Frame('D', Dict{String,Any}("detector_bvh" => bvh))
    return g_frame, d_frame
end

function test_place_detector_units_basic()
    g_frame, d_frame = _flat_detector_frames()
    obbs, obb_bvh = TamboSim.place_detector_units(g_frame, d_frame)

    @test obbs isa Vector{<:TamboSim.OBB}
    @test obb_bvh isa BVHTree
    @test length(obbs) > 0                                # at least one module on a flat 600 m triangle
    @test length(obb_bvh.triangles) > 0                   # BVH has the OBB faces
    @test !haskey(d_frame.data, "detector_units")          # function does not mutate
    @test !haskey(d_frame.data, "detector_unit_bvh")
end

function test_place_detector_units_slope_filter()
    g_frame, d_frame = _flat_detector_frames()
    # Horizontal triangle has slope = 0; a negative threshold makes the
    # filter `ψ > max_slope_rad` reject every grid point. With nothing
    # placed, the function should return an empty OBB list and nothing
    # for the BVH (since BVHTree refuses an empty input).
    obbs, obb_bvh = TamboSim.place_detector_units(g_frame, d_frame; max_slope_deg=-1.0)
    @test isempty(obbs)
    @test obb_bvh === nothing
end

function test_place_detector_units_spacing()
    g_frame, d_frame = _flat_detector_frames()
    obbs_coarse, _ = TamboSim.place_detector_units(g_frame, d_frame; spacing=200.0u"m")
    obbs_fine,   _ = TamboSim.place_detector_units(g_frame, d_frame; spacing=100.0u"m")
    @test length(obbs_fine) > length(obbs_coarse)         # smaller spacing → more modules
end

# A "roof": front slope (y < 0) tilts one way, back slope (y > 0) the other,
# so the surface carries TWO distinct normals. Lets us distinguish :terrain
# (per-site orientation → ≥2 distinct axes) from :fixed (one shared axis).
function _roof_detector_frames(; half_m=300.0, base_z=100.0, ridge_h=80.0, cs=ecefcoordinates)
    half = half_m; z = base_z; zr = base_z + ridge_h
    FL = Coordinate([-half*u"m", -half*u"m",  z*u"m"], cs)
    FR = Coordinate([ half*u"m", -half*u"m",  z*u"m"], cs)
    RL = Coordinate([-half*u"m",  0.0*u"m",   zr*u"m"], cs)
    RR = Coordinate([ half*u"m",  0.0*u"m",   zr*u"m"], cs)
    BL = Coordinate([-half*u"m",  half*u"m",  z*u"m"], cs)
    BR = Coordinate([ half*u"m",  half*u"m",  z*u"m"], cs)
    tris = [
        Triangle(FL, FR, RR), Triangle(FL, RR, RL),   # front slope
        Triangle(RL, RR, BR), Triangle(RL, BR, BL),   # back slope
    ]
    bvh    = BVHTree(tris)
    g_frame = Frame('G', Dict{String,Any}("cs" => cs))
    d_frame = Frame('D', Dict{String,Any}("detector_bvh" => bvh))
    return g_frame, d_frame
end

# Compare OBB orientations by their AngleAxis fields (the value is bit-identical
# across sites that share a normal, so exact comparison is appropriate here).
_axis_key(o) = (o.axes.theta, o.axes.axis_x, o.axes.axis_y, o.axes.axis_z)

function test_place_detector_units_tilt_mode()
    g_frame, d_frame = _roof_detector_frames()

    obbs_terrain, _ = TamboSim.place_detector_units(g_frame, d_frame; tilt_mode=:terrain)
    obbs_fixed,   _ = TamboSim.place_detector_units(g_frame, d_frame; tilt_mode=:fixed)

    @test length(obbs_terrain) > 0
    @test length(obbs_fixed) == length(obbs_terrain)      # same sites survive in both modes

    # :terrain follows the two slopes → at least two distinct orientations.
    @test length(unique(_axis_key.(obbs_terrain))) ≥ 2
    # :fixed gives every module the one mean-normal orientation.
    @test length(unique(_axis_key.(obbs_fixed))) == 1

    @test_throws ArgumentError TamboSim.place_detector_units(g_frame, d_frame; tilt_mode=:bogus)

    # Explicit fixed tilt angle: 0° = horizontal (identity), 90° = vertical (ψ = π/2).
    g_flat, d_flat = _flat_detector_frames()
    obbs_h, _ = TamboSim.place_detector_units(g_flat, d_flat; tilt_mode=:fixed, fixed_tilt_deg=0.0)
    obbs_v, _ = TamboSim.place_detector_units(g_flat, d_flat; tilt_mode=:fixed, fixed_tilt_deg=90.0)
    @test all(o -> isapprox(o.axes.theta, 0.0; atol=1e-9), obbs_h)
    @test all(o -> isapprox(o.axes.theta, π/2; rtol=1e-9), obbs_v)
    @test length(unique(_axis_key.(obbs_v))) == 1                  # still one shared orientation

    # fixed_tilt_deg requires :fixed, and must be in range.
    @test_throws ArgumentError TamboSim.place_detector_units(g_flat, d_flat; fixed_tilt_deg=90.0)
    @test_throws ArgumentError TamboSim.place_detector_units(g_flat, d_flat; tilt_mode=:fixed, fixed_tilt_deg=200.0)
end
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Geometry" begin
        run_geometry_tests()
    end
end
