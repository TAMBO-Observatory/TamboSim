/*
 * TAMBO cosmic-ray air-shower simulation using CORSIKA 8.
 *
 * Simulates showers observed at the TAMBO detector site in the Colca
 * Valley, Peru. Two triangular meshes in ECEF coordinates drive the geometry:
 *
 *   obs_surface.ply  -  valley floor observation surface
 *   terrain.ply      -  surrounding terrain rock volume (optional)
 *
 * The shower trajectory is specified in one of two mutually exclusive modes:
 *
 *   ECEF mode: two ECEF points passed on the command line -- the injection
 *     point (--inject-x/y/z, upstream, ~112 km altitude) and the intercept on
 *     the detection region (--intercept-x/y/z).  In normal use these are
 *     computed by the Julia corsika_run! orchestrator (src/corsika/run_corsika.jl),
 *     which traces the particle trajectory to the detector mesh and emits the
 *     argv for this binary.
 *
 *   Gun mode: a direction (--zenith/--azimuth, ENU at the core) plus a
 *     back-projection distance (--inject-distance, km).  The core defaults to
 *     the obs-mesh centroid but can be overridden with --core-x/y/z.
 *
 * Usage is modelled after c8_air_shower.cpp from the CORSIKA 8 repository.
 */

/* clang-format off */
// InteractionCounter uses boost/histogram which must be included before
// boost/type_traits.
#include <corsika/framework/process/InteractionCounter.hpp>
/* clang-format on */

#include <corsika/framework/core/Cascade.hpp>
#include <corsika/framework/core/EnergyMomentumOperations.hpp>
#include <corsika/framework/core/Logging.hpp>
#include <corsika/framework/core/PhysicalUnits.hpp>
#include <corsika/framework/geometry/PhysicalGeometry.hpp>
#include <corsika/framework/geometry/RootCoordinateSystem.hpp>
#include <corsika/framework/geometry/Sphere.hpp>
#include <corsika/framework/geometry/TriangularMesh.hpp>
#include <corsika/framework/process/BoundaryCrossingProcess.hpp>
#include <corsika/framework/process/ContinuousProcess.hpp>
#include <corsika/framework/process/DynamicInteractionProcess.hpp>
#include <corsika/framework/process/SecondariesProcess.hpp>
#include <corsika/framework/process/ProcessSequence.hpp>
#include <corsika/framework/process/SwitchProcessSequence.hpp>
#include <corsika/framework/random/RNGManager.hpp>
#include <corsika/framework/random/PowerLawDistribution.hpp>
#include <corsika/framework/utility/CorsikaFenv.hpp>

#include <corsika/modules/writers/EnergyLossWriter.hpp>
#include <corsika/modules/writers/InteractionWriter.hpp>
#include <corsika/modules/writers/LongitudinalWriter.hpp>
#include <corsika/modules/writers/ProductionWriter.hpp>
#include <corsika/modules/writers/PrimaryWriter.hpp>
#include <corsika/modules/writers/SubWriter.hpp>
#include <corsika/modules/writers/ParticleWriterParquet.hpp>
// #include <corsika/modules/TrackWriter.hpp>
#include <corsika/output/OutputManager.hpp>

#include <corsika/media/CORSIKA7Atmospheres.hpp>
#include <corsika/media/Environment.hpp>
#include <corsika/media/magnetic/GeomagneticModel.hpp>
#include <corsika/media/refractivity/GladstoneDaleRefractiveIndex.hpp>
#include <corsika/media/density_and_composition/HomogeneousMedium.hpp>
#include <corsika/media/interfaces/IMagneticFieldModel.hpp>
#include <corsika/media/LayeredSphericalAtmosphereBuilder.hpp>
#include <corsika/media/medium/MediumPropertyModel.hpp>
#include <corsika/media/composition/NuclearComposition.hpp>
#include <corsika/media/ShowerAxis.hpp>
#include <corsika/media/magnetic/UniformMagneticField.hpp>

#include <corsika/modules/BetheBlochPDG.hpp>
#include <corsika/modules/Epos.hpp>
#include <corsika/modules/EposLhcr.hpp>
#include <corsika/modules/ObservationMesh.hpp>
#include <corsika/modules/PROPOSAL.hpp>
#include <corsika/modules/ParticleCut.hpp>
#include <corsika/modules/Pythia8.hpp>
#include <corsika/modules/QGSJetII.hpp>
#include <corsika/modules/QGSJetIII.hpp>
#include <corsika/modules/Sibyll.hpp>
#include <corsika/modules/Sophia.hpp>
#include <corsika/modules/StackInspector.hpp>
#include <corsika/modules/thinning/EMThinning.hpp>
#include <corsika/modules/LongitudinalProfile.hpp>
#include <corsika/modules/ProductionProfile.hpp>

#ifdef WITH_FLUKA
#include <corsika/modules/FLUKA.hpp>
#else
#include <corsika/modules/UrQMD.hpp>
#endif

#include <corsika/setup/SetupStack.hpp>
#include <corsika/setup/SetupTrajectory.hpp>
#include <corsika/setup/SetupC7trackedParticles.hpp>

#include <boost/filesystem.hpp>

#include <CLI/App.hpp>
#include <CLI/Config.hpp>
#include <CLI/Formatter.hpp>

#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <limits>
#include <type_traits>
#include <string>

using namespace corsika;
using namespace std;

using EnvironmentInterface = media::IRefractiveIndexModel<
    media::IMediumPropertyModel<media::IMagneticFieldModel<media::IMediumModel>>>;
using EnvType = media::Environment<EnvironmentInterface>;
using StackType = setup::Stack<EnvType>;
using TrackingType = setup::Tracking;
using Particle = StackType::particle_type;

