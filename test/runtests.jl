using Test
using Unitful
using LinearAlgebra
using StaticArrays
using Rotations
using Distributions
using StatsBase

# Define unit dimension aliases that are used throughout the codebase
const ldim = Unitful.𝐋
const tdim = Unitful.𝐓
const edim = Unitful.𝐋^2 * Unitful.𝐌 * Unitful.𝐓^-2
const mdim = Unitful.𝐌
const speedoflight = 299_792_458.0u"m/s"

# Include test files
include("test_geometry.jl")
include("test_ray_tracing.jl")
include("test_samplers.jl")
include("test_particles.jl")
include("test_frames.jl")
include("test_bvh.jl")
include("test_weighting.jl")

@testset "Tambo.jl" begin
    @testset "Geometry" begin
        run_geometry_tests()
    end

    @testset "Ray Tracing" begin
        run_ray_tracing_tests()
    end

    @testset "Samplers" begin
        run_sampler_tests()
    end

    @testset "Particles" begin
        run_particle_tests()
    end

    @testset "Frames" begin
        run_frame_tests()
    end

    @testset "BVH" begin
        run_bvh_tests()
    end

    @testset "Weighting" begin
        run_weighting_tests()
    end
end
