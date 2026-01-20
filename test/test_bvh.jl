"""
Tests for the BVH (Bounding Volume Hierarchy) tree structure.
"""

# ============================================================================
# AABB (Axis-Aligned Bounding Box) for testing
# ============================================================================

struct TestAABB{T<:Real}
    min_corner::TestCoordinate{T}
    max_corner::TestCoordinate{T}
end

function TestAABB(triangles::Vector{TestTriangle{T}}) where {T}
    if isempty(triangles)
        error("Cannot create AABB from empty triangle list")
    end

    cs = triangles[1].v1.coordinate_system

    # Initialize with first triangle's vertices
    min_x = min(triangles[1].v1[1], triangles[1].v2[1], triangles[1].v3[1])
    min_y = min(triangles[1].v1[2], triangles[1].v2[2], triangles[1].v3[2])
    min_z = min(triangles[1].v1[3], triangles[1].v2[3], triangles[1].v3[3])
    max_x = max(triangles[1].v1[1], triangles[1].v2[1], triangles[1].v3[1])
    max_y = max(triangles[1].v1[2], triangles[1].v2[2], triangles[1].v3[2])
    max_z = max(triangles[1].v1[3], triangles[1].v2[3], triangles[1].v3[3])

    # Expand to include all triangles
    for tri in triangles[2:end]
        min_x = min(min_x, tri.v1[1], tri.v2[1], tri.v3[1])
        min_y = min(min_y, tri.v1[2], tri.v2[2], tri.v3[2])
        min_z = min(min_z, tri.v1[3], tri.v2[3], tri.v3[3])
        max_x = max(max_x, tri.v1[1], tri.v2[1], tri.v3[1])
        max_y = max(max_y, tri.v1[2], tri.v2[2], tri.v3[2])
        max_z = max(max_z, tri.v1[3], tri.v2[3], tri.v3[3])
    end

    min_corner = TestCoordinate([min_x, min_y, min_z], cs)
    max_corner = TestCoordinate([max_x, max_y, max_z], cs)

    return TestAABB{T}(min_corner, max_corner)
end

function test_aabb_merge(a::TestAABB{T}, b::TestAABB{T}) where {T}
    cs = a.min_corner.coordinate_system
    min_corner = TestCoordinate([
        min(a.min_corner[1], b.min_corner[1]),
        min(a.min_corner[2], b.min_corner[2]),
        min(a.min_corner[3], b.min_corner[3])
    ], cs)
    max_corner = TestCoordinate([
        max(a.max_corner[1], b.max_corner[1]),
        max(a.max_corner[2], b.max_corner[2]),
        max(a.max_corner[3], b.max_corner[3])
    ], cs)
    return TestAABB{T}(min_corner, max_corner)
end

function test_aabb_center(aabb::TestAABB{T}) where {T}
    return SVector{3}(
        (aabb.min_corner[1] + aabb.max_corner[1]) / 2,
        (aabb.min_corner[2] + aabb.max_corner[2]) / 2,
        (aabb.min_corner[3] + aabb.max_corner[3]) / 2
    )
end

function test_ray_aabb_intersect(ray::TestRay{T}, aabb::TestAABB{T}) where {T}
    # Slab method for ray-AABB intersection
    tmin = -Inf
    tmax = Inf

    for i in 1:3
        origin_i = ustrip(ray.origin[i])
        dir_i = ray.direction[i]
        min_i = ustrip(aabb.min_corner[i])
        max_i = ustrip(aabb.max_corner[i])

        if abs(dir_i) < 1e-9
            # Ray is parallel to slab
            if origin_i < min_i || origin_i > max_i
                return false
            end
        else
            t1 = (min_i - origin_i) / dir_i
            t2 = (max_i - origin_i) / dir_i

            if t1 > t2
                t1, t2 = t2, t1
            end

            tmin = max(tmin, t1)
            tmax = min(tmax, t2)

            if tmin > tmax
                return false
            end
        end
    end

    return tmax >= 0
end

# ============================================================================
# BVH Tree for testing
# ============================================================================

struct TestBVHNode{T<:Real}
    aabb::TestAABB{T}
    left::Union{Nothing, TestBVHNode{T}}
    right::Union{Nothing, TestBVHNode{T}}
    triangles::Vector{TestTriangle{T}}  # Only for leaf nodes
    is_leaf::Bool
end

struct TestBVHTree{T<:Real}
    root::TestBVHNode{T}
    triangles::Vector{TestTriangle{T}}
end

function test_build_bvh(triangles::Vector{TestTriangle{T}}, max_leaf_size::Int=4) where {T}
    root = test_build_bvh_node(triangles, max_leaf_size)
    return TestBVHTree{T}(root, triangles)
end