// When a particle exits the terrain-rock volume, the tracker sets its logical
// node to rock.getParent() (the topmost spanned atmosphere layer), which is
// not necessarily the layer that geometrically contains the exit point.  This
// BoundaryCrossingProcess re-resolves the logical node to the correct
// atmosphere layer on rock exit, so the very next step uses the correct
// medium.  Inert on every other boundary crossing (one pointer compare); the
// resolution runs only when leaving rock.
//
// It resolves among LAYERS, not via the full getContainingNode.  The relocator
// only ever runs with the particle sitting exactly on the rock surface (the
// tracker leaves it at the crossing point, not nudged outside).  There,
// getContainingNode is the wrong tool: it consults the rock via excludes(),
// and TriangularMesh::contains() at an on-surface point is degenerate (it
// drops the local face via the 1um boundary padding and votes by parity of
// the remaining crossings -- for non-convex terrain it can vote "inside"), so
// it could resolve back to the very rock the particle is leaving and
// ping-pong the boundary with near-zero progress.  The question we actually
// need answered is "which atmosphere LAYER contains this point?", which is a
// pure Sphere::contains (altitude vs the layer boundary) -- robust exactly on
// the rock surface and structurally unable to return the rock.  The
// atmosphere is a single-child nested-ball chain; the rock mesh is only ever
// a non-index-0 child of its owning layer, so descending the index-0 child
// chain while each layer's volume contains the point yields the innermost
// containing layer (L1 below the inner boundary, L2 above, ...) without ever
// reaching the rock.  node.getVolume().contains() is the same primitive
// Intersect.inl and getContainingNode use.
struct RockExitRelocator : public BoundaryCrossingProcess<RockExitRelocator> {
  EnvType& env_;
  void const* rockNode_; // stable address of the terrain-rock node, or nullptr
  RockExitRelocator(EnvType& env, void const* rockNode)
      : env_(env), rockNode_(rockNode) {}
  template <typename TParticle>
  ProcessReturn doBoundaryCrossing(TParticle& particle,
                                   typename TParticle::node_type const& from,
                                   typename TParticle::node_type const& /*to*/) {
    if (rockNode_ == nullptr || static_cast<void const*>(&from) != rockNode_)
      return ProcessReturn::Ok;
    auto const pos = particle.getPosition();
    auto const& uk = env_.getUniverse()->getChildNodes();
    auto* L = uk.empty() ? nullptr : uk[0].get();
    decltype(L) layer = nullptr;
    while (L != nullptr && L->getVolume().contains(pos)) {
      layer = L; // innermost layer so far whose sphere contains the exit point
      auto const& k = L->getChildNodes();
      L = k.empty() ? nullptr : k[0].get(); // index-0 child is the next layer
    }
    if (layer != nullptr) particle.setNode(layer);
    // Nudge the particle off the rock surface into air.  setNode alone is
    // insufficient: the cascade re-derives the next step from getPosition(),
    // and the tracker leaves a rock-exiting particle numerically pinned onto
    // the exit triangle.  The pin is intrinsic floating-point cancellation,
    // not a bug we can localise: the endpoint is computed as
    // start + velocity*t_mollertrumbore in the ECEF frame at radius ~6.4e6 m,
    // so the residual off the face is O(eps_mach * 1e6 m) ~ 1 nm -- far below
    // the 1 um TriangularMesh boundaryPadding that both contains() and the
    // straight-line ray intersect filter with a strict '>'.  A sub-padding
    // self-hit is therefore discarded and the next "real" exit collapses to
    // the far mountain face km away, unreachable in interaction-limited cm
    // steps: the particle freezes, bleeding StandardRock dE/dx in air.
    //
    // Displace it so it is a defined CLEARANCE off the exit face's plane,
    // measured along the surface normal -- the maximal-clearance direction,
    // independent of incidence angle (a fixed step along the momentum
    // direction clears only clearance*|cos(incidence)| perpendicular, which
    // is why a plain along-momentum nudge is not robust).  We keep the
    // particle on its own trajectory (move along +direction, the exit
    // direction by construction at a from==rock crossing) but rescale the
    // along-track distance by 1/|dir.n| so the perpendicular component off
    // the face equals kClearance.  |dir.n| (absolute value) makes this
    // independent of the triangle's winding-defined normal sign -- CORSIKA
    // does not canonicalise mesh normals outward, so n's sign is unreliable,
    // but moving forward along +direction by a positive distance is always
    // the physically correct exit move regardless of n's sign.  Cascade::step
    // dispatches boundary-crossing processes last, immediately before it
    // returns; there is no pre-computed next trajectory, so the mutated
    // position is read fresh on the very next step.
    constexpr double kClearance = 2.0e-6;  // m, perpendicular target (2x padding)
    constexpr double kMaxAlong = 1.0e-3;   // m, cap on along-track displacement
    double along = kClearance;             // fallback: plain 2 um along direction
    auto const* mesh = dynamic_cast<TriangularMesh const*>(&from.getVolume());
    if (mesh != nullptr) {
      auto const hits = mesh->intersectRayAll(pos, particle.getDirection());
      if (!hits.empty()) { // sorted by distance: front() is the pin face
        double const cosI =
            std::abs(particle.getDirection().dot(hits.front().normal).magnitude());
        along = (cosI > 1e-12) ? (kClearance / cosI) : kMaxAlong;
        if (along > kMaxAlong) {
          CORSIKA_LOG_WARN(
              "RockExitRelocator: near-tangent rock exit (|dir.n|={}), "
              "along-track nudge clamped to {} m (pid={} E={} GeV)",
              cosI, kMaxAlong, particle.getPID(), particle.getEnergy() / 1_GeV);
          along = kMaxAlong;
        }
      }
    }
    particle.setPosition(pos + along * 1_m * particle.getDirection());
    return ProcessReturn::Ok;
  }
};

// Keeps the in-rock EM cascade tractable.  A multi-TeV muon's brems/pair
// losses in 2.65 g/cm3 rock would seed an EM shower CORSIKA tracks down to
// emcut (~1 MeV) -- ~1e6-1e8 secondaries, each stepped against the 180k-
// triangle terrain mesh: intractable on the production budget, and
// physically invisible (an e+-/gamma born in rock cannot escape km of rock
// to be observed).  This process discards e+-/gamma whose logical node is
// the rock, keeping mu/tau/hadrons/nu -- those CAN escape and seed the
// observable air shower.  The muon's energy degradation is unaffected:
// PROPOSAL removes E_loss from the muon at the vertex and applies
// continuous dE/dx regardless of whether the EM child is tracked.
//
//  - doSecondaries erases e+-/gamma at birth when the producing
//    interaction happened in rock.  Secondaries inherit the projectile's
//    node at creation (GeometryNodeStackExtension: "copy Node from parent
//    particle!"), so an in-rock interaction's EM children carry
//    node == rock immediately.  Zero-cost removal of the rock-born
//    exponential source.
//  - doContinuous absorbs any e+-/gamma whose CURRENT logical node is rock,
//    on its first step -- the comprehensive backstop that also catches EM
//    produced in air that later travels into the rock.
//
// Approximation: e+-/gamma produced within ~an EM range of the rock surface
// could in principle exit into air; we discard them too.  Negligible: EM
// range in rock ~cm-m vs traversal hundreds m-km, and a sub-GeV EM particle
// exiting rock is negligible vs the muon/hadrons for a TAMBO air-shower
// observable.  No-op when the terrain mesh is disabled (rockNode_ == null).
struct RockEMAbsorber : public SecondariesProcess<RockEMAbsorber>,
                        public ContinuousProcess<RockEMAbsorber> {
  void const* rockNode_; // stable address of the terrain-rock node, or nullptr
  explicit RockEMAbsorber(void const* rockNode) : rockNode_(rockNode) {}

  static bool isEM(Code pid) {
    return pid == Code::Electron || pid == Code::Positron || pid == Code::Photon;
  }

  template <typename TStackView>
  void doSecondaries(TStackView& vS) {
    if (rockNode_ == nullptr) return;
    auto p = vS.begin();
    while (p != vS.end()) {
      if (isEM(p.getPID()) &&
          static_cast<void const*>(p.getNode()) == rockNode_) {
        p.erase();
      }
      ++p; // erase()+(++) is the SecondaryView idiom (cf. ParticleCut)
    }
  }

  template <typename TParticle>
  ProcessReturn doContinuous(Step<TParticle>& step, bool const) {
    if (rockNode_ != nullptr && isEM(step.getParticlePre().getPID()) &&
        static_cast<void const*>(step.getParticlePre().getNode()) == rockNode_) {
      return ProcessReturn::ParticleAbsorbed;
    }
    return ProcessReturn::Ok;
  }

  template <typename TParticle, typename TTrajectory>
  LengthType getMaxStepLength(TParticle const&, TTrajectory const&) {
    return std::numeric_limits<double>::infinity() * 1_m; // never limit steps
  }
};

