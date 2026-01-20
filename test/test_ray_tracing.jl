"""
Tests for ray tracing functionality.
"""

# ============================================================================
# Ray type definitions for testing
# ============================================================================

struct TestRay{T<:Real}
    origin::TestCoordinate{T}
    direction::TestDirection{T}
end

function test_reverse_ray(ray::TestRay{T}) where {T}
    return TestRay{T}(ray.origin, reverse(ray.direction))
end

# Ray-triangle intersection using Möller–Trumbore algorithm
function test_ray_triangle_intersect(ray::TestRay{T}, tri::TestTriangle{T}) where {T}
    EPSILON = 1e-9

    e1 = tri.v2.point - tri.v1.point
    e2 = tri.v3.point - tri.v1.point

    h = cross(ray.direction.point, ustrip.(e2))
    a = dot(ustrip.(e1), h)

    if abs(a) < EPSILON
        return nothing  # Ray is parallel to triangle
    end

    f = 1.0 / a
    s = ray.origin.point - tri.v1.point
    u = f * dot(ustrip.(s), h)

    if u < 0.0 || u > 1.0
        return nothing
    end

    q = cross(ustrip.(s), ustrip.(e1))
    v = f * dot(ray.direction.point, q)

    if v < 0.0 || u + v > 1.0
        return nothing
    end

    t = f * dot(ustrip.(e2), q)

    if t > EPSILON
        return t * u"m"  # Return distance as Quantity
    end

    return nothing
end

# Ray-sphere intersection
function test_ray_sphere_intersect(ray::TestRay{T}, sphere::TestSphere{T}) where {T}
    oc = ray.origin.point - sphere.center.point
    a = dot(ray.direction.point, ray.direction.point)
    b = 2.0 * dot(ustrip.(oc), ray.direction.point)
    c = dot(ustrip.(oc), ustrip.(oc)) - ustrip(sphere.radius)^2

    discriminant = b^2 - 4*a*c

    if discriminant < 0
        return Quantity{T, ldim, typeof(u"m")}[]
    elseif discriminant == 0
        t = -b / (2*a)
        return t > 0 ? [t * u"m"] : Quantity{T, ldim, typeof(u"m")}[]
    else
        sqrtd = sqrt(discriminant)
        t1 = (-b - sqrtd) / (2*a)
        t2 = (-b + sqrtd) / (2*a)
        results = Quantity{T, ldim, typeof(u"m")}[]
        if t1 > 0
            push!(results, t1 * u"m")
        end
        if t2 > 0
            push!(results, t2 * u"m")
        end
        return results
    end
end

# Ray-plane intersection
function test_ray_plane_intersect(ray::TestRay{T}, plane::TestPlane{T}) where {T}
    denom = dot(ray.direction.point, plane.normal.point)

    if abs(denom) < 1e-9
        return nothing, nothing  # Ray is parallel to plane
    end

    diff = plane.point.point - ray.origin.point
    t = dot(ustrip.(diff), plane.normal.point) / denom

    if t < 0
        return nothing, nothing
    end

    hit_point = TestCoordinate{T}(ray.origin.point + ray.direction.point * t * u"m", ray.origin.coordinate_system)
    return hit_point, t * u"m"
end

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
    cs = test_ecef
    origin = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = TestDirection([1.0, 0.0, 0.0], cs)

    ray = TestRay(origin, direction)

    @test ray.origin == origin
    @test ray.direction == direction
end

function test_ray_reverse()
    cs = test_ecef
    origin = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = TestDirection([1.0, 0.0, 0.0], cs)

    ray = TestRay(origin, direction)
    ray_rev = test_reverse_ray(ray)

    @test ray_rev.origin == ray.origin
    @test ray_rev.direction[1] ≈ -ray.direction[1]
end