function test_build_bvh_node(triangles::Vector{TestTriangle{T}}, max_leaf_size::Int) where {T}
    aabb = TestAABB(triangles)

    if length(triangles) <= max_leaf_size
        # Create leaf node
        return TestBVHNode{T}(aabb, nothing, nothing, triangles, true)
    end

    # Find best axis to split on (use longest axis)
    extent = aabb.max_corner.point - aabb.min_corner.point
    axis = argmax(ustrip.(extent))

    # Sort triangles by centroid on the split axis
    sorted_tris = sort(triangles, by=tri -> begin
        centroid = (tri.v1.point + tri.v2.point + tri.v3.point) / 3
        return ustrip(centroid[axis])
    end)

    # Split in half
    mid = div(length(sorted_tris), 2)
    left_tris = sorted_tris[1:mid]
    right_tris = sorted_tris[mid+1:end]

    left = test_build_bvh_node(left_tris, max_leaf_size)
    right = test_build_bvh_node(right_tris, max_leaf_size)

    return TestBVHNode{T}(aabb, left, right, TestTriangle{T}[], false)
end

struct TestBVHIntersection{T<:Real}
    hit::Bool
    distance::Quantity{T, ldim, typeof(u"m")}
    triangle_idx::Int
end

function test_bvh_intersect(bvh::TestBVHTree{T}, ray::TestRay{T}) where {T}
    return test_bvh_node_intersect(bvh.root, ray, bvh.triangles)
end

function test_bvh_node_intersect(node::TestBVHNode{T}, ray::TestRay{T}, all_triangles::Vector{TestTriangle{T}}) where {T}
    # First check if ray intersects AABB
    if !test_ray_aabb_intersect(ray, node.aabb)
        return nothing
    end

    if node.is_leaf
        # Test all triangles in leaf
        closest_t = Inf * u"m"
        closest_idx = -1

        for (i, tri) in enumerate(node.triangles)
            t = test_ray_triangle_intersect(ray, tri)
            if !isnothing(t) && t < closest_t
                closest_t = t
                # Find actual index in global triangle list
                for (j, global_tri) in enumerate(all_triangles)
                    if global_tri === tri
                        closest_idx = j
                        break
                    end
                end
            end
        end

        if closest_idx > 0
            return TestBVHIntersection{T}(true, closest_t, closest_idx)
        else
            return nothing
        end
    else
        # Recurse into children
        left_hit = isnothing(node.left) ? nothing : test_bvh_node_intersect(node.left, ray, all_triangles)
        right_hit = isnothing(node.right) ? nothing : test_bvh_node_intersect(node.right, ray, all_triangles)

        if isnothing(left_hit) && isnothing(right_hit)
            return nothing
        elseif isnothing(left_hit)
            return right_hit
        elseif isnothing(right_hit)
            return left_hit
        else
            return left_hit.distance < right_hit.distance ? left_hit : right_hit
        end
    end
end

function test_bvh_intersect_all(bvh::TestBVHTree{T}, ray::TestRay{T}) where {T}
    results = TestBVHIntersection{T}[]
    test_bvh_node_intersect_all!(results, bvh.root, ray, bvh.triangles)
    sort!(results, by=ix -> ix.distance)
    return results
end

function test_bvh_node_intersect_all!(results::Vector{TestBVHIntersection{T}}, node::TestBVHNode{T}, ray::TestRay{T}, all_triangles::Vector{TestTriangle{T}}) where {T}
    # First check if ray intersects AABB
    if !test_ray_aabb_intersect(ray, node.aabb)
        return
    end

    if node.is_leaf
        # Test all triangles in leaf
        for (i, tri) in enumerate(node.triangles)
            t = test_ray_triangle_intersect(ray, tri)
            if !isnothing(t)
                # Find actual index in global triangle list
                for (j, global_tri) in enumerate(all_triangles)
                    if global_tri === tri
                        push!(results, TestBVHIntersection{T}(true, t, j))
                        break
                    end
                end
            end
        end
    else
        # Recurse into children
        if !isnothing(node.left)
            test_bvh_node_intersect_all!(results, node.left, ray, all_triangles)
        end
        if !isnothing(node.right)
            test_bvh_node_intersect_all!(results, node.right, ray, all_triangles)
        end
    end
end

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
    cs = test_ecef
    min_corner = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    max_corner = TestCoordinate([10.0u"m", 10.0u"m", 10.0u"m"], cs)

    aabb = TestAABB(min_corner, max_corner)

    @test aabb.min_corner == min_corner
    @test aabb.max_corner == max_corner
end