// Production safety net for the rock/air interface.  RockExitRelocator's
// position nudge resolves the known way a particle can end up logically
// resident in the terrain rock while geometrically outside it (a degenerate
// on-surface re-resolution after a rock-exit boundary crossing).  This process
// is deliberately pathway-agnostic: rather than handle a specific entry route,
// it watches for the *invariant violation itself* -- logical node == rock yet
// rock.contains(position) == false -- which is the signature underlying a
// particle that bleeds StandardRock dE/dx while geometrically in air and
// silently ranges out before reaching any readout.  A healthy rock traversal
// has logical == rock AND contains() == true and resets the counter every
// step; the pathology accumulates logical == rock AND !contains() for tens of
// thousands of consecutive steps.  On crossing a generous persistence
// threshold the run is aborted with diagnostics rather than allowed to emit a
// complete-looking shower output in which an Earth-skimming signal particle
// was quietly lost.  The counter is a deliberately coarse run-global burst
// detector, not a per-particle accountant: a stuck particle steps thousands
// of times with no interleaving secondary, so a global count is a sufficient
// and cheap tripwire.  No-op when the terrain mesh is disabled
// (rockNode_ == nullptr); one pointer compare per step otherwise, with the
// contains() test reached only while a particle is logically in the rock.
struct RockInterfaceTripwire : public ContinuousProcess<RockInterfaceTripwire> {
  void const* rockNode_;
  explicit RockInterfaceTripwire(void const* rockNode) : rockNode_(rockNode) {}
  template <typename TParticle>
  ProcessReturn doContinuous(Step<TParticle>& step, bool const) {
    if (rockNode_ == nullptr) return ProcessReturn::Ok;
    auto const& pre = step.getParticlePre();
    auto const* nd = pre.getNode();
    if (static_cast<void const*>(nd) != rockNode_) return ProcessReturn::Ok;
    using NodeT = std::remove_reference_t<decltype(*nd)>;
    bool const inside = static_cast<NodeT const*>(rockNode_)
                            ->getVolume()
                            .contains(pre.getPosition());
    static long stuck = 0;
    if (inside) {
      stuck = 0;
      return ProcessReturn::Ok;
    }
    constexpr long kStuckLimit = 1000; // a real loop racks up tens of thousands
    if (++stuck >= kStuckLimit) {
      auto const c =
          pre.getPosition().getCoordinates(get_root_CoordinateSystem());
      CORSIKA_LOG_ERROR(
          "Rock/air interface stuck state: a particle has been logically "
          "resident in the terrain rock while geometrically OUTSIDE it for {} "
          "consecutive steps -- it is bleeding StandardRock dE/dx in air and "
          "will silently range out before reaching any readout.  Reached via "
          "a path RockExitRelocator's nudge does not cover.  pid={} "
          "E={} GeV pos=({:.1f},{:.1f},{:.1f}) m.  Aborting rather than emit "
          "a misleading shower output.",
          stuck, pre.getPID(), pre.getEnergy() / 1_GeV, c.getX() / 1_m,
          c.getY() / 1_m, c.getZ() / 1_m);
      std::exit(EXIT_FAILURE);
    }
    return ProcessReturn::Ok;
  }
  template <typename TParticle, typename TTrajectory>
  LengthType getMaxStepLength(TParticle const&, TTrajectory const&) {
    return std::numeric_limits<double>::infinity() * 1_m;
  }
};

// ---------------------------------------------------------------------------
// Random stream registration
// ---------------------------------------------------------------------------
long registerRandomStreams(long seed) {
  RNGManager<>::getInstance().registerRandomStream("cascade");
  RNGManager<>::getInstance().registerRandomStream("qgsjet");
  RNGManager<>::getInstance().registerRandomStream("qgsjetIII");
  RNGManager<>::getInstance().registerRandomStream("sibyll");
  RNGManager<>::getInstance().registerRandomStream("sophia");
  RNGManager<>::getInstance().registerRandomStream("epos");
  RNGManager<>::getInstance().registerRandomStream("epos-lhcr");
  RNGManager<>::getInstance().registerRandomStream("pythia");
  RNGManager<>::getInstance().registerRandomStream("urqmd");
  RNGManager<>::getInstance().registerRandomStream("fluka");
  RNGManager<>::getInstance().registerRandomStream("proposal");
  RNGManager<>::getInstance().registerRandomStream("thinning");
  RNGManager<>::getInstance().registerRandomStream("primary_particle");
  if (seed == 0) {
    std::random_device rd;
    seed = rd();
    CORSIKA_LOG_INFO("random seed (auto) {}", seed);
  } else {
    CORSIKA_LOG_INFO("random seed {}", seed);
  }
  RNGManager<>::getInstance().setSeed(seed);
  return seed;
}

template <typename T>
using MyExtraEnv = media::GladstoneDaleRefractiveIndex<
    media::MediumPropertyModel<media::UniformMagneticField<T>>>;

// ---------------------------------------------------------------------------
// Custom 5-layer atmosphere for the Colca Valley (TAMBO site).
// Layer parameters fitted to local radiosonde / reanalysis data.
// ---------------------------------------------------------------------------
template <typename TEnvironmentInterface, template <typename> typename TExtraEnv,
          typename TEnvironment, typename... TArgs>
void create_5layer_colca_atmosphere(TEnvironment& env,
                                    Point const& center, TArgs... args) {
  auto builder = media::make_layered_spherical_atmosphere_builder<
      TEnvironmentInterface, TExtraEnv>::create(center, constants::EarthRadius::Mean,
                                                std::forward<TArgs>(args)...);

  builder.setNuclearComposition(media::standardAirComposition);

  using media::AtmosphereLayerParameters;
  // Field order is positional: AtmosphereLayerParameters is declared
  // { LengthType altitude; GrammageType offset; LengthType scaleHeight; }
  // (CORSIKA7Atmospheres.hpp:66-70).  addExponentialLayer/addLinearLayer
  // take (offset b, scaleHeight, altitude upperBoundary) -- see the
  // params[i].offset/.scaleHeight/.altitude call order below.
  constexpr std::array<AtmosphereLayerParameters, 5> params{{
      {3.8_km,   1208.0663_g / (1_cm * 1_cm), 1045629.03_cm},
      {9.7_km,   1148.2458_g / (1_cm * 1_cm),  963788.26_cm},
      {26.5_km,  1182.7783_g / (1_cm * 1_cm),  770343.77_cm},
      {100_km,   1510.0311_g / (1_cm * 1_cm),  701471.17_cm},
      {5000_km,  1_g / (1_cm * 1_cm),          1e9_cm},
  }};

  for (int i = 0; i < 4; ++i) {
    builder.addExponentialLayer(params[i].offset, params[i].scaleHeight,
                                params[i].altitude);
  }
  builder.addLinearLayer(params[4].offset, params[4].scaleHeight, params[4].altitude);

  builder.assemble(env);
}

// ---------------------------------------------------------------------------
// Derive local ENU basis vectors from an ECEF point (metres).
// east, north, up are unit vectors in the ECEF frame.
// ---------------------------------------------------------------------------
static void ecefToENU(double cx, double cy, double cz, std::array<double, 3>& east,
                      std::array<double, 3>& north, std::array<double, 3>& up) {
  double const r = std::sqrt(cx * cx + cy * cy + cz * cz);
  double const rxy = std::sqrt(cx * cx + cy * cy);

  up = {cx / r, cy / r, cz / r};

  if (rxy > 0.0) {
    east = {-cy / rxy, cx / rxy, 0.0};
  } else {
    east = {1.0, 0.0, 0.0}; // fallback at poles
  }

  // north = up x east  (right-handed ENU basis)
  north = {up[1] * east[2] - up[2] * east[1],
          up[2] * east[0] - up[0] * east[2],
          up[0] * east[1] - up[1] * east[0]};

  double const nm =
      std::sqrt(north[0] * north[0] + north[1] * north[1] + north[2] * north[2]);
  north[0] /= nm;
  north[1] /= nm;
  north[2] /= nm;
}

// ---------------------------------------------------------------------------
// Mesh loading
//
// Loads the observation mesh and (optionally) the terrain mesh from their PLY
// files (ECEF metres, scale 1 m, 1 um boundary padding).  When a terrain mesh
// is present, checks that every obs-mesh vertex has a matching terrain vertex
// within 1 mm (same-geometry sanity check; warns but does not fail).
// ---------------------------------------------------------------------------
struct LoadedMeshes {
  TriangularMesh obsMesh;
  std::unique_ptr<TriangularMesh> terrainMesh; // nullptr when terrain disabled
  bool useTerrainMesh;
};