function test_triangle_intersection_hit()
    cs = test_ecef

    # Create a triangle in the XY plane at z=10
    v1 = TestCoordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v2 = TestCoordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v3 = TestCoordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    tri = TestTriangle(v1, v2, v3)

    # Ray pointing at the triangle
    origin = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = TestDirection([0.0, 0.0, 1.0], cs)
    ray = TestRay(origin, direction)

    # Test intersection
    t = test_ray_triangle_intersect(ray, tri)

    @test !isnothing(t)
    @test t ≈ 10.0u"m"
end

function test_triangle_intersection_miss()
    cs = test_ecef

    # Create a triangle in the XY plane at z=10
    v1 = TestCoordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v2 = TestCoordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v3 = TestCoordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    tri = TestTriangle(v1, v2, v3)

    # Ray pointing away from the triangle
    origin = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = TestDirection([0.0, 0.0, -1.0], cs)
    ray = TestRay(origin, direction)

    # Test intersection
    t = test_ray_triangle_intersect(ray, tri)

    @test isnothing(t)
end

function test_triangle_intersection_parallel()
    cs = test_ecef

    # Create a triangle in the XY plane at z=10
    v1 = TestCoordinate([-5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v2 = TestCoordinate([5.0u"m", -5.0u"m", 10.0u"m"], cs)
    v3 = TestCoordinate([0.0u"m", 5.0u"m", 10.0u"m"], cs)
    tri = TestTriangle(v1, v2, v3)

    # Ray parallel to the triangle
    origin = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = TestDirection([1.0, 0.0, 0.0], cs)
    ray = TestRay(origin, direction)

    # Test intersection
    t = test_ray_triangle_intersect(ray, tri)

    @test isnothing(t)
end

function test_sphere_intersection_through()
    cs = test_ecef

    # Create a sphere at the origin
    center = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    sphere = TestSphere(center, 10.0u"m")

    # Ray that passes through the sphere
    origin = TestCoordinate([-20.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = TestDirection([1.0, 0.0, 0.0], cs)
    ray = TestRay(origin, direction)

    # Test intersection
    ts = test_ray_sphere_intersect(ray, sphere)

    @test length(ts) == 2
    @test ts[1] ≈ 10.0u"m"  # Entry at x=-10
    @test ts[2] ≈ 30.0u"m"  # Exit at x=+10
end

function test_sphere_intersection_miss()
    cs = test_ecef

    # Create a sphere at the origin
    center = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    sphere = TestSphere(center, 10.0u"m")

    # Ray that misses the sphere
    origin = TestCoordinate([-20.0u"m", 20.0u"m", 0.0u"m"], cs)
    direction = TestDirection([1.0, 0.0, 0.0], cs)
    ray = TestRay(origin, direction)

    # Test intersection
    ts = test_ray_sphere_intersect(ray, sphere)

    @test length(ts) == 0
end

function test_plane_intersection_hit()
    cs = test_ecef

    # Create a plane at z=10
    point = TestCoordinate([0.0u"m", 0.0u"m", 10.0u"m"], cs)
    normal = TestDirection([0.0, 0.0, 1.0], cs)
    plane = TestPlane(point, normal)

    # Ray pointing at the plane
    origin = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = TestDirection([0.0, 0.0, 1.0], cs)
    ray = TestRay(origin, direction)

    # Test intersection
    hit_point, t = test_ray_plane_intersect(ray, plane)

    @test !isnothing(hit_point)
    @test t ≈ 10.0u"m"
    @test hit_point[3] ≈ 10.0u"m"
end

function test_plane_intersection_parallel()
    cs = test_ecef

    # Create a plane at z=10
    point = TestCoordinate([0.0u"m", 0.0u"m", 10.0u"m"], cs)
    normal = TestDirection([0.0, 0.0, 1.0], cs)
    plane = TestPlane(point, normal)

    # Ray parallel to the plane
    origin = TestCoordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    direction = TestDirection([1.0, 0.0, 0.0], cs)
    ray = TestRay(origin, direction)

    # Test intersection
    hit_point, t = test_ray_plane_intersect(ray, plane)

    @test isnothing(hit_point)
    @test isnothing(t)
end
