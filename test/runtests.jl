using Test
using Unitful
using LinearAlgebra
using StaticArrays
using Rotations
using Distributions
using StatsBase

# Import the Tambo module to test actual source code
using Tambo

# Import internal types and functions not exported by default
import Tambo: CoordinateSystem, ecefcoordinates, Coordinate, Direction,
              Triangle, Sphere, Plane, OBB, Ray,
              AABB, BVHNode, BVHTree,
              normal, area, centroid, longlat_to_cart, cart_to_longlat, sph_to_cart, cart_to_sph,
              find_intersect, find_intersection, intersect_all,
              UnitfulPowerLawSampler, UniformAngularSampler,
              Frame, cut_frames!,
              Particle, FitStatus, ParticleShape,
              WeightParameters,
              reverse

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
include("test_detector_culling.jl")

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

    @testset "Detector Culling" begin
        run_detector_culling_tests()
    end
end
