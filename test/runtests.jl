using Test
using Unitful
using LinearAlgebra
using StaticArrays
using Rotations
using Distributions
using StatsBase
using Random
using ProgressMeter

# Import the Tambo module to test actual source code
using Tambo

# Import internal types and functions not exported by default
import Tambo: CoordinateSystem, ecefcoordinates, Coordinate, Direction,
              Triangle, Sphere, Plane, OBB, Ray,
              AABB, BVHNode, BVHTree,
              normal, area, centroid, longlat_to_cart, cart_to_longlat, sph_to_cart, cart_to_sph,
              find_intersect, find_intersection, intersect_all,
              UnitfulPowerLawSampler, UniformAngularSampler, pl_norm, probability,
              Frame, cut_frames!,
              Particle, FitStatus, ParticleShape,
              WeightParameters,
              reverse,
              # Particle types
              TauMinus, TauPlus, NuTau, NuTauBar,
              # Julia interfaces types
              Intersection, SphereIntersection, TriangleIntersection,
              StochasticLoss,
              # Julia interfaces functions
              cull_intersections, should_go_through_earth, is_proposal_available,
              # Additional imports for coverage tests
              compute_rotation, validate_triangle,
              particle_mass, particle_speed, lorentz_gamma, particle_vacuum_range

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
include("test_julia_interfaces.jl")
include("test_regression.jl")
include("test_coverage_extras.jl")
include("test_injection_regression.jl")

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

    @testset "Julia Interfaces" begin
        run_julia_interfaces_tests()
    end

    @testset "Regression" begin
        run_regression_tests()
    end

    @testset "Coverage Extras" begin
        run_coverage_extras_tests()
    end

    @testset "Injection Regression" begin
        run_injection_regression_tests()
    end
end
