if !@isdefined(__TAMBOSIM_TEST_SETUP_LOADED__)
    const __TAMBOSIM_TEST_SETUP_LOADED__ = true
using Test
using Unitful
using LinearAlgebra
using StaticArrays
using Rotations
using Distributions
using StatsBase
using Random
using ProgressMeter

# Import the TamboSim module to test actual source code
using TamboSim

# Import internal types and functions not exported by default
import TamboSim: CoordinateSystem, ecefcoordinates, Coordinate, Direction,
              Triangle, Sphere, Plane, OBB, Ray,
              AABB, BVHNode, BVHTree,
              normal, area, centroid, longlat_to_cart, cart_to_longlat, sph_to_cart, cart_to_sph,
              find_intersect, find_intersection, intersect_all,
              UnitfulPowerLawSampler, UniformAngularSampler, pl_norm, probability,
              Frame,
              Particle, FitStatus, ParticleShape,
              reverse,
              # Particle types
              TauMinus, TauPlus, NuTau, NuTauBar, Gamma,
              # Julia interfaces types
              Intersection, SphereIntersection, TriangleIntersection,
              StochasticLoss,
              # Julia interfaces functions
              cull_intersections, should_go_through_earth, is_proposal_available,
              # Additional imports for coverage tests
              compute_rotation, validate_triangle,
              particle_mass, particle_speed, lorentz_gamma, particle_vacuum_range,
              find_trim_idxs

# Define unit dimension aliases that are used throughout the codebase
const ldim = Unitful.𝐋
const tdim = Unitful.𝐓
const edim = Unitful.𝐋^2 * Unitful.𝐌 * Unitful.𝐓^-2
const mdim = Unitful.𝐌
const speedoflight = 299_792_458.0u"m/s"
end
