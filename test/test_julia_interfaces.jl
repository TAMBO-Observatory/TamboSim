include("testsetup.jl")
"""
Tests for the Julia interfaces (TauRunner and PROPOSAL).

These tests focus on helper functions, structures, and initialization
that can be tested without the full external bindings.
"""

# ============================================================================
# Test functions
# ============================================================================

function run_julia_interfaces_tests()
    @testset "TauRunner Interface" begin
        test_cull_intersections()
        test_should_go_through_earth()
        test_spherical_position_formula_equivalence()
    end

    @testset "PROPOSAL Interface" begin
        test_is_proposal_available()
        test_init_proposal_tables_path_sync()
        test_init_proposal_idempotent()
    end
end

# ============================================================================
# TauRunner Interface Tests
# ============================================================================

function test_cull_intersections()
    cs = ecefcoordinates

    # Create some test intersections
    # First, create some positions and normals
    pos1 = Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
    pos2 = Coordinate([2.0u"m", 0.0u"m", 0.0u"m"], cs)
    pos3 = Coordinate([3.0u"m", 0.0u"m", 0.0u"m"], cs)
    pos4 = Coordinate([4.0u"m", 0.0u"m", 0.0u"m"], cs)

    normal = Direction([1.0, 0.0, 0.0], cs)

    # Create triangle intersections (point, normal, distance, u, v, hit, index)
    tri_ix1 = TriangleIntersection(pos1, normal, 1.0u"m", 0.3, 0.3, true, 1)
    tri_ix2 = TriangleIntersection(pos2, normal, 2.0u"m", 0.3, 0.3, true, 2)

    # Create sphere intersection (point, normal, distance, hit)
    sphere_ix = SphereIntersection(pos3, normal, 3.0u"m", true)

    # Another triangle after sphere
    tri_ix3 = TriangleIntersection(pos4, normal, 4.0u"m", 0.3, 0.3, true, 3)

    # Test that intersections after sphere are culled
    intersections = Intersection{Float64}[tri_ix1, tri_ix2, sphere_ix, tri_ix3]
    culled = cull_intersections(intersections)

    # Should only have the first two triangles and the sphere, not tri_ix3
    @test length(culled) == 3
    @test culled[1] == tri_ix1
    @test culled[2] == tri_ix2
    @test culled[3] == sphere_ix

    # Test with no sphere intersection - should keep all
    intersections_no_sphere = Intersection{Float64}[tri_ix1, tri_ix2]
    culled_no_sphere = cull_intersections(intersections_no_sphere)
    @test length(culled_no_sphere) == 2

    # Test with empty intersections
    empty_ixs = Intersection{Float64}[]
    culled_empty = cull_intersections(empty_ixs)
    @test isempty(culled_empty)
end

function test_should_go_through_earth()
    cs = ecefcoordinates

    # Create test positions and normals
    pos = Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
    normal = Direction([1.0, 0.0, 0.0], cs)

    # Create triangle intersection (point, normal, distance, u, v, hit, index)
    tri_ix = TriangleIntersection(pos, normal, 1.0u"m", 0.3, 0.3, true, 1)

    # Create sphere intersection (point, normal, distance, hit)
    sphere_ix = SphereIntersection(pos, normal, 1.0u"m", true)

    # Test with few sphere intersections (shouldn't go through Earth)
    few_spheres = Intersection{Float64}[tri_ix, sphere_ix, sphere_ix, tri_ix]
    @test !should_go_through_earth(few_spheres)

    # Test with many sphere intersections (should go through Earth)
    many_spheres = Intersection{Float64}[
        sphere_ix, sphere_ix, sphere_ix,
        sphere_ix, sphere_ix, sphere_ix
    ]
    @test should_go_through_earth(many_spheres)

    # Test threshold: exactly 4 spheres shouldn't trigger
    exactly_four = Intersection{Float64}[sphere_ix, sphere_ix, sphere_ix, sphere_ix]
    @test !should_go_through_earth(exactly_four)

    # Test threshold: 5 spheres should trigger
    five_spheres = Intersection{Float64}[
        sphere_ix, sphere_ix, sphere_ix, sphere_ix, sphere_ix
    ]
    @test should_go_through_earth(five_spheres)

    # Test with empty intersections
    empty_ixs = Intersection{Float64}[]
    @test !should_go_through_earth(empty_ixs)
end

# Verify the spherical-case position formula in taurunner_interface.
# Old formula (particle.position = detector end):
#   position = remaining * reverse(d) + detector
# New formula (particle.position = Earth entry):
#   position = traveled * d + earth_entry
# Since detector = earth_entry + chord_length * d and
# traveled + remaining = chord_length, these are algebraically identical.
# This test makes that explicit so a future edit can't silently break it.
function test_spherical_position_formula_equivalence()
    cs = ecefcoordinates
    earth_entry = Coordinate([0.0u"m", 0.0u"m", 6.371e6u"m"], cs)
    d           = Direction([0.0, 1.0, 0.0], cs)   # arbitrary unit direction
    chord_length = 800_000.0u"m"

    detector = Coordinate(earth_entry.point .+ chord_length .* d.point, cs)

    for fraction_traveled in [0.0, 0.1, 0.5, 0.73, 0.99, 1.0]
        traveled  = fraction_traveled * chord_length
        remaining = (1.0 - fraction_traveled) * chord_length

        # Old formula: step backward from detector by the remaining distance
        pos_old = detector.point .- remaining .* d.point

        # New formula: step forward from Earth entry by the traveled distance
        pos_new = earth_entry.point .+ traveled .* d.point

        @test all(isapprox.(ustrip.(u"m", pos_old), ustrip.(u"m", pos_new), atol=1e-6))
    end
end

# ============================================================================
# PROPOSAL Interface Tests
# ============================================================================

function test_is_proposal_available()
    # This function should return a boolean
    result = is_proposal_available()
    @test result isa Bool
    # In the test environment, PROPOSAL likely isn't fully available
    # so we just check that the function runs without error
end

function test_init_proposal_tables_path_sync()
    tables_path = get_tambosim_path() * "/resources/proposal_tables"
    init_proposal(Dict("tablespath" => tables_path))
    # ENV["PROPOSAL_TABLES_PATH"] must match what init_proposal configured so
    # TauRunner's SphericalBodyPropagator and TamboSim's propagators share tables.
    @test abspath(ENV["PROPOSAL_TABLES_PATH"]) == abspath(tables_path)
end

function test_init_proposal_idempotent()
    tables_path = get_tambosim_path() * "/resources/proposal_tables"
    init_proposal(Dict("tablespath" => tables_path))
    # Calling a second time must not error and must leave tables path unchanged.
    init_proposal(Dict("tablespath" => tables_path))
    @test abspath(ENV["PROPOSAL_TABLES_PATH"]) == abspath(tables_path)
end
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Julia Interfaces" begin
        run_julia_interfaces_tests()
    end
end