function test_aabb_from_triangles()
    cs = test_ecef

    # Create triangles at different locations
    tri1 = TestTriangle(
        TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
        TestCoordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs),
        TestCoordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)
    )

    tri2 = TestTriangle(
        TestCoordinate([5.0u"m", 5.0u"m", 5.0u"m"], cs),
        TestCoordinate([6.0u"m", 5.0u"m", 5.0u"m"], cs),
        TestCoordinate([5.0u"m", 6.0u"m", 5.0u"m"], cs)
    )

    aabb = TestAABB([tri1, tri2])

    # AABB should encompass both triangles
    @test aabb.min_corner[1] <= 0.0u"m"
    @test aabb.min_corner[2] <= 0.0u"m"
    @test aabb.min_corner[3] <= 0.0u"m"
    @test aabb.max_corner[1] >= 6.0u"m"
    @test aabb.max_corner[2] >= 6.0u"m"
    @test aabb.max_corner[3] >= 5.0u"m"
end

function test_aabb_merge_test()
    cs = test_ecef

    aabb1 = TestAABB(
        TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
        TestCoordinate([5.0u"m", 5.0u"m", 5.0u"m"], cs)
    )

    aabb2 = TestAABB(
        TestCoordinate([3.0u"m", 3.0u"m", 3.0u"m"], cs),
        TestCoordinate([10.0u"m", 10.0u"m", 10.0u"m"], cs)
    )

    merged = test_aabb_merge(aabb1, aabb2)

    @test merged.min_corner[1] == 0.0u"m"
    @test merged.min_corner[2] == 0.0u"m"
    @test merged.min_corner[3] == 0.0u"m"
    @test merged.max_corner[1] == 10.0u"m"
    @test merged.max_corner[2] == 10.0u"m"
    @test merged.max_corner[3] == 10.0u"m"
end

function test_aabb_center_test()
    cs = test_ecef

    aabb = TestAABB(
        TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
        TestCoordinate([10.0u"m", 10.0u"m", 10.0u"m"], cs)
    )

    center = test_aabb_center(aabb)

    @test center[1] == 5.0u"m"
    @test center[2] == 5.0u"m"
    @test center[3] == 5.0u"m"
end

# BVH Construction tests
function test_bvh_construction_single_triangle()
    cs = test_ecef

    tri = TestTriangle(
        TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs),
        TestCoordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs),
        TestCoordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)
    )

    bvh = test_build_bvh([tri])

    @test bvh isa TestBVHTree
    @test length(bvh.triangles) == 1
end

function test_bvh_construction_multiple_triangles()
    cs = test_ecef

    # Create multiple triangles
    triangles = TestTriangle{Float64}[]
    for i in 0:4
        tri = TestTriangle(
            TestCoordinate([Float64(i)*u"m", 0.0u"m", 0.0u"m"], cs),
            TestCoordinate([Float64(i+1)*u"m", 0.0u"m", 0.0u"m"], cs),
            TestCoordinate([Float64(i+0.5)*u"m", 1.0u"m", 0.0u"m"], cs)
        )
        push!(triangles, tri)
    end

    bvh = test_build_bvh(triangles)

    @test bvh isa TestBVHTree
    @test length(bvh.triangles) == 5
end

# BVH Intersection tests
function test_bvh_intersect_single()
    cs = test_ecef

    # Create a single triangle in the XY plane at z=10
    tri = TestTriangle(
        TestCoordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs),
        TestCoordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs),
        TestCoordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    )

    bvh = test_build_bvh([tri])

    # Ray pointing at the triangle
    origin = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = TestDirection([0.0, 0.0, 1.0], cs)
    ray = TestRay(origin, direction)

    # Test intersection
    ix = test_bvh_intersect(bvh, ray)

    @test !isnothing(ix)
    @test ix.hit == true
end

function test_bvh_intersect_all_test()
    cs = test_ecef

    # Create two triangles at different z positions
    tri1 = TestTriangle(
        TestCoordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs),
        TestCoordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs),
        TestCoordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    )

    tri2 = TestTriangle(
        TestCoordinate([-5.0u"m", -5.0u"m", 20.0u"m"], cs),
        TestCoordinate([5.0u"m", -5.0u"m", 20.0u"m"], cs),
        TestCoordinate([0.0u"m", 5.0u"m", 20.0u"m"], cs)
    )

    bvh = test_build_bvh([tri1, tri2])

    # Ray pointing through both triangles
    origin = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = TestDirection([0.0, 0.0, 1.0], cs)
    ray = TestRay(origin, direction)

    # Test all intersections
    ixs = test_bvh_intersect_all(bvh, ray)

    @test length(ixs) == 2
    @test ixs[1].distance < ixs[2].distance
end

function test_bvh_intersect_miss()
    cs = test_ecef

    # Create a triangle
    tri = TestTriangle(
        TestCoordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs),
        TestCoordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs),
        TestCoordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    )

    bvh = test_build_bvh([tri])

    # Ray that misses the triangle
    origin = TestCoordinate([100.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = TestDirection([0.0, 0.0, 1.0], cs)
    ray = TestRay(origin, direction)

    # Test intersection
    ix = test_bvh_intersect(bvh, ray)

    @test isnothing(ix)
end
