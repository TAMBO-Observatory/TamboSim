/*
 * TAMBO cosmic-ray air-shower simulation using CORSIKA 8.
 *
 * Simulates showers observed at the TAMBO detector site in the Colca
 * Valley, Peru. Two triangular meshes in ECEF coordinates drive the geometry:
 *
 *   obs_surface.ply  -  valley floor observation surface
 *   terrain.ply      -  surrounding terrain rock volume (optional)
 *
 * The shower trajectory is specified by two ECEF points passed on the command
 * line: the injection point (--inject-x/y/z, upstream, ~112 km altitude) and
 * the intercept on the detection region (--intercept-x/y/z).  In normal use
 * these coordinates are computed by the Julia corsika_run! orchestrator
 * (src/corsika/run_corsika.jl), which traces the particle trajectory to the
 * detector mesh and emits the argv for this binary.
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
#include <corsika/framework/geometry/Sphere.hpp>
#include <corsika/framework/geometry/TriangularMesh.hpp>
#include <corsika/framework/process/DynamicInteractionProcess.hpp>
#include <corsika/framework/process/ProcessSequence.hpp>
#include <corsika/framework/process/SwitchProcessSequence.hpp>
#include <corsika/framework/random/RNGManager.hpp>
#include <corsika/framework/random/PowerLawDistribution.hpp>
#include <corsika/framework/utility/CorsikaFenv.hpp>
#include <corsika/framework/utility/SaveBoostHistogram.hpp>

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
#include <corsika/modules/ObservationPlane.hpp>
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
#include <limits>
#include <string>

using namespace corsika;
using namespace std;

using EnvironmentInterface = media::IRefractiveIndexModel<
    media::IMediumPropertyModel<media::IMagneticFieldModel<media::IMediumModel>>>;
using EnvType = media::Environment<EnvironmentInterface>;
using StackType = setup::Stack<EnvType>;
using TrackingType = setup::Tracking;
using Particle = StackType::particle_type;

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
// main
// ---------------------------------------------------------------------------
int main(int argc, char** argv) {

  CLI::App app{"Simulate air showers at the TAMBO site using CORSIKA 8."};

  CORSIKA_LOG_INFO(
      "Please cite the following papers when using CORSIKA 8:\n"
      " - \"Towards a Next Generation of CORSIKA: A Framework for the Simulation of "
      "Particle Cascades in Astroparticle Physics\", Comput. Softw. Big Sci. 3 (2019) "
      "2, https://doi.org/10.1007/s41781-018-0013-0");

  // ---- Primary ID ----
  int A = 0, Z = 0, nevent = 0;
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
      ->required()
      ->group("Geometry");
  app.add_option("--inject-y", "Y component of the injection point (ECEF metres)")
      ->required()
      ->group("Geometry");
  app.add_option("--inject-z", "Z component of the injection point (ECEF metres)")
      ->required()
      ->group("Geometry");
  app.add_option("--intercept-x",
                 "X component of the shower-core intercept on the detection region (ECEF metres)")
      ->required()
      ->group("Geometry");
  app.add_option("--intercept-y",
                 "Y component of the shower-core intercept on the detection region (ECEF metres)")
      ->required()
      ->group("Geometry");
  app.add_option("--intercept-z",
                 "Z component of the shower-core intercept on the detection region (ECEF metres)")
      ->required()
      ->group("Geometry");

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
  app.add_option("-N,--nevent", nevent, "Number of showers to simulate")
      ->default_val(1)
      ->check(CLI::PositiveNumber)
      ->group("Output");
  app.add_option("-f,--filename", "Output library filename")
      ->required()
      ->default_val("tambo_library")
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
  bool disable_interaction_hists = true;
  app.add_flag("--disable-interaction-histograms", disable_interaction_hists,
               "Disable saving interaction histograms")
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
      return 1;
#endif
      logging::set_level(logging::level::trace);
    }
  }

  // ---- Validate primary ID ----
  if (app.count("--pdg") == 0) {
    if ((app.count("-A") == 0) || (app.count("-Z") == 0)) {
      CORSIKA_LOG_ERROR("If --pdg is not provided, both -A and -Z are required.");
      return 1;
    }
  }

  // ---- Random streams ----
  auto seed = registerRandomStreams(app["--seed"]->as<long>());

  /* === ENVIRONMENT === */
  EnvType env;
  CoordinateSystemPtr const& rootCS = env.getCoordinateSystem();
  Point const earthCenter{rootCS, 0_m, 0_m, 0_m};
  Point const earthSurface{rootCS, 0_m, 0_m, constants::EarthRadius::Mean};
  // media::GeomagneticModel wmm(earthCenter, corsika_data("GeoMag/WMM.COF"));

  /* === LOAD MESHES === */
  std::string const obsMeshPath = app["--obs-mesh"]->as<std::string>();
  CORSIKA_LOG_INFO("Loading observation mesh: {}", obsMeshPath);
  // PLY coordinates are ECEF metres; load directly into rootCS with scale=1_m
  TriangularMesh obsMesh = TriangularMesh::fromPLY(obsMeshPath, rootCS, 1_m, 1e-6_m);
  CORSIKA_LOG_INFO("Observation mesh: {} vertices, {} triangles",
                   obsMesh.getVertexCount(), obsMesh.getTriangleCount());

  std::string const terrainMeshPath = app["--terrain-mesh"]->as<std::string>();
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

  /* === INTERCEPT POINT AND ENU FRAME ===
   * The intercept is the pre-computed intersection of the particle trajectory
   * with the detector region, passed in ECEF metres from the Julia caller.
   * The ENU frame at the intercept is used for the magnetic field and escape plane.
   */
  double const cx = app["--intercept-x"]->as<double>();
  double const cy = app["--intercept-y"]->as<double>();
  double const cz = app["--intercept-z"]->as<double>();
  CORSIKA_LOG_INFO("Shower core / intercept (ECEF m): ({:.1f}, {:.1f}, {:.1f})", cx, cy, cz);

  std::array<double, 3> eastHat, northHat, upHat;
  ecefToENU(cx, cy, cz, eastHat, northHat, upHat);

  /* === ESCAPE PLANE: 1 mm below the lowest point of the observation mesh ===
   *
   * The plane is perpendicular to the upward radial direction at the
   * area-weighted centroid of the observation mesh (i.e. normal = upHat).
   * "Lowest" is measured as the minimum projection of obs-mesh vertices
   * onto upHat, which is the vertical distance from Earth centre.
   * Absorbing: particles that escape the obs mesh are recorded and removed
   * here instead of propagating indefinitely.
   */
  double minVertProj = std::numeric_limits<double>::infinity();
  for (size_t vi = 0; vi < obsMesh.getVertexCount(); ++vi) {
    auto const coords = obsMesh.getVertex(vi).getCoordinates(rootCS);
    double const proj = coords.getX() / 1_m * upHat[0]
                      + coords.getY() / 1_m * upHat[1]
                      + coords.getZ() / 1_m * upHat[2];
    minVertProj = std::min(minVertProj, proj);
  }
  double const escapePlaneDist = minVertProj - 0.001; // 1 mm below lowest vertex
  Point const escapePlaneCenter{rootCS,
      escapePlaneDist * upHat[0] * 1_m,
      escapePlaneDist * upHat[1] * 1_m,
      escapePlaneDist * upHat[2] * 1_m};
  DirectionVector const escapeNormal{rootCS, {upHat[0], upHat[1], upHat[2]}};
  DirectionVector const escapeRefDir{rootCS, {eastHat[0], eastHat[1], eastHat[2]}};
  Plane const escapePlane{escapePlaneCenter, escapeNormal};
  CORSIKA_LOG_INFO("Escape plane distance from Earth centre: {:.1f} m  ({:.1f} mm below lowest obs vertex)",
                   escapePlaneDist, 1.0);

  /* === ATMOSPHERE with correct magnetic field at obs mesh centroid === */
  // // WMM for TAMBO site (lat ~ -15.6°, lon ~ -72.3°, alt ~ 3.5 km, epoch 2024):
  // //   B_E ~ -1700 nT (slightly westward)
  // //   B_N ~ 25500 nT (mostly northward)
  // //   B_U ~ 11000 nT (upward, southern hemisphere)
  // // Rotate these ENU components into ECEF using the site's ENU basis vectors.
  // constexpr double B_E_T =  -1700e-9;  // Tesla (eastward component)
  // constexpr double B_N_T =  25500e-9;  // Tesla (northward component)
  // constexpr double B_U_T =  11000e-9;  // Tesla (upward component)
  // double const Bx = B_E_T * eastHat[0] + B_N_T * northHat[0] + B_U_T * upHat[0];
  // double const By = B_E_T * eastHat[1] + B_N_T * northHat[1] + B_U_T * upHat[1];
  // double const Bz = B_E_T * eastHat[2] + B_N_T * northHat[2] + B_U_T * upHat[2];
  // MagneticFieldVector const obsField{rootCS, Bx * 1_T, By * 1_T, Bz * 1_T};

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

  /* === TERRAIN ROCK VOLUME ===
   * The terrain mesh is registered as a HomogeneousMedium (standard rock,
   * 2.65 g/cm³, SiO2 composition) in the environment so that particles
   * propagate through it with correct physics rather than being absorbed at
   * the surface.  No readout is attached; particles that enter rock are
   * tracked by CORSIKA until they stop or escape.
   *
   * The rock volume boundary is shifted 0.1 mm toward Earth's center relative
   * to the terrain mesh surface.  This guarantees that the obs mesh (which is
   * coplanar with the terrain surface) lies in air above the rock boundary.
   * Particles traveling downward from air are absorbed by the obs mesh before
   * they ever reach the rock volume.  The PLY files are unchanged; this is a
   * CORSIKA-side adjustment only.
   */
  if (useTerrainMesh) {
    constexpr double kInsetM = 1e-4; // 0.1 mm below terrain surface
    std::vector<Point> insetVertices;
    insetVertices.reserve(terrainMeshPtr->getVertexCount());
    for (size_t vi = 0; vi < terrainMeshPtr->getVertexCount(); ++vi) {
      auto const c = terrainMeshPtr->getVertex(vi).getCoordinates(rootCS);
      double const x = c.getX() / 1_m;
      double const y = c.getY() / 1_m;
      double const z = c.getZ() / 1_m;
      double const r = std::sqrt(x * x + y * y + z * z);
      double const scale = (r - kInsetM) / r;
      insetVertices.emplace_back(rootCS, scale * x * 1_m, scale * y * 1_m, scale * z * 1_m);
    }
    std::vector<std::array<size_t, 3>> faces;
    faces.reserve(terrainMeshPtr->getTriangleCount());
    for (size_t ti = 0; ti < terrainMeshPtr->getTriangleCount(); ++ti)
      faces.push_back(terrainMeshPtr->getTriangle(ti).getVertexIndices());

    // Code::Silicon is not registered in this CORSIKA build; Oxygen (Z/A=0.5)
    // matches standard rock's bulk Z/A and is used as a proxy for SiO2.
    static media::NuclearComposition const rockComposition{
        {Code::Oxygen}, {1.0}};
    auto rockNode = EnvType::createNode<TriangularMesh>(std::move(insetVertices), faces);
    rockNode->setModelProperties<MyExtraEnv<HomogeneousMedium<EnvironmentInterface>>>(
        1.000327, earthSurface,
        media::Medium::StandardRock,
        obsField,
        2.65_g / (1_cm * 1_cm * 1_cm),
        rockComposition);
    env.getUniverse()->addChild(std::move(rockNode));
    CORSIKA_LOG_INFO("Terrain mesh registered as standard rock volume (2.65 g/cm3, {:.2f} mm inset)",
                     kInsetM * 1e3);
  }

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
    return 1;
  }

  /* === INJECTION GEOMETRY ===
   * The injection point and shower-core intercept are provided directly in
   * ECEF metres. The shower direction is the unit vector from inject to intercept.
   */
  double const injectX = app["--inject-x"]->as<double>();
  double const injectY = app["--inject-y"]->as<double>();
  double const injectZ = app["--inject-z"]->as<double>();

  // Propagation direction: inject → intercept (normalised)
  double const dx = cx - injectX, dy = cy - injectY, dz = cz - injectZ;
  double const dnorm = std::sqrt(dx * dx + dy * dy + dz * dz);
  if (dnorm == 0.0) {
    CORSIKA_LOG_CRITICAL("Inject and intercept points are identical.");
    return EXIT_FAILURE;
  }
  double const pnx = dx / dnorm, pny = dy / dnorm, pnz = dz / dnorm;

  DirectionVector const propDir{rootCS, {pnx, pny, pnz}};
  Point const showerCore{rootCS, cx * 1_m, cy * 1_m, cz * 1_m};
  Point const injectionPos{rootCS, injectX * 1_m, injectY * 1_m, injectZ * 1_m};

  // Shower axis: from injection through core and 20% beyond
  media::ShowerAxis const showerAxis{injectionPos, (showerCore - injectionPos) * 1.2,
                                     env};
  auto const dX = 10_g / square(1_cm);

  CORSIKA_LOG_INFO("Injection point (ECEF m): ({:.1f}, {:.1f}, {:.1f})", injectX, injectY, injectZ);
  CORSIKA_LOG_INFO("Shower core / intercept (ECEF m): ({:.1f}, {:.1f}, {:.1f})", cx, cy, cz);
  CORSIKA_LOG_INFO("Injection distance: {:.1f} km", dnorm / 1000.);
  CORSIKA_LOG_INFO("Propagation direction (ECEF): ({:.4f}, {:.4f}, {:.4f})", pnx, pny, pnz);

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

  /* === OBSERVATION MESH (absorbing: records and removes particles at valley floor) === */
  ObservationMesh<TrackingType, ParticleWriterParquet> observationLevel{
      obsMesh, 
      true,     // absorbinb
      1e-6_m,   // padding
      false,    // writeHitInfo
      true,     // recordEntry
      false,    // recordExit
    };
  output.add("particles", observationLevel);

  /* === ESCAPE PLANE (absorbing: catches particles that miss the obs mesh) === */
  ObservationPlane<TrackingType, ParticleWriterParquet> escapeLevel{
      escapePlane, escapeRefDir, true, 1e-6_m};
  output.add("escape", escapeLevel);

  PrimaryWriter<TrackingType, ParticleWriterParquet> primaryWriter(obsMesh);
  output.add("primary", primaryWriter);

  InteractionWriter<TrackingType, ParticleWriterParquet> inter_writer(showerAxis, obsMesh);
  output.add("interactions", inter_writer);

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

    // Order mirrors c8_air_shower: inspector first, thinning near end before cut
    auto fullSequence = make_sequence(stackInspect, 
                                      neutrinoPrimaryPythia, hadronSequence,
                                      decaySequence, emCascade, 
                                      // prodprof, 
                                      emContinuous,
                                      longprof, sequence,
    // trackWriter,  // uncomment together with the block above 
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

    if (!disable_interaction_hists) {
      auto const hists = heCounted.getHistogram() + leIntCounted.getHistogram();
      string const histDir = outFilename + "/interaction_hist";
      boost::filesystem::create_directories(histDir);
      save_hist(hists.labHist(),
                histDir + "/inthist_lab_" + to_string(i_shower) + ".npz", true);
      save_hist(hists.CMSHist(),
                histDir + "/inthist_cms_" + to_string(i_shower) + ".npz", true);
    }
  };

  output.startOfLibrary();
  for (int i = 1; i <= nev; ++i) {
    PowerLawDistribution<HEPEnergyType> plRng(eSlope, eMin, eMax);
    HEPEnergyType const E = (eMax == eMin)
        ? eMin
        : plRng(RNGManager<>::getInstance().getRandomStream("primary_particle"));
    auto obsMeshSequence = make_sequence(observationLevel, escapeLevel);
    runOneShower(obsMeshSequence, i, E);
  }

  output.endOfLibrary();
  return EXIT_SUCCESS;
}
