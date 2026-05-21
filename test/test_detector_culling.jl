include("testsetup.jl")
"""
Tests for the detector culling functionality.

These tests cover occlusion computation, face orientation detection,
and the geometric triangle weighting used in injection.
"""

# Import detector culling functions
import TamboSim: faces_forward, compute_occlusion, occlusion_mask_to_faces,
              geometric_triangle_weight, triangles_to_mesh

# ============================================================================
# Test functions
# ============================================================================

function run_detector_culling_tests()
    @testset "faces_forward" begin
        test_faces_forward_towards()
        test_faces_forward_away()
        test_faces_forward_perpendicular()
    end

    @testset "triangles_to_mesh" begin
        test_triangles_to_mesh_single()
        test_triangles_to_mesh_shared_vertices()
    end

    @testset "occlusion_mask_to_faces" begin
        test_occlusion_mask_to_faces_all_visible()
        test_occlusion_mask_to_faces_partial()
    end

    @testset "compute_occlusion" begin
        test_compute_occlusion_no_occlusion()
        test_compute_occlusion_with_occlusion()
    end

    @testset "geometric_triangle_weight" begin
        test_geometric_triangle_weight_facing()
        test_geometric_triangle_weight_away()
    end
end

# ============================================================================
# faces_forward tests
# ============================================================================

function test_faces_forward_towards()
    cs = ecefcoordinates
    # Normal pointing in +z, direction pointing in -z (towards the face)
    normal = Direction([0.0, 0.0, 1.0], cs)
    direction = Direction([0.0, 0.0, -1.0], cs)

    @test faces_forward(direction, normal) == true
end

function test_faces_forward_away()
    cs = ecefcoordinates
    # Normal pointing in +z, direction pointing in +z (away from face)
    normal = Direction([0.0, 0.0, 1.0], cs)
    direction = Direction([0.0, 0.0, 1.0], cs)

    @test faces_forward(direction, normal) == false
end

function test_faces_forward_perpendicular()
    cs = ecefcoordinates
    # Normal pointing in +z, direction pointing in +x (perpendicular)
    normal = Direction([0.0, 0.0, 1.0], cs)
    direction = Direction([1.0, 0.0, 0.0], cs)

    # Perpendicular should not be considered facing forward (dot = 0)
    @test faces_forward(direction, normal) == false
end

# ============================================================================
# triangles_to_mesh tests
# ============================================================================

function test_triangles_to_mesh_single()
    cs = ecefcoordinates

    tri = Triangle(
        Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
        Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs),
        Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)
    )

    vertices, faces = triangles_to_mesh([tri])

    @test length(vertices) == 3
    @test size(faces) == (1, 3)
    @test faces[1, :] == [1, 2, 3]
end

function test_triangles_to_mesh_shared_vertices()
    cs = ecefcoordinates

    # Two triangles sharing an edge
    tri1 = Triangle(
        Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
        Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs),
        Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)
    )
    tri2 = Triangle(
        Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs),
        Coordinate([1.0u"m", 1.0u"m", 0.0u"m"], cs),
        Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)
    )

    vertices, faces = triangles_to_mesh([tri1, tri2])

    # Should have 4 unique vertices (2 are shared)
    @test length(vertices) == 4
    @test size(faces) == (2, 3)
end

# ============================================================================
# occlusion_mask_to_faces tests
# ============================================================================

function test_occlusion_mask_to_faces_all_visible()
    # All vertices visible
    occlusion_mask = BitVector([1, 1, 1, 1])
    faces = [1 2 3; 2 3 4]  # 2 faces

    result = occlusion_mask_to_faces(occlusion_mask, faces)

    @test length(result) == 2
    @test result[1] ≈ 1.0
    @test result[2] ≈ 1.0
end

function test_occlusion_mask_to_faces_partial()
    # Some vertices occluded
    occlusion_mask = BitVector([1, 1, 0, 0])  # vertices 3 and 4 occluded
    faces = [1 2 3; 2 3 4]  # 2 faces

    result = occlusion_mask_to_faces(occlusion_mask, faces)

    @test length(result) == 2
    @test result[1] ≈ 2/3  # face 1 has vertices 1,2,3: two visible
    @test result[2] ≈ 1/3  # face 2 has vertices 2,3,4: one visible