static LoadedMeshes loadMeshes(std::string const& obsMeshPath,
                               std::string const& terrainMeshPath,
                               CoordinateSystemPtr const& rootCS) {
  CORSIKA_LOG_INFO("Loading observation mesh: {}", obsMeshPath);
  // PLY coordinates are ECEF metres; load directly into rootCS with scale=1_m
  TriangularMesh obsMesh = TriangularMesh::fromPLY(obsMeshPath, rootCS, 1_m, 1e-6_m);
  CORSIKA_LOG_INFO("Observation mesh: {} vertices, {} triangles",
                   obsMesh.getVertexCount(), obsMesh.getTriangleCount());

  bool const useTerrainMesh =
      !terrainMeshPath.empty() && boost::filesystem::exists(terrainMeshPath);
  std::unique_ptr<TriangularMesh> terrainMeshPtr;
  if (useTerrainMesh) {
    CORSIKA_LOG_INFO("Loading terrain mesh: {}", terrainMeshPath);
    terrainMeshPtr =
        std::make_unique<TriangularMesh>(TriangularMesh::fromPLY(terrainMeshPath, rootCS,
                                                                 1_m, 1e-6_m));
    CORSIKA_LOG_INFO("Terrain mesh: {} vertices, {} triangles",
                     terrainMeshPtr->getVertexCount(),
                     terrainMeshPtr->getTriangleCount());
  } else if (!terrainMeshPath.empty()) {
    CORSIKA_LOG_WARN("Terrain mesh not found: {} -- terrain rock volume disabled",
                     terrainMeshPath);
  }

  if (useTerrainMesh) {
    // Check that every obs-mesh vertex has a matching vertex in the terrain mesh
    // within 1 mm. This confirms the two files were generated from the same geometry.
    constexpr double kTolM = 1e-3;
    size_t nMismatched = 0;
    double maxMinDist = 0.0;
    for (size_t oi = 0; oi < obsMesh.getVertexCount(); ++oi) {
      auto const oc = obsMesh.getVertex(oi).getCoordinates(rootCS);
      double minDist2 = std::numeric_limits<double>::infinity();
      for (size_t ti = 0; ti < terrainMeshPtr->getVertexCount(); ++ti) {
        auto const tc = terrainMeshPtr->getVertex(ti).getCoordinates(rootCS);
        double const dx = (oc.getX() - tc.getX()) / 1_m;
        double const dy = (oc.getY() - tc.getY()) / 1_m;
        double const dz = (oc.getZ() - tc.getZ()) / 1_m;
        minDist2 = std::min(minDist2, dx * dx + dy * dy + dz * dz);
      }
      double const minDist = std::sqrt(minDist2);
      maxMinDist = std::max(maxMinDist, minDist);
      if (minDist > kTolM) ++nMismatched;
    }
    if (nMismatched > 0) {
      CORSIKA_LOG_WARN(
          "Obs/terrain mesh mismatch: {} of {} obs vertices have no matching terrain "
          "vertex within {:.1f} mm (max gap = {:.3f} mm). The two PLY files may not "
          "have been generated from the same geometry -- particles at the observation "
          "surface may propagate through air instead of rock.",
          nMismatched, obsMesh.getVertexCount(), kTolM * 1e3, maxMinDist * 1e3);
    } else {
      CORSIKA_LOG_INFO("Obs/terrain mesh alignment check passed (max vertex gap = {:.4f} mm).",
                       maxMinDist * 1e3);
    }
  }
  return LoadedMeshes{std::move(obsMesh), std::move(terrainMeshPtr), useTerrainMesh};
}

/* === TERRAIN ROCK VOLUME ===
 * The terrain mesh is registered as a HomogeneousMedium (standard rock,
 * 2.65 g/cm³, SiO2 composition) in the environment so that particles
 * propagate through it with correct physics rather than being absorbed at
 * the surface.  No readout is attached; particles that enter rock are
 * tracked by CORSIKA until they stop or escape.
 *
 * The rock volume boundary is shifted 0.1 mm toward Earth's center relative
 * to the terrain mesh surface.  This keeps the obs mesh (which is coplanar
 * with the terrain surface) just inside air, avoiding z-fighting between the
 * absorbing obs mesh and the rock boundary for particles arriving at the
 * valley floor.  Earth-skimming particles that pass through the terrain far
 * from the obs mesh still traverse the rock with full physics.  The PLY
 * files are unchanged; this is a CORSIKA-side adjustment only.
 *
 * Returns ok=false on a fatal atmosphere-topology error (caller must abort).
 * On success rockNodePtr is the stable terrain-rock node address, captured
 * before the ownership move so RockExitRelocator can identify rock-exit
 * boundary crossings; it stays nullptr (relocator no-ops) when the terrain
 * mesh is disabled.
 */
struct TerrainRockResult {
  bool ok;                 // false => fatal atmosphere-topology error, abort
  void const* rockNodePtr; // stable rock-node address, nullptr when disabled
};

