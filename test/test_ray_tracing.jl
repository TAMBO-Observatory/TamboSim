include("testsetup.jl")
"""
Tests for ray tracing functionality using the actual TamboSim types.
"""

# ============================================================================
# Test functions
# ============================================================================

function run_ray_tracing_tests()
    @testset "Ray" begin
        test_ray_construction()
        test_ray_reverse()
    end

    @testset "Triangle Intersection" begin
        test_triangle_intersection_hit()
        test_triangle_intersection_miss()
        test_triangle_intersection_parallel()
    end

    @testset "Sphere Intersection" begin
        test_sphere_intersection_through()
        test_sphere_intersection_miss()
    end

    @testset "Plane Intersection" begin
        test_plane_intersection_hit()
        test_plane_intersection_parallel()
    end
end

function test_ray_construction()
    cs = ecefcoordinates
    origin = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = Direction([1.0, 0.0, 0.0], cs)

    ray = Ray(origin, direction)

    @test ray.origin == origin
    @test ray.direction == direction
end

function test_ray_reverse()
    cs = ecefcoordinates
    origin = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = Direction([1.0, 0.0, 0.0], cs)

    ray = Ray(origin, direction)
    ray_rev = reverse(ray)

    @test ray_rev.origin == ray.origin
    @test ray_rev.direction[1] ≈ -ray.direction[1]
end

function test_triangle_intersection_hit()
    cs = ecefcoordinates

    # Create a triangle in the XY plane at z=10
    v1 = Coordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v2 = Coordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v3 = Coordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    tri = Triangle(v1, v2, v3)

    # Ray pointing at the triangle
    origin = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = Direction([0.0, 0.0, 1.0], cs)
    ray = Ray(origin, direction)

    # Test intersection using actual TamboSim function
    intersection = find_intersect(ray, tri)

    @test !isnothing(intersection)
    @test intersection.distance ≈ 10.0u"m"
    @test intersection.hit == true
end

function test_triangle_intersection_miss()
    cs = ecefcoordinates

    # Create a triangle in the XY plane at z=10
    v1 = Coordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v2 = Coordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v3 = Coordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    tri = Triangle(v1, v2, v3)

    # Ray pointing away from the triangle
    origin = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = Direction([0.0, 0.0, -1.0], cs)
    ray = Ray(origin, direction)

    # Test intersection
    intersection = find_intersect(ray, tri)

    @test isnothing(intersection)
end

function test_triangle_intersection_parallel()
    cs = ecefcoordinates

    # Create a triangle in the XY plane at z=10
    v1 = Coordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v2 = Coordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v3 = Coordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    tri = Triangle(v1, v2, v3)

    # Ray parallel to the triangle
    origin = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = Direction([1.0, 0.0, 0.0], cs)
    ray = Ray(origin, direction)

    # Test intersection
    intersection = find_intersect(ray, tri)

    @test isnothing(intersection)
end

function test_sphere_intersection_through()
    cs = ecefcoordinates

    # Create a sphere at the origin
    center = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    sphere = Sphere(center, 10.0u"m")

    # Ray that passes through the sphere
    origin = Coordinate([-20.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = Direction([1.0, 0.0, 0.0], cs)
    ray = Ray(origin, direction)

    # Test intersection using actual TamboSim function
    intersections = intersect_all(sphere, ray)

    @test length(intersections) == 2
    @test intersections[1].distance ≈ 10.0u"m"  # Entry at x=-10
    @test intersections[2].distance ≈ 30.0u"m"  # Exit at x=+10
end

function test_sphere_intersection_miss()
    cs = ecefcoordinates

    # Create a sphere at the origin
    center = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    sphere = Sphere(center, 10.0u"m")

    # Ray that misses the sphere
    origin = Coordinate([-20.0u"m", 20.0u"m", 0.0u"m"], cs)
    direction = Direction([1.0, 0.0, 0.0], cs)
    ray = Ray(origin, direction)

    # Test intersection
    intersections = intersect_all(sphere, ray)

    @test length(intersections) == 0
end

function test_plane_intersection_hit()
    cs = ecefcoordinates

    # Create a plane at z=10
    point = Coordinate([0.0u"m", 0.0u"m", 10.0u"m"], cs)
    normal_dir = Direction([0.0, 0.0, 1.0], cs)
    plane = Plane(point, normal_dir)

    # Ray pointing at the plane
    origin = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = Direction([0.0, 0.0, 1.0], cs)
    ray = Ray(origin, direction)

    # Test intersection using actual TamboSim function
    hit_point, t = find_intersection(ray, plane)

    @test !isnothing(hit_point)
    @test t ≈ 10.0u"m"
    @test hit_point[3] ≈ 10.0u"m"
end

function test_plane_intersection_parallel()
    cs = ecefcoordinates

    # Create a plane at z=10
    point = Coordinate([0.0u"m", 0.0u"m", 10.0u"m"], cs)
    normal_dir = Direction([0.0, 0.0, 1.0], cs)
    plane = Plane(point, normal_dir)

    # Ray parallel to the plane
    origin = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = Direction([1.0, 0.0, 0.0], cs)
    ray = Ray(origin, direction)

    # Test intersection
    hit_point, t = find_intersection(ray, plane)

    @test isnothing(hit_point)
    @test isnothing(t)
end
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Ray Tracing" begin
        run_ray_tracing_tests()
    end
end
