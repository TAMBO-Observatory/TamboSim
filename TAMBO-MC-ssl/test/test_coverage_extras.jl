function run_coverage_extras_tests()

    cs = ecefcoordinates
    c1 = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs)
    c2 = Coordinate([1.0u"m", 0.0u"m", 0.0u"m"], cs)
    c3 = Coordinate([0.0u"m", 1.0u"m", 0.0u"m"], cs)
    c4 = Coordinate([0.0u"m", 0.0u"m", 1.0u"m"], cs)
    dir_up = Direction([0.0, 0.0, 1.0], cs)
    tri = Triangle(c1, c2, c3)
    sphere = Sphere(c1, 1.0u"m")
    ray = Ray(Coordinate([0.1u"m", 0.1u"m", -1.0u"m"], cs), dir_up)
    plane = Plane(c1, dir_up)

    # ---- Display methods ----
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
        obb = OBB(
            c1,
            AngleAxis(0.0, 1.0, 0.0, 0.0),
            [1.0u"m", 1.0u"m", 1.0u"m"]
        )
        show(io, obb)
        @test occursin("OBB", String(take!(io)))

        # BVH
        bvh = BVHTree([tri])
        show(io, bvh)
        @test occursin("BVHTree", String(take!(io)))
        show(io, MIME"text/plain"(), bvh)
        @test occursin("object type", String(take!(io)))

        # BVHNode
        node = bvh.root
        show(io, node)
        @test occursin("BVHNode", String(take!(io)))

        # Plane
        show(io, plane)
        @test occursin("Plane", String(take!(io)))

        # Ray single-line and multi-line
        show(io, ray)
        @test occursin("Ray", String(take!(io)))
        show(io, MIME"text/plain"(), ray)
        @test occursin("origin", String(take!(io)))

        # TriangleIntersection
        ix = TriangleIntersection(c1, dir_up, 1.0u"m", 0.5, 0.5, true, 1)
        show(io, ix)
        @test occursin("TriangleIntersection", String(take!(io)))

        # SphereIntersection
        six = SphereIntersection(c1, dir_up, 1.0u"m", true)
        show(io, six)
        @test occursin("SphereIntersection", String(take!(io)))

        # Particle at different energy scales
        for (e, expected) in [(500.0u"GeV", "GeV"), (5e3u"GeV", "TeV"), (5e6u"GeV", "PeV"), (5e9u"GeV", "EeV")]
            p = Particle(TauMinus, e, c1, dir_up)
            show(io, p)
            s = String(take!(io))
            @test occursin(expected, s)
        end

        # Particle multi-line
        p = Particle(TauMinus, 1e5u"GeV", c1, dir_up)
        show(io, MIME"text/plain"(), p)
        s = String(take!(io))
        @test occursin("type:", s)
        @test occursin("status:", s)

        # WeightParameters single-line and multi-line
        wp = WeightParameters(
            1.0u"m^2",
            1e3u"GeV", 1e6u"GeV",
            -2.0,
            0.0, π/2,
            0.0, 2π,
            1e4u"GeV", 1e5u"GeV",
            100.0u"g/cm^2",
            2.65u"g/cm^3",
            1e-32u"cm^2",
            1e-33u"cm^2"
        )
        show(io, wp)
        @test occursin("WeightParameters", String(take!(io)))
        show(io, MIME"text/plain"(), wp)
        @test occursin("Sampling", String(take!(io)))

        # Frame single-line and multi-line
        f = Frame(Dict("key1" => 1, "key2" => "val"))
        show(io, f)
        @test occursin("2 keys", String(take!(io)))
        show(io, MIME"text/plain"(), f)
        s = String(take!(io))
        @test occursin("key1", s)

        # Frame with parent
        parent_f = Frame(Dict("parent_key" => 42))
        child_f = Frame(Dict("child_key" => 7), parent_f, 'T')
        show(io, child_f)
        @test occursin("has parent", String(take!(io)))
        show(io, MIME"text/plain"(), child_f)
        @test occursin("has parent", String(take!(io)))

        # Simulation
        sim = Simulation(Dict{String,Any}("geometry" => Dict()), Frame[])
        show(io, sim)
        @test occursin("Simulation", String(take!(io)))
        show(io, MIME"text/plain"(), sim)
        @test occursin("events:", String(take!(io)))

        # UnitfulPowerLawSampler
        pl = UnitfulPowerLawSampler(-2.0, 1e3u"GeV", 1e6u"GeV")
        show(io, pl)
        @test occursin("UnitfulPowerLawSampler", String(take!(io)))

        # UniformAngularSampler
        as = UniformAngularSampler(0.0, π/2, 0.0, 2π)
        show(io, as)
        @test occursin("UniformAngularSampler", String(take!(io)))

        # StochasticLoss at different scales
        for (e, expected) in [(0.5u"GeV", "MeV"), (50.0u"GeV", "GeV"), (5e3u"GeV", "TeV")]
            loss = StochasticLoss(1, e, c1)
            show(io, loss)
            s = String(take!(io))
            @test occursin(expected, s)
        end
    end

    # ---- Sampler utilities ----
    @testset "find_trim_idxs" begin
        # Stable data - no trimming needed
        stable = 10.0 .^ range(1, 5, length=10)
        l, r = Tambo.find_trim_idxs(stable)
        @test l == 1
        @test r == length(stable)

        # Data with jumps at edges
        data = copy(stable)
        data[1] = 1e-10  # big jump at start
        data[end] = 1e20  # big jump at end
        l, r = Tambo.find_trim_idxs(data)
        @test l > 1
        @test r < length(data)
    end

    # ---- Llama progress ----
    @testset "Llama progress" begin
        @test LlamaBarGlyphs isa BarGlyphs

        p = llama_progress(10; desc="Test")
        @test p isa ProgressMeter.Progress

        p2 = llama_progress(10)
        @test p2 isa ProgressMeter.Progress

        # Just verify print_llama runs without error
        print_llama()
        @test true
    end

    # ---- Geometry utilities ----
    @testset "Geometry utilities - extra coverage" begin
        # cart_to_longlat(Coordinate)
        c = Coordinate([6371.0e3u"m", 0.0u"m", 0.0u"m"], cs)
        ll = cart_to_longlat(c)
        @test length(ll) == 2
        @test isapprox(ll[1], 0.0, atol=1e-10)
        @test isapprox(ll[2], 0.0, atol=1e-10)

        # cart_to_sph(Direction)
        theta, phi = cart_to_sph(dir_up)
        @test isapprox(theta, 0.0, atol=1e-10)

        # validate_triangle
        center = Coordinate([0.0u"m", 0.0u"m", -1.0u"m"], cs)
        @test validate_triangle(tri, center) isa Bool

        # centroid
        cent = centroid(tri)
        @test cent isa Coordinate

        # sample(Triangle)
        Random.seed!(42)
        s = sample(tri)
        @test s isa Coordinate

        # compute_rotation
        R = compute_rotation((0.0, 0.0))
        @test size(R) == (3, 3)
    end

    # ---- Coordinate system from longlat ----
    @testset "CoordinateSystem from longlat" begin
        cs_local = CoordinateSystem((0.0, 0.0), 6371.0e3u"m")
        @test cs_local isa CoordinateSystem
        @test eltype(cs_local) == Float64
    end

    # ---- Direction operations ----
    @testset "Direction scalar/quantity multiplication" begin
        d1 = Direction([1.0, 0.0, 0.0], cs)

        # scalar * Direction
        d2 = 2.0 * d1
        @test d2 isa Direction

        # Direction * scalar
        d3 = d1 * 2.0
        @test d3 isa Direction

        # Quantity * Direction -> Coordinate
        qc = 5.0u"m" * d1
        @test qc isa Coordinate
        @test isapprox(ustrip(u"m", qc.point[1]), 5.0, atol=1e-10)

        # Direction * Quantity -> Coordinate
        qc2 = d1 * 5.0u"m"
        @test qc2 isa Coordinate
    end

    # ---- Particle state ----
    @testset "Particle state - extra coverage" begin
        # Particle(id, T)
        p1 = Particle(42, Float64)
        @test p1.id == 42
        @test p1.pdg == Tambo.Unknown

        # Particle(T)
        p2 = Particle(Float64)
        @test p2.id == 0

        # particle_mass
        m = Tambo.particle_mass(TauMinus)
        @test ustrip(m) > 0

        # particle_speed from PDG
        v = Tambo.particle_speed(1e5u"GeV", TauMinus)
        @test ustrip(u"m/s", v) > 0
        @test ustrip(u"m/s", v) <= ustrip(u"m/s", 299_792_458.0u"m/s")

        # particle_speed for massless
        v_photon = Tambo.particle_speed(1.0u"GeV", 0.0u"GeV" / (299_792_458.0u"m/s")^2)
        @test isapprox(ustrip(u"m/s", v_photon), 299_792_458.0, rtol=1e-6)

        # lorentz_gamma
        γ = Tambo.lorentz_gamma(1e5u"GeV", 1.77686u"GeV" / (299_792_458.0u"m/s")^2)
        @test γ > 1.0

        # particle_vacuum_range(pdg, energy)
        r = Tambo.particle_vacuum_range(TauMinus, 1e5u"GeV", 0.5)
        @test ustrip(u"m", r) > 0

        # particle_vacuum_range(particle)
        p = Particle(TauMinus, 1e5u"GeV", c1, dir_up)
        r2 = Tambo.particle_vacuum_range(p, 0.5)
        @test ustrip(u"m", r2) > 0
    end

    # ---- OBB intersection ----
    @testset "OBB intersection" begin
        obb = OBB(
            Coordinate([5.0u"m", 0.0u"m", 0.0u"m"], cs),
            AngleAxis(0.0, 1.0, 0.0, 0.0),
            [1.0u"m", 1.0u"m", 1.0u"m"]
        )

        # world_to_local point
        lp = Tambo.world_to_local(obb, Coordinate([6.0u"m", 0.0u"m", 0.0u"m"], cs))
        @test length(lp) == 3

        # world_to_local direction
        ld = Tambo.world_to_local(obb, dir_up)
        @test length(ld) == 3

        # Hit
        hit_ray = Ray(Coordinate([5.0u"m", 0.0u"m", -5.0u"m"], cs), Direction([0.0, 0.0, 1.0], cs))
        result = find_intersect(hit_ray, obb, 1)
        @test result isa TriangleIntersection

        # Miss
        miss_ray = Ray(Coordinate([50.0u"m", 0.0u"m", -5.0u"m"], cs), Direction([0.0, 0.0, 1.0], cs))
        result_miss = find_intersect(miss_ray, obb, 1)
        @test isnothing(result_miss)

        # Parallel (ray along x, OBB centered on x but far in z)
        par_ray = Ray(Coordinate([0.0u"m", 0.0u"m", 50.0u"m"], cs), Direction([1.0, 0.0, 0.0], cs))
        result_par = find_intersect(par_ray, obb, 1)
        @test isnothing(result_par)
    end

    # ---- Plane conversion ----
    @testset "Plane conversion" begin
        # Same CS - should return same plane
        p = Plane(c1, dir_up)
        p2 = convert(cs, p)
        @test p2.point === p.point

        # Different CS
        cs2 = CoordinateSystem((0.5, 0.5), 6371.0e3u"m")
        c_cs2 = Coordinate([0.0u"m", 0.0u"m", 0.0u"m"], cs2)
        d_cs2 = Direction([0.0, 0.0, 1.0], cs2)
        p3 = Plane(c_cs2, d_cs2)
        p4 = convert(cs, p3)
        @test CoordinateSystem(p4.point) == cs
    end

    # ---- Shapes ----
    @testset "Shapes - extra coverage" begin
        # Sphere coordinate_system
        @test CoordinateSystem(sphere) == cs
    end

    # ---- Simulation / relativize! ----
    @testset "Simulation and relativize!" begin
        # Simulation constructor
        cfg = Dict{String,Any}("geometry" => Dict("key" => "value"))
        sim = Simulation(cfg, Frame[])
        @test sim isa Simulation
        @test length(sim.results) == 0

        # Simulation requires geometry key
        @test_throws AssertionError Simulation(Dict{String,Any}("other" => 1), Frame[])

        # relativize!
        rd = Dict{String,Any}("path" => "_TAMBOSIM_PATH_/data", "nested" => Dict{String,Any}("p" => "_TAMBOSIM_PATH_/x"))
        Tambo.relativize!(rd)
        if haskey(ENV, "TAMBOSIM_PATH")
            @test !occursin("_TAMBOSIM_PATH_", rd["path"])
            @test !occursin("_TAMBOSIM_PATH_", rd["nested"]["p"])
        end
    end
end
