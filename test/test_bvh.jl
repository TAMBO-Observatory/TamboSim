"""
Tests for the BVH (Bounding Volume Hierarchy) tree structure.

These tests use the actual Tambo types from src/ to ensure code coverage.
"""

# Import BVH-related functions
import Tambo: merge, surface_area, center

# ============================================================================
# Test functions
# ============================================================================

function run_bvh_tests()
    @testset "AABB" begin
        test_aabb_construction()
        test_aabb_from_triangles()
        test_aabb_merge_test()
        test_aabb_center_test()
    end

    @testset "BVH Construction" begin
        test_bvh_construction_single_triangle()
        test_bvh_construction_multiple_triangles()
    end

    @testset "BVH Intersection" begin
        test_bvh_intersect_single()
        test_bvh_intersect_all_test()
        test_bvh_intersect_miss()
    end
end

# AABB tests
function test_aabb_construction()
    cs = ecefcoordinates
    min_corner = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    max_corner = Coordinate([10.0u"m", 10.0u"m", 10.0u"m"], cs)

    aabb = AABB(min_corner, max_corner)

    @test aabb.min == min_corner
    @test aabb.max == max_corner
end

function test_aabb_from_triangles()
    cs = ecefcoordinates

    # Create triangles at different locations
    tri1 = Triangle(
        Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
        Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs),
        Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)
    )

    tri2 = Triangle(
        Coordinate([5.0u"m", 5.0u"m", 5.0u"m"], cs),
        Coordinate([6.0u"m", 5.0u"m", 5.0u"m"], cs),
        Coordinate([5.0u"m", 6.0u"m", 5.0u"m"], cs)
    )

    aabb = AABB([tri1, tri2])

    # AABB should encompass both triangles
    @test aabb.min[1] <= 0.0u"m"
    @test aabb.min[2] <= 0.0u"m"
    @test aabb.min[3] <= 0.0u"m"
    @test aabb.max[1] >= 6.0u"m"
    @test aabb.max[2] >= 6.0u"m"
    @test aabb.max[3] >= 5.0u"m"
end

function test_aabb_merge_test()
    cs = ecefcoordinates

    aabb1 = AABB(
        Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
        Coordinate([5.0u"m", 5.0u"m", 5.0u"m"], cs)
    )

    aabb2 = AABB(
        Coordinate([3.0u"m", 3.0u"m", 3.0u"m"], cs),
        Coordinate([10.0u"m", 10.0u"m", 10.0u"m"], cs)
    )

    merged = merge(aabb1, aabb2)

    @test merged.min[1] == 0.0u"m"
    @test merged.min[2] == 0.0u"m"
    @test merged.min[3] == 0.0u"m"
    @test merged.max[1] == 10.0u"m"
    @test merged.max[2] == 10.0u"m"
    @test merged.max[3] == 10.0u"m"
end

function test_aabb_center_test()
    cs = ecefcoordinates

    aabb = AABB(
        Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
        Coordinate([10.0u"m", 10.0u"m", 10.0u"m"], cs)
    )

    c = center(aabb)

    @test c[1] == 5.0u"m"
    @test c[2] == 5.0u"m"
    @test c[3] == 5.0u"m"
end

# BVH Construction tests
function test_bvh_construction_single_triangle()
    cs = ecefcoordinates

    tri = Triangle(
        Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
        Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs),
        Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)
    )

    bvh = BVHTree([tri])

    @test bvh isa BVHTree
    @test length(bvh.triangles) == 1
end

function test_bvh_construction_multiple_triangles()
    cs = ecefcoordinates

    # Create multiple triangles
    triangles = Triangle{Float64}[]
    for i in 0:4
        tri = Triangle(
            Coordinate([Float64(i)*u"m", 0.0u"m", 0.0u"m"], cs),
            Coordinate([Float64(i+1)*u"m", 0.0u"m", 0.0u"m"], cs),
            Coordinate([Float64(i+0.5)*u"m", 1.0u"m", 0.0u"m"], cs)
        )
        push!(triangles, tri)
    end

    bvh = BVHTree(triangles)

    @test bvh isa BVHTree
    @test length(bvh.triangles) == 5
end

# BVH Intersection tests
function test_bvh_intersect_single()
    cs = ecefcoordinates

    # Create a single triangle in the XY plane at z=10
    tri = Triangle(
        Coordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs),
        Coordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs),
        Coordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    )

    bvh = BVHTree([tri])

    # Ray pointing in +z direction from origin should hit the triangle
    origin = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = Direction([0.0, 0.0, 1.0], cs)
    ray = Ray(origin, direction)

    intersection = find_intersect(ray, bvh)

    @test !isnothing(intersection)
    @test intersection.hit
    @test intersection.distance ≈ 10.0u"m"
end

function test_bvh_intersect_all_test()
    cs = ecefcoordinates

    # Create two triangles at different z positions
    tri1 = Triangle(
        Coordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs),
        Coordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs),
        Coordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    )

    tri2 = Triangle(
        Coordinate([-5.0u"m", -5.0u"m", 20.0u"m"], cs),
        Coordinate([5.0u"m", -5.0u"m", 20.0u"m"], cs),
        Coordinate([0.0u"m", 5.0u"m", 20.0u"m"], cs)
    )

    bvh = BVHTree([tri1, tri2])

    # Ray pointing in +z direction should hit both triangles
    origin = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = Direction([0.0, 0.0, 1.0], cs)
    ray = Ray(origin, direction)

    intersections = intersect_all(bvh, ray)

    @test length(intersections) == 2
    # First intersection should be closer
    @test intersections[1].distance < intersections[2].distance
    @test intersections[1].distance ≈ 10.0u"m"
    @test intersections[2].distance ≈ 20.0u"m"
end

function test_bvh_intersect_miss()
    cs = ecefcoordinates

    # Create a triangle
    tri = Triangle(
        Coordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs),
        Coordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs),
        Coordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    )

    bvh = BVHTree([tri])

    # Ray far away from the triangle should miss
    origin = Coordinate([100.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = Direction([0.0, 0.0, 1.0], cs)
    ray = Ray(origin, direction)

    intersection = find_intersect(ray, bvh)
    @test isnothing(intersection)
end