end

# ============================================================================
# compute_occlusion tests
# ============================================================================

function test_compute_occlusion_no_occlusion()
    cs = ecefcoordinates

    # Single triangle - no self-occlusion possible
    tri = Triangle(
        Coordinate([0.0u"m", 0.0u"m", 10.0u"m"], cs),
        Coordinate([10.0u"m", 0.0u"m", 10.0u"m"], cs),
        Coordinate([5.0u"m", 10.0u"m", 10.0u"m"], cs)
    )

    triangles = [tri]
    bvh = BVHTree(triangles)
    vertices, faces = triangles_to_mesh(triangles)

    # Direction from above (+z looking down)
    d = Direction([0.0, 0.0, -1.0], cs)

    occlusion = compute_occlusion(vertices, faces, d, bvh)

    # All vertices should be visible (no occlusion)
    @test all(occlusion .== 1)
end

function test_compute_occlusion_with_occlusion()
    cs = ecefcoordinates

    # Two triangles: one behind the other
    # Front triangle (closer to viewer at z=10)
    tri_front = Triangle(
        Coordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs),
        Coordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs),
        Coordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    )

    # Back triangle (further from viewer at z=20)
    tri_back = Triangle(
        Coordinate([-5.0u"m", -5.0u"m", 20.0u"m"], cs),
        Coordinate([5.0u"m", -5.0u"m", 20.0u"m"], cs),
        Coordinate([0.0u"m", 5.0u"m", 20.0u"m"], cs)
    )

    triangles = [tri_front, tri_back]
    bvh = BVHTree(triangles)
    vertices, faces = triangles_to_mesh(triangles)

    # Direction from below (-z looking up towards +z)
    # This means viewing from z=0, looking towards positive z
    # The front triangle is at z=10, back at z=20
    # When we look from below, the back triangle vertices should be occluded
    d = Direction([0.0, 0.0, 1.0], cs)

    occlusion = compute_occlusion(vertices, faces, d, bvh)

    # The first 3 vertices (front triangle) should NOT be occluded
    # The last 3 vertices (back triangle) SHOULD be occluded
    @test sum(occlusion[1:3]) == 3  # All front vertices visible
    @test sum(occlusion[4:6]) == 0  # All back vertices occluded
end

# ============================================================================
# geometric_triangle_weight tests
# ============================================================================

function test_geometric_triangle_weight_facing()
    cs = ecefcoordinates

    # Triangle in XY plane with normal pointing up (+z)
    tri = Triangle(
        Coordinate([0.0u"m", 0.0u"m", 10.0u"m"], cs),
        Coordinate([10.0u"m", 0.0u"m", 10.0u"m"], cs),
        Coordinate([5.0u"m", 10.0u"m", 10.0u"m"], cs)
    )

    triangles = [tri]
    normals = normal.(triangles)
    bvh = BVHTree(triangles)

    # Direction pointing down (-z), towards the triangle
    d = Direction([0.0, 0.0, -1.0], cs)

    weights = geometric_triangle_weight(triangles, d, normals, bvh)

    @test length(weights) == 1
    @test weights[1] ≈ 1.0  # Triangle faces the direction and is not occluded
end

function test_geometric_triangle_weight_away()
    cs = ecefcoordinates

    # Triangle in XY plane with normal pointing up (+z)
    tri = Triangle(
        Coordinate([0.0u"m", 0.0u"m", 10.0u"m"], cs),
        Coordinate([10.0u"m", 0.0u"m", 10.0u"m"], cs),
        Coordinate([5.0u"m", 10.0u"m", 10.0u"m"], cs)
    )

    triangles = [tri]
    normals = normal.(triangles)
    bvh = BVHTree(triangles)

    # Direction pointing up (+z), away from the triangle
    d = Direction([0.0, 0.0, 1.0], cs)

    weights = geometric_triangle_weight(triangles, d, normals, bvh)

    @test length(weights) == 1
    @test weights[1] ≈ 0.0  # Triangle faces away from the direction
end
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Detector Culling" begin
        run_detector_culling_tests()
    end
end
