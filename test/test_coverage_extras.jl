"""
Display and utility tests for Tambo.

Tests the show/display methods for all public types and a small set of
module-level utilities (llama progress bar, relativize!).
"""

function run_display_tests()
    cs = ecefcoordinates
    c1 = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    dir_up = Direction([0.0, 0.0, 1.0], cs)
    tri = Triangle(c1,
                   Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs),
                   Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs))
    sphere = Sphere(c1, 1.0u"m")
    ray    = Ray(Coordinate([0.1u"m", 0.1u"m", -1.0u"m"], cs), dir_up)
    plane  = Plane(c1, dir_up)

    @testset "Display methods" begin
        io = IOBuffer()

        # CoordinateSystem
        show(io, cs)
        @test occursin("CoordinateSystem", String(take!(io)))

        # Coordinate single-line and multi-line
        show(io, c1)
        @test occursin("Coordinate", String(take!(io)))
        show(io, MIME"text/plain"(), c1)
        @test occursin("x:", String(take!(io)))

        # Direction single-line and multi-line
        show(io, dir_up)
        @test occursin("Direction", String(take!(io)))
        show(io, MIME"text/plain"(), dir_up)
        @test occursin("zenith", String(take!(io)))

        # Triangle
        show(io, tri)
        @test occursin("Triangle", String(take!(io)))

        # Sphere single-line and multi-line
        show(io, sphere)
        @test occursin("Sphere", String(take!(io)))
        show(io, MIME"text/plain"(), sphere)
        @test occursin("radius", String(take!(io)))

        # AABB
        aabb = AABB(tri)
        show(io, aabb)
        @test occursin("AABB", String(take!(io)))

        # OBB
        obb = OBB(c1, AngleAxis(0.0, 1.0, 0.0, 0.0), [1.0u"m", 1.0u"m", 1.0u"m"])
        show(io, obb)
        @test occursin("OBB", String(take!(io)))

        # BVH tree and node
        bvh = BVHTree([tri])
        show(io, bvh)
        @test occursin("BVHTree", String(take!(io)))
        show(io, MIME"text/plain"(), bvh)
        @test occursin("object type", String(take!(io)))
        show(io, bvh.root)
        @test occursin("BVHNode", String(take!(io)))

        # Plane
        show(io, plane)
        @test occursin("Plane", String(take!(io)))

        # Ray single-line and multi-line
        show(io, ray)
        @test occursin("Ray", String(take!(io)))
        show(io, MIME"text/plain"(), ray)
        @test occursin("origin", String(take!(io)))

        # Intersections
        ix = TriangleIntersection(c1, dir_up, 1.0u"m", 0.5, 0.5, true, 1)
        show(io, ix)
        @test occursin("TriangleIntersection", String(take!(io)))
        six = SphereIntersection(c1, dir_up, 1.0u"m", true)
        show(io, six)
        @test occursin("SphereIntersection", String(take!(io)))

        # Particle at different energy scales
        for (e, expected) in [(500.0u"GeV", "GeV"), (5e3u"GeV", "TeV"),
                              (5e6u"GeV", "PeV"), (5e9u"GeV", "EeV")]
            p = Particle(TauMinus, e, c1, dir_up)
            show(io, p)
            @test occursin(expected, String(take!(io)))
        end
        p = Particle(TauMinus, 1e5u"GeV", c1, dir_up)
        show(io, MIME"text/plain"(), p)
        s = String(take!(io))
        @test occursin("pdg:", s)
        @test occursin("status:", s)

        # WeightParameters
        wp = WeightParameters(
            1.0u"m^2", 1e3u"GeV", 1e6u"GeV", -2.0,
            0.0, π/2, 0.0, 2π,
            1e4u"GeV", 1e5u"GeV",
            100.0u"g/cm^2", 2.65u"g/cm^3",
            1e-32u"cm^2", 1e-33u"cm^2"
        )
        show(io, wp)
        @test occursin("WeightParameters", String(take!(io)))
        show(io, MIME"text/plain"(), wp)
        @test occursin("Sampling", String(take!(io)))

        # Frame single-line and multi-line
        f = Frame('Q', Dict{String,Any}("key1" => 1, "key2" => "val"))
        show(io, f)
        @test occursin("2 keys", String(take!(io)))
        show(io, MIME"text/plain"(), f)
        @test occursin("key1", String(take!(io)))

        gframe = Frame('G', Dict{String,Any}("parent_key" => 42))
        child_f = Frame('Q', Dict{String,Any}("child_key" => 7))
        child_f.parents['G'] = gframe
        show(io, child_f)
        @test occursin("parents", String(take!(io)))
        show(io, MIME"text/plain"(), child_f)
        @test occursin("parents", String(take!(io)))

        # Samplers
        pl = UnitfulPowerLawSampler(-2.0, 1e3u"GeV", 1e6u"GeV")
        show(io, pl)
        @test occursin("UnitfulPowerLawSampler", String(take!(io)))
        as = UniformAngularSampler(0.0, π/2, 0.0, 2π)
        show(io, as)
        @test occursin("UniformAngularSampler", String(take!(io)))

        # StochasticLoss at different energy scales
        for (e, expected) in [(0.5u"GeV", "MeV"), (50.0u"GeV", "GeV"), (5e3u"GeV", "TeV")]
            loss = StochasticLoss(1, e, c1)
            show(io, loss)
            @test occursin(expected, String(take!(io)))
        end
    end

    @testset "Llama progress" begin
        @test LlamaBarGlyphs isa BarGlyphs
        @test llama_progress(10; desc="Test") isa ProgressMeter.Progress
        @test llama_progress(10) isa ProgressMeter.Progress
        print_llama()
        @test true
    end

    @testset "relativize!" begin
        rd = Dict{String,Any}(
            "path"   => "_TAMBOSIM_PATH_/data",
            "nested" => Dict{String,Any}("p" => "_TAMBOSIM_PATH_/x")
        )
        Tambo.relativize!(rd)
        @test !occursin("_TAMBOSIM_PATH_", rd["path"])
        @test !occursin("_TAMBOSIM_PATH_", rd["nested"]["p"])
    end
end