static TerrainRockResult registerTerrainRock(EnvType& env,
                                              CoordinateSystemPtr const& rootCS,
                                              Point const& earthSurface,
                                              MagneticFieldVector const& obsField,
                                              bool useTerrainMesh,
                                              TriangularMesh const* terrainMesh) {
  if (!useTerrainMesh) return {true, nullptr};
  constexpr double kInsetM = 1e-4; // 0.1 mm below terrain surface
  std::vector<Point> insetVertices;
  insetVertices.reserve(terrainMesh->getVertexCount());
  double rTopM = 0.0; // max vertex radius (m): how high the terrain reaches
  for (size_t vi = 0; vi < terrainMesh->getVertexCount(); ++vi) {
    auto const c = terrainMesh->getVertex(vi).getCoordinates(rootCS);
    double const x = c.getX() / 1_m;
    double const y = c.getY() / 1_m;
    double const z = c.getZ() / 1_m;
    double const r = std::sqrt(x * x + y * y + z * z);
    if (r > rTopM) rTopM = r;
    double const scale = (r - kInsetM) / r;
    insetVertices.emplace_back(rootCS, scale * x * 1_m, scale * y * 1_m, scale * z * 1_m);
  }
  std::vector<std::array<size_t, 3>> faces;
  faces.reserve(terrainMesh->getTriangleCount());
  for (size_t ti = 0; ti < terrainMesh->getTriangleCount(); ++ti)
    faces.push_back(terrainMesh->getTriangle(ti).getVertexIndices());

  // Code::Silicon is not registered in this CORSIKA build;
  // Set up locally using Silicon = get_nucleus_code(28, 14).
  static media::NuclearComposition const rockComposition{
      {Code::Oxygen, get_nucleus_code(28, 14)}, {0.533, 0.467}};
  auto rockNode = EnvType::createNode<TriangularMesh>(std::move(insetVertices), faces);
  rockNode->setModelProperties<MyExtraEnv<media::HomogeneousMedium<EnvironmentInterface>>>(
      1.000327, earthSurface,
      media::Medium::StandardRock,
      obsField,
      2.65_g / (1_cm * 1_cm * 1_cm),
      rockComposition);
  // CRITICAL: the terrain mesh straddles several spherical atmosphere layers.
  // The tracker only tests the *current* logical node's direct children and
  // excluded-overlap nodes -- one level, no tree descent (Intersect.inl) --
  // and getContainingNode only consults excludes() when no child contains the
  // point.  A rock node attached under any single layer is therefore invisible
  // to a muon traversing it while logically resident in a different layer.
  // Make it reachable for BOTH tracking and medium lookup by registering it as
  // an overlap-exclusion on every atmosphere layer from the innermost up to
  // the highest one the terrain actually reaches (topLayer, resolved via
  // getContainingNode at the terrain's maximum radius).  Ownership goes to
  // topLayer (the topmost spanned layer) so rock.getParent() is a real
  // atmosphere layer -- never the universe, which would erase the particle.
  // The tracker sets a rock-exiting particle's logical node to that parent
  // regardless of where the exit point actually is; exact placement is
  // delivered separately by RockExitRelocator (a BoundaryCrossingProcess in
  // the process sequence) which, on every rock exit, re-resolves the logical
  // node to the true containing node via a full-tree getContainingNode.  So
  // the next step always uses the correct medium, and ownership only governs
  // the getParent()-never-universe safety.
  Point const rockTop{rootCS, 0_m, 0_m, rTopM * 1_m};
  auto* topLayer = env.getUniverse()->getContainingNode(rockTop);
  using LayerPtr = decltype(env.getUniverse().get());
  std::vector<LayerPtr> chain;
  for (LayerPtr L = env.getUniverse()->getChildNodes().empty()
                        ? nullptr
                        : env.getUniverse()->getChildNodes()[0].get();
       L != nullptr;
       L = L->getChildNodes().empty() ? nullptr
                                      : L->getChildNodes()[0].get())
    chain.push_back(L); // outermost -> innermost (single-child layer chain)
  // Both failure cases below are fatal, not recoverable: the chain-based
  // overlap-exclusion logic assumes the atmosphere is the expected nested
  // single-child ball chain.  If that assumption does not hold we cannot
  // know which layers the terrain spans, and continuing would silently run
  // a shower in which Earth-skimming particles ghost through rock with no
  // energy loss.  Refuse to run rather than emit a misleading parquet.
  if (chain.empty()) {
    CORSIKA_LOG_ERROR("No atmosphere layers found; cannot register terrain rock.");
    return {false, nullptr};
  }
  bool reached = false;
  for (auto* L : chain) {
    if (L == topLayer) reached = true;
    if (reached) L->excludeOverlapWith(rockNode); // topLayer .. innermost
  }
  if (!reached) {
    CORSIKA_LOG_ERROR(
        "Terrain top did not resolve into the atmosphere layer chain -- the "
        "atmosphere topology is not the expected nested single-child ball "
        "chain (terrain above the atmosphere, or the atmosphere is not the "
        "universe's first-child path).  Refusing to register terrain rock.");
    return {false, nullptr};
  }
  void const* const rockNodePtr = rockNode.get(); // stable address before move
  topLayer->addChild(std::move(rockNode)); // topmost spanned layer owns it
  CORSIKA_LOG_INFO("Terrain mesh registered as standard rock volume (2.65 g/cm3, {:.2f} mm inset)",
                   kInsetM * 1e3);
  return {true, rockNodePtr};
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main(int argc, char** argv) {

  CLI::App app{"Simulate air showers at the TAMBO site using CORSIKA 8."};

  CORSIKA_LOG_INFO(
      "Please cite the following papers when using CORSIKA 8:\n"
      " - \"Towards a Next Generation of CORSIKA: A Framework for the Simulation of "
      "Particle Cascades in Astroparticle Physics\", Comput. Softw. Big Sci. 3 (2019) "
      "2, https://doi.org/10.1007/s41781-018-0013-0");

  #pragma region CLI options
  // ---- Primary ID ----
  int A = 0, Z = 0;
  std::vector<double> cli_energy_range;

  auto opt_Z = app.add_option("-Z", Z, "Atomic number for primary")
                   ->check(CLI::Range(0, 26))
                   ->group("Primary");
  auto opt_A = app.add_option("-A", A, "Atomic mass number for primary")
                   ->needs(opt_Z)
                   ->check(CLI::Range(1, 58))
                   ->group("Primary");
  app.add_option("-p,--pdg",
                 "PDG code for primary (p=2212, gamma=22, e-=11, mu-=13)")
      ->excludes(opt_A)
      ->excludes(opt_Z)
      ->group("Primary");
  app.add_option("-E,--energy", "Primary energy in GeV")
      ->default_val(0)
      ->group("Primary");
  app.add_option("--energy_range", cli_energy_range,
                 "Low and high values for the primary energy range in GeV")
      ->expected(2)
      ->check(CLI::PositiveNumber)
      ->group("Primary");
  app.add_option("--eslope", "Spectral index for energy sampling, dN/dE = E^eSlope")
      ->default_val(-1.0)
      ->group("Primary");
      
  // ---- Geometry / mesh ----
  app.add_option("--obs-mesh",
                 "Path to the observation-region PLY file (ECEF metres)")
      ->required()
      ->check(CLI::ExistingFile)
      ->group("Geometry");
  app.add_option("--terrain-mesh",
                 "Path to the terrain PLY file used as an absorbing boundary "
                 "(ECEF metres).  Leave empty to disable.")
      ->default_val("")
      ->group("Geometry");
  app.add_option("--inject-x", "X component of the injection point (ECEF metres)")
      ->group("Geometry");
  app.add_option("--inject-y", "Y component of the injection point (ECEF metres)")
      ->group("Geometry");
  app.add_option("--inject-z", "Z component of the injection point (ECEF metres)")
      ->group("Geometry");
  app.add_option("--intercept-x",
                 "X component of the shower-core intercept on the detection region (ECEF metres)")
      ->group("Geometry");
  app.add_option("--intercept-y",
                 "Y component of the shower-core intercept on the detection region (ECEF metres)")
      ->group("Geometry");
  app.add_option("--intercept-z",
                 "Z component of the shower-core intercept on the detection region (ECEF metres)")
      ->group("Geometry");

  // ---- Radio ----
  bool enable_radio = false;
  app.add_flag("--radio", enable_radio,
               "Enable radio emission (CoREAS) sampled at obs-mesh vertices")
      ->group("Radio");
  app.add_option("--radio-antenna-stride",
                 "Place an antenna on every Nth obs-mesh vertex (cost control)")
      ->default_val(16)
      ->check(CLI::PositiveNumber)
      ->group("Radio");
  app.add_option("--radio-time-window", "Antenna trace duration in ns")
      ->default_val(200.0)
      ->check(CLI::PositiveNumber)
      ->group("Radio");
  app.add_option("--radio-sampling", "Antenna sampling rate in GHz")
      ->default_val(5.0)
      ->check(CLI::PositiveNumber)
      ->group("Radio");
  app.add_option("--radio-formalism", "Radio emission formalism")
      ->default_val("coreas")
      ->check(CLI::IsMember({"coreas"}))
      ->group("Radio");

  // ---- Gun (alternative to --inject/--intercept) ----
  app.add_option("--zenith", "Gun: primary zenith angle (deg; >90 = up-going)")
      ->group("Gun");
  app.add_option("--azimuth",
                 "Gun: primary azimuth angle (deg, ENU from East toward North)")
      ->group("Gun");
  app.add_option("--inject-distance",
                 "Gun: distance (km) from core back along the axis to the injection point")
      ->group("Gun");
  app.add_option("--core-x", "Gun: shower-core X (ECEF m; default = obs-mesh centroid)")
      ->group("Gun");
  app.add_option("--core-y", "Gun: shower-core Y (ECEF m; default = obs-mesh centroid)")
      ->group("Gun");
  app.add_option("--core-z", "Gun: shower-core Z (ECEF m; default = obs-mesh centroid)")
      ->group("Gun");

  // ---- Config ----
  app.add_option("--emcut",
                 "Min. kin. energy of photons, electrons and positrons (GeV)")
      ->default_val(10.0)
      ->check(CLI::Range(1e-6, 1.e13))
      ->group("Config");
  app.add_option("--hadcut", "Min. kin. energy of hadrons (GeV)")
      ->default_val(1.0)
      ->check(CLI::Range(0.02, 1.e13))
      ->group("Config");
  app.add_option("--mucut", "Min. kin. energy of muons (GeV)")
      ->default_val(10.0)
      ->check(CLI::Range(1e-6, 1.e13))
      ->group("Config");
  app.add_option("--taucut", "Min. kin. energy of tau leptons (GeV)")
      ->default_val(10.0)
      ->check(CLI::Range(1e-6, 1.e13))
      ->group("Config");
  app.add_option("--max-deflection-angle",
                 "Maximum deflection angle in tracking (radians)")
      ->default_val(0.2)
      ->check(CLI::Range(1e-8, 1.))
      ->group("Config");

  bool track_neutrinos = false;
  app.add_flag("--track-neutrinos", track_neutrinos, "Enable neutrino tracking")
      ->group("Config");
  bool track_charm = false;
  app.add_flag("--track-charm", track_charm,
               "Enable charmed hadron tracking (Sibyll, Pythia8, EPOS-LHC-R, QGSJet-III)")
      ->group("Config");

  app.add_option("-M,--hadronModel", "High-energy hadronic interaction model")
      ->default_val("SIBYLL-2.3d")
      ->check(CLI::IsMember({"SIBYLL-2.3d", "QGSJet-II.04", "QGSJet-III", "EPOS-LHC",
                             "EPOS-LHC-R", "Pythia8"}))
      ->group("Config");
  app.add_option("-T,--hadronModelTransitionEnergy",
                 "Transition energy between high-/low-energy hadronic models (GeV)")
      ->default_val(std::pow(10, 1.9))
      ->check(CLI::NonNegativeNumber)
      ->group("Config");

  // ---- Thinning ----
  app.add_option("--emthin",
                 "Fraction of primary energy at which EM thinning starts")
      ->default_val(1e-6)
      ->check(CLI::Range(0., 1.))
      ->group("Thinning");
  app.add_option("--max-weight",
                 "Maximum weight for EM thinning (0 = Kobal optimum * 0.5)")
      ->default_val(0)
      ->check(CLI::NonNegativeNumber)
      ->group("Thinning");
  bool multithin = false;
  app.add_flag("--multithin", multithin, "Keep thinned particles (weight=0)")
      ->group("Thinning");

  // ---- Output ----
  app.add_option("-N,--nevent", "Number of showers to simulate")
      ->default_val(1)
      ->check(CLI::PositiveNumber)
      ->group("Output");
  app.add_option("-f,--filename", "Output library filename")
      ->required()
      ->group("Output");
  bool compressOutput = false;
  app.add_flag("--compress", compressOutput, "Compress output directory to tarball")
      ->group("Output");
  bool forceOverwrite = false;
  app.add_flag("--force", forceOverwrite,
               "Wipe the output directory if it already exists")
      ->group("Output");

  // ---- Misc ----
  app.add_option("-s,--seed", "Random number seed (0 = auto)")
      ->default_val(0)
      ->check(CLI::NonNegativeNumber)
      ->group("Misc");
  bool force_interaction = false;
  app.add_flag("--force-interaction", force_interaction,
               "Force the first interaction at the injection point")
      ->group("Misc");
  bool force_decay = false;
  app.add_flag("--force-decay", force_decay, "Force the primary to immediately decay")
      ->group("Misc");
  app.add_option("-v,--verbosity", "Verbosity level: warn, info, debug, trace")
      ->default_val("info")
      ->check(CLI::IsMember({"warn", "info", "debug", "trace"}))
      ->group("Misc");
  app.add_option("--neutrino-interaction-type",
                 "Neutrino interaction type: neutral/NC, charged/CC, or both")
      ->default_val("both")
      ->check(CLI::IsMember({"neutral", "NC", "charged", "CC", "both"}))
      ->group("Misc");

  #pragma endregion

  #pragma region Parse + validate
  CLI11_PARSE(app, argc, argv);

  // ---- Verbosity ----
  if (app.count("--verbosity")) {
    auto const lv = app["--verbosity"]->as<std::string>();
    if (lv == "warn") logging::set_level(logging::level::warn);
    else if (lv == "info") logging::set_level(logging::level::info);
    else if (lv == "debug") logging::set_level(logging::level::debug);
    else if (lv == "trace") {
#ifndef _C8_DEBUG_
      CORSIKA_LOG_ERROR("trace log level requires a Debug build.");
      return EXIT_FAILURE;
#endif
      logging::set_level(logging::level::trace);
    }
  }

  // ---- Validate primary ID ----
  if (app.count("--pdg") == 0) {
    if ((app.count("-A") == 0) || (app.count("-Z") == 0)) {
      CORSIKA_LOG_ERROR("If --pdg is not provided, both -A and -Z are required.");
      return EXIT_FAILURE;
    }
  }

  // ---- Validate injection-geometry mode (ECEF pair XOR gun triple) ----
  bool const gun_mode = app.count("--zenith") && app.count("--azimuth") &&
                        app.count("--inject-distance");
  bool const ecef_mode = app.count("--inject-x") && app.count("--inject-y") &&
                         app.count("--inject-z") && app.count("--intercept-x") &&
                         app.count("--intercept-y") && app.count("--intercept-z");
  if (gun_mode == ecef_mode) {
    CORSIKA_LOG_CRITICAL(
        "Specify EITHER --inject-x/y/z + --intercept-x/y/z, OR the gun flags "
        "--zenith + --azimuth + --inject-distance (not both, not neither).");
    return EXIT_FAILURE;
  }

  // ---- Random streams ----
  auto seed = registerRandomStreams(app["--seed"]->as<long>());

  #pragma endregion

  #pragma region Environment
  /* === ENVIRONMENT === */
  EnvType env;
  CoordinateSystemPtr const& rootCS = env.getCoordinateSystem();
  Point const earthCenter{rootCS, 0_m, 0_m, 0_m};
  Point const earthSurface{rootCS, 0_m, 0_m, constants::EarthRadius::Mean};
  // media::GeomagneticModel wmm(earthCenter, corsika_data("GeoMag/WMM.COF"));

  #pragma endregion

  #pragma region Load meshes
  /* === LOAD MESHES === */
  LoadedMeshes loadedMeshes = loadMeshes(app["--obs-mesh"]->as<std::string>(),
                                         app["--terrain-mesh"]->as<std::string>(),
                                         rootCS);
  TriangularMesh& obsMesh = loadedMeshes.obsMesh;
  bool const useTerrainMesh = loadedMeshes.useTerrainMesh;

  #pragma endregion

  #pragma region Core + ENU
  /* === SHOWER CORE AND ENU FRAME ===
   * The core (cx, cy, cz) is the reference point on the detector region in ECEF
   * metres.  In ECEF mode it is the pre-computed intercept passed by the Julia
   * caller (--intercept-x/y/z).  In gun mode it is either --core-x/y/z or, by
   * default, the obs-mesh centroid.  The ENU frame at the core is used for the
   * magnetic field, the escape plane, and (in gun mode) the propagation axis.
   */
  double cx, cy, cz;
  if (ecef_mode) {
    cx = app["--intercept-x"]->as<double>();
    cy = app["--intercept-y"]->as<double>();
    cz = app["--intercept-z"]->as<double>();
  } else {
    // gun mode: core = --core-x/y/z if given, else obs-mesh centroid
    if (app.count("--core-x") && app.count("--core-y") && app.count("--core-z")) {
      cx = app["--core-x"]->as<double>();
      cy = app["--core-y"]->as<double>();
      cz = app["--core-z"]->as<double>();
    } else {
      double sx = 0.0, sy = 0.0, sz = 0.0;
      size_t const nv = obsMesh.getVertexCount();
      for (size_t i = 0; i < nv; ++i) {
        auto const c = obsMesh.getVertex(i).getCoordinates(rootCS);
        sx += c.getX() / 1_m;
        sy += c.getY() / 1_m;
        sz += c.getZ() / 1_m;
      }
      cx = sx / nv;
      cy = sy / nv;
      cz = sz / nv;
    }
  }
  std::array<double, 3> eastHat, northHat, upHat;
  ecefToENU(cx, cy, cz, eastHat, northHat, upHat);

  #pragma endregion

  #pragma region Atmosphere
  /* === ATMOSPHERE with correct magnetic field at obs mesh centroid === */
  // WMM for TAMBO site (lat ~ -15.6°, lon ~ -72.3°, alt ~ 3.5 km, epoch 2024):
  // see https://www.ngdc.noaa.gov/geomag/calculators/magcalc.shtml#igrfwmm
  constexpr double B_E =  -2.5;  // uT (eastward component)
  constexpr double B_N =  22.9;  // uT (northward component)
  constexpr double B_U =  -3.7;  // uT (upward component)
  double const Bx = B_E * eastHat[0] + B_N * northHat[0] + B_U * upHat[0];
  double const By = B_E * eastHat[1] + B_N * northHat[1] + B_U * upHat[1];
  double const Bz = B_E * eastHat[2] + B_N * northHat[2] + B_U * upHat[2];
  MagneticFieldVector const obsField{rootCS, Bx * 1_uT, By * 1_uT, Bz * 1_uT};

  CORSIKA_LOG_INFO("Magnetic field (ECEF nT): ({:.1f}, {:.1f}, {:.1f})",
                   obsField.getX(rootCS) / 1_nT,
                   obsField.getY(rootCS) / 1_nT,
                   obsField.getZ(rootCS) / 1_nT);

  create_5layer_colca_atmosphere<EnvironmentInterface, MyExtraEnv>(
      env, earthCenter, 1.000327, earthSurface,
      media::Medium::AirDry1Atm, obsField);

  #pragma endregion

  #pragma region Terrain rock volume
  /* === TERRAIN ROCK VOLUME (see registerTerrainRock above) === */
  auto const rock = registerTerrainRock(env, rootCS, earthSurface, obsField,
                                        useTerrainMesh,
                                        loadedMeshes.terrainMesh.get());
  if (!rock.ok) return EXIT_FAILURE;
  void const* const rockNodePtr = rock.rockNodePtr;

  #pragma endregion

  #pragma region Primary particle ID
  /* === PRIMARY PARTICLE ID === */
  Code beamCode;
  if (app.count("--pdg") > 0) {
    beamCode = convert_from_PDG(PDGCode(app["--pdg"]->as<int>()));
  } else {
    if ((A == 1) && (Z == 1))
      beamCode = Code::Proton;
    else if ((A == 1) && (Z == 0))
      beamCode = Code::Neutron;
    else
      beamCode = get_nucleus_code(A, Z);
  }

  HEPEnergyType eMin = 0_GeV, eMax = 0_GeV;
  if (app["--energy"]->as<double>() > 0.0) {
    eMin = eMax = app["--energy"]->as<double>() * 1_GeV;
  } else if (!cli_energy_range.empty()) {
    eMin = std::min(cli_energy_range[0], cli_energy_range[1]) * 1_GeV;
    eMax = std::max(cli_energy_range[0], cli_energy_range[1]) * 1_GeV;
  } else {
    CORSIKA_LOG_CRITICAL("Must set either --energy or --energy_range.");
    return EXIT_FAILURE;
  }

  #pragma endregion

  #pragma region Injection geometry
  /* === INJECTION GEOMETRY ===
   * Two modes resolve the same trio of quantities: the propagation direction
   * (pnx, pny, pnz, ECEF unit vector), the shower core (cx, cy, cz, resolved in
   * the Core + ENU region), and the injection point (injectX/Y/Z, ECEF metres).
   *
   *   ECEF mode: inject and intercept are given directly; the direction is the
   *              unit vector from inject to intercept (core).
   *   Gun mode:  the direction is built from (zenith, azimuth) in the ENU frame
   *              at the core, and inject = core - inject_distance * propDir.
   */
  double injectX, injectY, injectZ;  // ECEF metres
  double pnx, pny, pnz;              // propagation unit vector (ECEF)

  if (ecef_mode) {
    injectX = app["--inject-x"]->as<double>();
    injectY = app["--inject-y"]->as<double>();
    injectZ = app["--inject-z"]->as<double>();

    // Propagation direction: inject → intercept (normalised)
    double const dx = cx - injectX, dy = cy - injectY, dz = cz - injectZ;
    double const dnorm = std::sqrt(dx * dx + dy * dy + dz * dz);
    if (dnorm == 0.0) {
      CORSIKA_LOG_CRITICAL("Inject and intercept points are identical.");
      return EXIT_FAILURE;
    }
    pnx = dx / dnorm;
    pny = dy / dnorm;
    pnz = dz / dnorm;
  } else {
    // Gun mode: direction from (zenith, azimuth) in the ENU frame at the core.
    constexpr double kDeg2Rad = M_PI / 180.0;
    double const zen = app["--zenith"]->as<double>() * kDeg2Rad;
    double const azi = app["--azimuth"]->as<double>() * kDeg2Rad;
    // ENU components of the propagation direction.  Azimuth measured from East
    // toward North; zenith from local up (>90 deg = up-going).
    double const dE = std::sin(zen) * std::cos(azi);
    double const dN = std::sin(zen) * std::sin(azi);
    double const dU = std::cos(zen);
    // Rotate ENU → ECEF using the local basis at the core.
    pnx = dE * eastHat[0] + dN * northHat[0] + dU * upHat[0];
    pny = dE * eastHat[1] + dN * northHat[1] + dU * upHat[1];
    pnz = dE * eastHat[2] + dN * northHat[2] + dU * upHat[2];

    // injection point = core - inject_distance * propDir
    double const L = app["--inject-distance"]->as<double>() * 1000.0;  // km → m
    injectX = cx - L * pnx;
    injectY = cy - L * pny;
    injectZ = cz - L * pnz;
  }

  DirectionVector const propDir{rootCS, {pnx, pny, pnz}};
  Point const showerCore{rootCS, cx * 1_m, cy * 1_m, cz * 1_m};
  Point const injectionPos{rootCS, injectX * 1_m, injectY * 1_m, injectZ * 1_m};

  // Shower axis: from injection through core and 20% beyond
  media::ShowerAxis const showerAxis{injectionPos, (showerCore - injectionPos) * 1.2,
                                     env};
  auto const dX = 10_g / square(1_cm);

  {
    double const dx = cx - injectX, dy = cy - injectY, dz = cz - injectZ;
    double const dnorm = std::sqrt(dx * dx + dy * dy + dz * dz);
    CORSIKA_LOG_INFO("Injection point (ECEF m): ({:.1f}, {:.1f}, {:.1f})", injectX, injectY,
                     injectZ);
    CORSIKA_LOG_INFO("Shower core (ECEF m): ({:.1f}, {:.1f}, {:.1f})", cx, cy, cz);
    CORSIKA_LOG_INFO("Injection distance: {:.1f} km", dnorm / 1000.);
    CORSIKA_LOG_INFO("Propagation direction (ECEF): ({:.4f}, {:.4f}, {:.4f})", pnx, pny, pnz);
  }

  #pragma endregion

  #pragma region Output manager
  /* === OUTPUT MANAGER === */
  std::stringstream args;
  for (int i = 0; i < argc; ++i) { args << argv[i] << " "; }
  std::string const outFilename = app["--filename"]->as<std::string>();
  if (boost::filesystem::exists(outFilename)) {
    if (forceOverwrite) {
      CORSIKA_LOG_WARN("Removing existing output directory: {}", outFilename);
      boost::filesystem::remove_all(outFilename);
    } else {
      CORSIKA_LOG_CRITICAL("Output path already exists: {} (use --force to overwrite)",
                           outFilename);
      return EXIT_FAILURE;
    }
  }
  OutputManager output(outFilename, seed, args.str(), compressOutput);

  EnergyLossWriter dEdX{showerAxis, dX};
  output.add("energyloss", dEdX);

  // TrackWriter records every tracking step (start/end position, energy, PDG, weight)
  // to tracks.parquet -- useful for shower visualisations.  Note: files can be very
  // large for high-energy showers (O(GB) at 1 PeV without thinning); consider
  // enabling only for low-multiplicity or thinned runs.
  // TrackWriter<TrackWriterParquet> trackWriter;
  // output.add("tracks", trackWriter);

  #pragma endregion

  #pragma region Physics processes
  /* === PHYSICS PROCESSES === */
  DynamicInteractionProcess<StackType> heModel;
  set<Code> const trackedParticles =
      (track_charm ? corsika::setup::C7trackedParticlesAndCharm
                   : corsika::setup::C7trackedParticles);
  auto const all_elements = corsika::media::get_all_elements_in_universe(env);
  auto sibyll =
      std::make_shared<corsika::sibyll::Interaction>(all_elements, trackedParticles);

  if (auto const ms = app["--hadronModel"]->as<std::string>(); ms == "SIBYLL-2.3d") {
    heModel = DynamicInteractionProcess<StackType>{sibyll};
  } else if (ms == "QGSJet-II.04") {
    heModel = DynamicInteractionProcess<StackType>{
        std::make_shared<corsika::qgsjetII::Interaction>()};
  } else if (ms == "QGSJet-III") {
    heModel = DynamicInteractionProcess<StackType>{
        std::make_shared<corsika::qgsjetIII::Interaction>()};
  } else if (ms == "EPOS-LHC") {
    heModel = DynamicInteractionProcess<StackType>{
        std::make_shared<corsika::epos::Interaction>(trackedParticles)};
  } else if (ms == "EPOS-LHC-R") {
    heModel = DynamicInteractionProcess<StackType>{
        std::make_shared<corsika::EPOS_LHCR::Interaction>(trackedParticles)};
  } else if (ms == "Pythia8") {
    heModel = DynamicInteractionProcess<StackType>{
        std::make_shared<corsika::pythia8::Interaction>(trackedParticles)};
  } else {
    CORSIKA_LOG_CRITICAL("Invalid hadron model: {}", ms);
    return EXIT_FAILURE;
  }

  InteractionCounter heCounted{heModel};

  corsika::pythia8::Decay decaySequence;

  bool NC = false, CC = false;
  if (auto const s = app["--neutrino-interaction-type"]->as<std::string>();
      s == "neutral" || s == "NC") {
    NC = true;
  } else if (s == "charged" || s == "CC") {
    CC = true;
  } else {
    NC = CC = true;
  }
  corsika::pythia8::NeutrinoInteraction neutrinoPrimaryPythia(trackedParticles, NC, CC);
  corsika::sophia::InteractionModel sophia;

  HEPEnergyType const emcut = 1_GeV * app["--emcut"]->as<double>();
  HEPEnergyType const hadcut = 1_GeV * app["--hadcut"]->as<double>();
  HEPEnergyType const mucut = 1_GeV * app["--mucut"]->as<double>();
  HEPEnergyType const taucut = 1_GeV * app["--taucut"]->as<double>();
  ParticleCut<SubWriter<decltype(dEdX)>> cut(emcut, emcut, hadcut, mucut, taucut,
                                             !track_neutrinos, dEdX);

  auto const prod_threshold = std::min({emcut, hadcut, mucut, taucut});
  set_energy_production_threshold(Code::Electron, prod_threshold);
  set_energy_production_threshold(Code::Positron, prod_threshold);
  set_energy_production_threshold(Code::Photon, prod_threshold);
  set_energy_production_threshold(Code::MuMinus, prod_threshold);
  set_energy_production_threshold(Code::MuPlus, prod_threshold);
  set_energy_production_threshold(Code::TauMinus, prod_threshold);
  set_energy_production_threshold(Code::TauPlus, prod_threshold);

  HEPEnergyType const heThreshold =
      1_GeV * app["--hadronModelTransitionEnergy"]->as<double>();
  corsika::proposal::Interaction emCascade(
      env, sophia, sibyll->getHadronInteractionModel(), heThreshold);
  corsika::proposal::ContinuousProcess<SubWriter<decltype(dEdX)>> emContinuousProposal(
      env, dEdX);
  BetheBlochPDG<SubWriter<decltype(dEdX)>> emContinuousBethe{dEdX};
  struct EMHadronSwitch {
    bool operator()(Particle const& p) const { return is_hadron(p.getPID()); }
  };
  auto emContinuous =
      make_select(EMHadronSwitch(), emContinuousBethe, emContinuousProposal);

  LongitudinalWriter profile{showerAxis, dX};
  output.add("profile", profile);
  LongitudinalProfile<SubWriter<decltype(profile)>> longprof{profile};

  // ProductionWriter prod_profile{showerAxis, dX};
  // output.add("production_profile", prod_profile);
  // ProductionProfile<SubWriter<decltype(prod_profile)>> prodprof{prod_profile};

#ifdef WITH_FLUKA
  corsika::fluka::Interaction leIntModel{all_elements};
#else
  corsika::urqmd::UrQMD leIntModel{};
#endif
  InteractionCounter leIntCounted{leIntModel};

  struct EnergySwitch {
    HEPEnergyType cutE_;
    EnergySwitch(HEPEnergyType cutE) : cutE_(cutE) {}
    bool operator()(Particle const& p) const {
      return (p.getKineticEnergy() < cutE_);
    }
  };
  auto hadronSequence =
      make_select(EnergySwitch(heThreshold), leIntCounted, heCounted);

  #pragma endregion

  #pragma region Observation mesh
  /* === OBSERVATION MESH (absorbing: records and removes particles at valley floor) === */
  ObservationMesh<TrackingType, ParticleWriterParquet> observationLevel{
      obsMesh, 
      true,     // absorbing
      1e-6_m,   // padding
      false,    // writeHitInfo
      true,     // recordEntry
      false,    // recordExit
    };
  output.add("particles", observationLevel);

  PrimaryWriter<TrackingType, ParticleWriterParquet> primaryWriter(obsMesh);
  output.add("primary", primaryWriter);

  InteractionWriter<TrackingType, ParticleWriterParquet> inter_writer(showerAxis, obsMesh);
  output.add("interactions", inter_writer);

  #pragma endregion

  #pragma region Shower loop
  /* === SHOWER LOOP === */
  // Per-shower quantities extracted from CLI to avoid repeated parsing
  double const emthinfrac = app["--emthin"]->as<double>();
  double const maxWeightArg = app["--max-weight"]->as<double>();
  double const eSlope = app["--eslope"]->as<double>();
  double const maxDefl = app["--max-deflection-angle"]->as<double>();
  int const nev = app["--nevent"]->as<int>();

  // Lambda that runs one shower given a pre-assembled process sequence.
  // EMThinning and StackInspector are added here because they depend on the
  // per-shower primary energy.
  auto runOneShower = [&](auto& sequence, int i_shower,
                          HEPEnergyType primaryTotalEnergy) {
    HEPEnergyType const eKin = primaryTotalEnergy - get_mass(beamCode);

    double const maxW = (maxWeightArg > 0)
                            ? maxWeightArg
                            : 0.5 * emthinfrac * primaryTotalEnergy / 1_GeV;
    EMThinning thinning{emthinfrac * primaryTotalEnergy, maxW, !multithin};
    StackInspector<StackType> stackInspect(10000, false, primaryTotalEnergy);
    RockExitRelocator rockRelocator{env, rockNodePtr};
    RockEMAbsorber rockEMAbsorber{rockNodePtr};
    RockInterfaceTripwire rockTripwire{rockNodePtr};

    // Order mirrors c8_air_shower: inspector first, thinning near end before cut.
    // rockRelocator runs early so any later boundary-aware process in the same
    // crossing observes the corrected logical node.  rockEMAbsorber runs before
    // the EM/hadron/decay processes so an e+-/gamma in rock is removed before
    // any interaction is sampled for it that step (collapsing the cascade).
    // rockTripwire is a passive per-step invariant check (logical==rock implies
    // contains()); it mutates nothing and only aborts on a sustained violation.
    auto fullSequence = make_sequence(stackInspect, rockRelocator, rockEMAbsorber,
                                      rockTripwire,
                                      neutrinoPrimaryPythia, hadronSequence,
                                      decaySequence, emCascade, 
                                      // prodprof, 
                                      emContinuous,
                                      longprof, sequence,
                                      // trackWriter,  
                                      inter_writer, 
                                      thinning, cut);

    TrackingType tracking(maxDefl);
    StackType stack;
    Cascade EAS(env, tracking, fullSequence, output, stack);
    stack.clear();

    CORSIKA_LOG_INFO("Primary: {}  E_kin = {} GeV", beamCode, eKin / 1_GeV);
    CORSIKA_LOG_INFO("Shower {} of {}", i_shower, nev);

    auto const primaryProperties =
        std::make_tuple(beamCode, eKin, propDir.normalized(), injectionPos, 0_ns);
    stack.addParticle(primaryProperties);

    if (force_interaction) {
      CORSIKA_LOG_INFO("Forcing first interaction at injection point.");
      EAS.forceInteraction();
    }
    if (force_decay) {
      CORSIKA_LOG_INFO("Forcing primary decay.");
      EAS.forceDecay();
    }

    primaryWriter.recordPrimary(primaryProperties);
    EAS.run();
  };

  output.startOfLibrary();
  for (int i = 1; i <= nev; ++i) {
    PowerLawDistribution<HEPEnergyType> plRng(eSlope, eMin, eMax);
    HEPEnergyType const E = (eMax == eMin)
        ? eMin
        : plRng(RNGManager<>::getInstance().getRandomStream("primary_particle"));
    auto obsMeshSequence = make_sequence(observationLevel);
    runOneShower(obsMeshSequence, i, E);
  }

  output.endOfLibrary();
  #pragma endregion
  return EXIT_SUCCESS;
}
