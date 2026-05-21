include("testsetup.jl")
"""
Tests for CORSIKA mesh-format event reading, coordinate transformations,
and the MultiParquetIterator.

Uses the example parquet file at test/resources/example_corsika.parquet.
"""

import TamboSim: CorsikaEvent, MultiParquetIterator, CoordinateSystem,
              particle_speed, particle_mass

using Parquet2
using Tables
using YAML

function run_read_corsika_tests()
    tambosim = get_tambosim_path()
    parquet_path = joinpath(tambosim, "test", "resources", "example_corsika.parquet")

    # Identity transform: target ECEF, no per-shower rotation, no offset.
    cs = ecefcoordinates
    dir_rot      = SMatrix{3,3,Float64,9}(I)
    coord_offset = SVector(0.0u"m", 0.0u"m", 0.0u"m")

    # ------------------------------------------------------------------
    @testset "Parquet schema" begin
        t = Parquet2.readfile(parquet_path)
        cols = Tables.columnnames(t)
        for expected in (:pdg, :kinetic_energy, :x, :y, :z, :nx, :ny, :nz, :time, :weight)
            @test expected in cols
        end
    end

    # ------------------------------------------------------------------
    @testset "CorsikaEvent construction from row" begin
        t = Parquet2.readfile(parquet_path)
        row = first(Tables.rows(t))

        evt = CorsikaEvent(row, cs, dir_rot, coord_offset)

        # Weight preserved
        @test evt.weight == row.weight

        # Energy preserved (converted to GeV)
        @test ustrip(u"GeV", evt.particle.energy) ≈ row.kinetic_energy

        # Direction is unit-normalized
        d = evt.particle.direction.point
        @test isapprox(norm(d), 1.0, atol=1e-6)

        # Position has units of meters
        @test unit(evt.particle.position.point[1]) == u"m"

        # Time is non-negative
        @test evt.particle.time >= 0.0u"s"
    end

    # ------------------------------------------------------------------
    @testset "CorsikaEvent direction preserves orientation" begin
        # With identity rotation the direction should match the input
        t = Parquet2.readfile(parquet_path)
        row = first(Tables.rows(t))

        evt = CorsikaEvent(row, cs, dir_rot, coord_offset)
        input_dir = normalize([row.nx, row.ny, row.nz])
        @test isapprox(evt.particle.direction.point, SVector{3}(input_dir), atol=1e-6)
    end

    # ------------------------------------------------------------------
    @testset "CorsikaEvent energy conservation" begin
        t = Parquet2.readfile(parquet_path)
        for (i, row) in enumerate(Tables.rows(t))
            i > 20 && break
            evt = CorsikaEvent(row, cs, dir_rot, coord_offset)
            @test ustrip(u"GeV", evt.particle.energy) ≈ row.kinetic_energy
            @test evt.particle.energy >= 0.0u"GeV"
        end
    end

    # ------------------------------------------------------------------
    @testset "CorsikaEvent particle speed" begin
        t = Parquet2.readfile(parquet_path)
        for (i, row) in enumerate(Tables.rows(t))
            i > 20 && break
            evt = CorsikaEvent(row, cs, dir_rot, coord_offset)
            @test evt.particle.speed > 0.0u"m/s"
            @test evt.particle.speed <= 299_792_458.0u"m/s" + 1.0u"m/s"
        end
    end

    # ------------------------------------------------------------------
    @testset "MultiParquetIterator basics" begin
        transform(row) = CorsikaEvent(row, cs, dir_rot, coord_offset)
        iter = MultiParquetIterator([parquet_path], transform; chunk_size=100, T=CorsikaEvent)

        first_evt = nothing
        count = 0
        for evt in iter
            if count == 0
                first_evt = evt
            end
            count += 1
        end

        @test count == 10273
        @test first_evt isa CorsikaEvent
        @test first_evt.particle.energy >= 0.0u"GeV"
    end

    # ------------------------------------------------------------------
    @testset "MultiParquetIterator multiple files" begin
        transform(row) = CorsikaEvent(row, cs, dir_rot, coord_offset)
        iter = MultiParquetIterator(
            [parquet_path, parquet_path], transform;
            chunk_size=5000, T=CorsikaEvent
        )

        count = 0
        for _ in iter
            count += 1
        end
        @test count == 2 * 10273
    end

    # ------------------------------------------------------------------
    @testset "MultiParquetIterator small chunk size" begin
        transform(row) = CorsikaEvent(row, cs, dir_rot, coord_offset)
        iter = MultiParquetIterator([parquet_path], transform; chunk_size=1, T=CorsikaEvent)

        count = 0
        for _ in iter
            count += 1
            count >= 10 && break
        end
        @test count == 10
    end

    # ------------------------------------------------------------------
    @testset "Coordinate system conversion round-trip" begin
        cs2 = CoordinateSystem(
            SVector(100.0u"m", 200.0u"m", 300.0u"m"),
            SMatrix{3,3,Float64,9}([
                0.0  1.0  0.0;
               -1.0  0.0  0.0;
                0.0  0.0  1.0
            ])
        )

        p = Coordinate([1000.0u"m", 2000.0u"m", 3000.0u"m"], cs)
        p2 = convert(cs2, p)
        p_back = convert(cs, p2)

        @test isapprox(ustrip.(p.point), ustrip.(p_back.point), atol=1e-6)
    end

    # ------------------------------------------------------------------
    @testset "read_corsika_mesh directory structure" begin
        # Build a minimal event-level dir with one completed shower in the
        # mesh-format layout that read_corsika_mesh expects.
        mktempdir() do tmpdir
            shower_dir   = joinpath(tmpdir, "shower_0")
            particle_dir = joinpath(shower_dir, "particles")
            mkpath(particle_dir)

            cp(parquet_path, joinpath(particle_dir, "particles.parquet"))

            # summary.yaml lives inside particles/ — read_corsika_mesh's
            # globbed path retains its trailing slash, so dirname strips
            # only the slash, leaving the lookup inside particles/.
            open(joinpath(particle_dir, "summary.yaml"), "w") do io
                write(io, "status: completed\n")
            end

            # config.yaml carries the mesh bounding box (min/max in ECEF metres).
            config = Dict(
                "mesh" => Dict(
                    "bounds" => Dict(
                        "min" => [0.0, 0.0, 0.0],
                        "max" => [0.0, 0.0, 0.0],
                    )
                )
            )
            open(joinpath(particle_dir, "config.yaml"), "w") do io
                YAML.write(io, config)
            end

            events = TamboSim.read_corsika_mesh(tmpdir, cs)
            count = 0
            for evt in events
                count += 1
                @test evt isa CorsikaEvent
                count >= 5 && break
            end
            @test count == 5
        end
    end

    # ------------------------------------------------------------------
    @testset "read_corsika_mesh skips incomplete showers" begin
        mktempdir() do tmpdir
            # Shower without summary.yaml at shower-dir level — incomplete.
            shower_dir   = joinpath(tmpdir, "shower_0")
            particle_dir = joinpath(shower_dir, "particles")
            mkpath(particle_dir)
            cp(parquet_path, joinpath(particle_dir, "particles.parquet"))

            open(joinpath(particle_dir, "config.yaml"), "w") do io
                YAML.write(io, Dict("mesh" => Dict("bounds" => Dict(
                    "min" => [0.0, 0.0, 0.0], "max" => [0.0, 0.0, 0.0]))))
            end

            @test_throws ArgumentError TamboSim.read_corsika_mesh(tmpdir, cs)
        end
    end

    # ------------------------------------------------------------------
    @testset "particle_speed relativistic consistency" begin
        # High-energy tau: speed should approach c
        ke_high = 1e6u"GeV"
        v_high = particle_speed(ke_high, TauMinus)
        c = 299_792_458.0u"m/s"
        @test v_high < c
        @test v_high > 0.999 * c

        # Low-energy tau: speed should be noticeably less than c
        mass_tau = particle_mass(TauMinus)
        rest_energy = uconvert(u"GeV", mass_tau * speedoflight^2)
        ke_low = rest_energy * 0.01
        v_low = particle_speed(ke_low, TauMinus)
        @test v_low < 0.15 * c
        @test v_low > 0.0u"m/s"

        # Photon: mass is zero, speed should be c
        v_photon = particle_speed(1.0u"GeV", Gamma)
        @test isapprox(ustrip(u"m/s", v_photon), ustrip(u"m/s", c), rtol=1e-10)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    @testset "CORSIKA Read Mesh" begin
        run_read_corsika_tests()
    end
end
