# Unit tests for the pure-math functions in radio_fluence.jl.
#
# These use synthetic data only -- no CORSIKA output and no plotting backend --
# so they run with the Julia stdlib alone:
#
#   julia src/corsika/tambo_shower/analysis/test_radio_fluence.jl

using Test
using LinearAlgebra

include(joinpath(@__DIR__, "radio_fluence.jl"))

@testset "energy_fluence" begin
    # Constant unit field over a uniform 0..100 ns grid; compare to the
    # closed form computed via an independent path. The ns->s conversion is
    # load-bearing: a missing 1e-9 would make dt=1.0 and blow the result up by
    # 1e9, so we also assert dt directly.
    t = collect(range(0.0, 100.0, length = 1001))          # ns
    ex = ones(length(t)); ey = zeros(length(t)); ez = zeros(length(t))

    ts = t .* NS_TO_S
    dt = ts[2] - ts[1]
    @test dt ≈ 1e-10 rtol = 1e-9                            # 0.1 ns spacing in s
    expected = EPS0 * C * sum(ex .^ 2) * dt / EV
    @test energy_fluence(t, ex, ey, ez) ≈ expected rtol = 1e-9
    @test energy_fluence(t, ex, ey, ez) > 0

    # Zero field -> zero fluence.
    z = zeros(length(t))
    @test energy_fluence(t, z, z, z) == 0.0
end

@testset "project_to_shower_plane" begin
    # v = +z, B = +y  =>  v×B = (-1,0,0) = ê1,  v×(v×B) = (0,-1,0) = ê2.
    v = [0.0, 0.0, 1.0]
    B = [0.0, 1.0, 0.0]
    positions = [1.0 0.0 0.0;   # +x  -> a=-1, b=0
                 0.0 1.0 0.0;   # +y  -> a=0,  b=-1
                 0.0 0.0 0.0]   # core-> a=0,  b=0
    core = [0.0, 0.0, 0.0]

    a, b = project_to_shower_plane(positions, core, v, B)
    @test a[1] ≈ -1.0 atol = 1e-12
    @test b[1] ≈ 0.0  atol = 1e-12
    @test a[2] ≈ 0.0  atol = 1e-12
    @test b[2] ≈ -1.0 atol = 1e-12
    @test a[3] ≈ 0.0  atol = 1e-12   # core maps to origin
    @test b[3] ≈ 0.0  atol = 1e-12

    # A non-origin core shifts the projection.
    core2 = [1.0, 0.0, 0.0]
    a2, b2 = project_to_shower_plane(positions, core2, v, B)
    @test a2[3] ≈ 1.0 atol = 1e-12   # origin point now at (0,0,0)-core2 -> a=+1
end
