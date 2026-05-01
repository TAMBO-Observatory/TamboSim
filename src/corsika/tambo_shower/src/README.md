# Building tambo_shower against CORSIKA 8

## Step 1: Build and install CORSIKA 8

> **On Harvard FAS RC**: a shared CORSIKA install already lives at
> `/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika`.
> Unless you are actively developing CORSIKA itself, skip this step and link
> `tambo_shower` against it per the on-cluster README at
> `/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/README.md`,
> then continue with Step 3 below.

`tambo_shower` requires the `mesh-bvh-geometry-framework` branch of CORSIKA 8
developed by Jeff Lazar, which provides `TriangularMesh`, `ObservationMesh`,
and PLY mesh loading. These features are not yet in the CORSIKA 8 mainline.

The general instructions for installing CORSIKA 8 [can be found here](https://gitlab.iap.kit.edu/AirShowerPhysics/corsika);
the steps below are based on that resource and use CORSIKA 8's own
`conan-install.sh` and `corsika-cmake.sh` wrappers.

1. Clone the `mesh-bvh-geometry-framework` branch of CORSIKA:
    ```shell
    git clone --recursive --branch mesh-bvh-geometry-framework \
      https://gitlab.iap.kit.edu/AirShowerPhysics/corsika.git corsika
    ```

2. CORSIKA uses Conan to manage its C++ dependencies, so you will need to
   install Conan via python. If you don't already have a copy of Conan, we
   suggest setting up a dedicated python virtual environment and installing
   via pip.

3. Optionally, ensure you have a copy of FLUKA, which is one of two packages
   that can be used for the low-energy hadronic interactions in CORSIKA. FLUKA
   is not strictly required, but it is significantly faster than the
   alternative. To install FLUKA, register for an account [on the FLUKA
   website](http://www.fluka.eu/Fluka/www/html/fluka.php?). To then compile
   CORSIKA with FLUKA, provide the runtime environment variables `FLUPRO`,
   pointing to the directory containing the executable `flupro`, and `FLUFOR`,
   pointing to the fortran executable used to compile FLUKA.

4. Use Conan to install and precompile all the C++ packages CORSIKA depends on:
    ```shell
    mkdir -p "${CORSIKA_PREFIX}/corsika-build"
    cd "${CORSIKA_PREFIX}/corsika-build"

    # 4a: install conan dependencies (generates conan_cmake/ with conan_toolchain.cmake)
    ../corsika/conan-install.sh --source-directory ../corsika --release-with-debug

    # 4b: configure (conan-install.sh generates corsika-cmake.sh in the corsika/ dir)
    ../corsika/corsika-cmake.sh -c "-DWITH_FLUKA=ON -DCMAKE_INSTALL_PREFIX=../corsika-install"
    ```

5. Compile and install CORSIKA:
    ```shell
    make -j4
    make install
    ```
    The install step places headers under `${CORSIKA_PREFIX}/corsika-install/include/corsika/`
    and the CORSIKA 8 cmake package under `${CORSIKA_PREFIX}/corsika-install/lib/cmake/corsika/`.
    On any shared cluster with memory-limited login nodes, use `-j1` or submit
    the build as a job.

## Step 2: Build the application

Given a TamboSim checkout at `TAMBOSIM_DIR`, the following commands compile
`${TAMBOSIM_DIR}/src/corsika/tambo_shower/src/tambo_shower.cpp` against the
CORSIKA 8 installation produced in Step 1:

```bash
export CONAN_DEPENDENCIES=${CORSIKA_PREFIX}/corsika-install/lib/cmake/dependencies

cd "${TAMBOSIM_DIR}/src/corsika/tambo_shower/src/"
mkdir -p build

cmake -DCMAKE_TOOLCHAIN_FILE=${CONAN_DEPENDENCIES}/conan_toolchain.cmake \
      -DCMAKE_PREFIX_PATH=${CONAN_DEPENDENCIES} \
      -Dcorsika_DIR=${CORSIKA_PREFIX}/corsika-install/lib/cmake/corsika \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DWITH_FLUKA=ON \
      -S . \
      -B build

cmake --build build
```

Drop `-DWITH_FLUKA=ON` if you compiled CORSIKA without FLUKA support. With
FLUKA, `FLUPRO` and `FLUFOR` must be set in the environment at compile time
(see Step 1.3). The resulting binary is `build/tambo_shower`.

The `CMakeLists.txt` automatically detects the GCC runtime library directory
from `${CMAKE_CXX_COMPILER}` and embeds it as an RPATH, so the binary runs
without loading any compiler module at runtime.

## Step 3: Run

The injection trajectory is specified by two ECEF points: the injection point
(upstream, e.g. at ~112 km altitude) and the intercept on the observation mesh.
Both are provided in metres.

A proton shower at 10^8 GeV injected from directly above the detector:

```bash
./tambo_shower \
  -Z 1 -A 1 \
  -E 1e8 \
  --inject-x    1234567.0 \
  --inject-y    -5678901.0 \
  --inject-z    2345678.0 \
  --intercept-x 1234500.0 \
  --intercept-y -5678800.0 \
  --intercept-z 2345500.0 \
  --obs-mesh    /path/to/colca_valley_obs_surface.ply \
  --terrain-mesh /path/to/colca_valley_terrain.ply \
  -f output_dir
```

In normal use the injection and intercept coordinates are computed by the Julia
`corsika_run(particle, topography, detector_region, ...)` wrapper, which
intersects the particle trajectory with the triangulated detector region and
converts both endpoints to ECEF.

The PLY mesh files (`colca_valley_obs_surface.ply`, `colca_valley_terrain.ply`) are
in `resources/geometry/` in this repository.

**Note:** the output directory must not already exist. Remove it before re-running:
```bash
rm -rf output_dir
```

### Key options

| Option | Description | Default |
|--------|-------------|---------|
| `-Z -A` | Atomic number and mass of primary | required (or `--pdg`) |
| `-p,--pdg` | Primary PDG code (e.g. 2212=proton, 22=gamma) | required (or `-Z -A`) |
| `-E` | Primary energy (GeV) | required |
| `--inject-x/y/z` | Injection point in ECEF metres | required |
| `--intercept-x/y/z` | Shower-core intercept on detection region in ECEF metres | required |
| `--obs-mesh` | Path to observation-region PLY (ECEF m) | required |
| `--terrain-mesh` | Path to terrain PLY (ECEF m); omit to disable | (disabled) |
| `-N` | Number of showers | 1 |
| `-f` | Output directory name (must not exist) | required |
| `--emcut` | Min kinetic energy of photons/electrons/positrons (GeV) | 10 |
| `--hadcut` | Min kinetic energy of hadrons (GeV) | 1 |
| `--mucut` | Min kinetic energy of muons (GeV) | 10 |
| `--taucut` | Min kinetic energy of tau leptons (GeV) | 10 |
| `-M` | High-energy hadronic model (SIBYLL-2.3d, QGSJet-II.04, QGSJet-III, EPOS-LHC, EPOS-LHC-R, Pythia8) | SIBYLL-2.3d |
| `-s` | Random seed (0 = auto) | 0 |
| `--force-interaction` | Force first interaction at injection point | off |

## Coordinate system

The PLY files and the `--inject-x/y/z` / `--intercept-x/y/z` values must all be
in Earth-Centered Earth-Fixed (ECEF) coordinates in metres. CORSIKA 8's root
coordinate system is also ECEF, so vertices are loaded directly with `scale=1_m`.

The injection geometry is computed as follows:

1. The area-weighted centroid of the observation mesh triangles is computed in ECEF.
2. The local ENU (East-North-Up) frame is derived at that centroid.
3. The shower propagation direction is resolved in ECEF from the requested zenith
   and azimuth (azimuth measured clockwise from North).
4. The injection point is the intersection of the upstream ray from the centroid
   with the sphere at Earth radius + `--injection-altitude`.

## Output

Output is written to `<filename>/` in Parquet format:

- `particles/` — particles crossing the observation mesh
- `terrain/` — particles absorbed by the terrain mesh (if loaded)
- `escape/` — particles that exit below the observation mesh without hitting it
- `primary/` — primary particle record
- `energyloss/`, `profile/`, `production_profile/` — longitudinal profiles
- `interactions/` — first-interaction record
- `interaction_hist/` — per-shower interaction histograms (numpy `.npz`)

## Notes on the terrain mesh

`colca_valley_terrain.ply` (~90k vertices, ~180k triangles) is a large mesh. Building
its BVH takes a few seconds at startup. It is used as an absorbing
`ObservationMesh` — particles that strike the terrain are recorded in
`terrain/` and removed from the simulation. Omit `--terrain-mesh` to disable it
and run faster.
