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
  --obs-mesh    /path/to/obs_surface.ply \
  --terrain-mesh /path/to/terrain.ply \
  --site-file   ../../../../resources/sites/colca.toml \
  -f output_dir
```

`--site-file` is required and has no default: the file it names supplies both
the atmosphere layer profile and the geomagnetic field, which are physically
tied to a location. Nothing about a site is compiled in, so **adding or editing
a site needs no rebuild** — write a TOML file.

The schema, and the two shipped sites (`colca` — the TAMBO site in the Colca
Valley; `lima` — the TAMBO-4 Lima validation site), are documented in
[`resources/sites/README.md`](../../../../resources/sites/README.md). In brief:

```toml
[geomagnetic_field]
east_uT = -2.5; north_uT = 22.9; up_uT = 3.7   # local ENU, positive up

[[atmosphere.layer]]                            # innermost first,
type = "exponential"                            # strictly increasing altitude
top_altitude_km = 3.8
offset_g_cm2    = 1208.0663
scale_height_cm = 1045629.03
```

Any number of layers is supported, in any mix of `"exponential"` and
`"linear"` (constant-density) profiles — the familiar "4 exponential + 1
linear" shape is the CORSIKA 7 preset convention, not a limit. Unknown keys are
rejected so a typo cannot silently change the atmosphere, and the run is
refused if the outermost layer does not enclose the injection point.

From the Julia side, `[corsika] site_file` gives the path (absolute, or
relative to the package root); it is checked by `TamboSim.site_file_path` in
`src/corsika/run_corsika.jl` before the binary is spawned. For provenance the
resolved file is copied into the run's output directory as `site.toml`, since
`config.yaml` records only the argv string and so pins the path rather than the
contents.

In normal use the injection and intercept coordinates are computed by the Julia
`corsika_run!` orchestrator (`src/corsika/run_corsika.jl`): `plan_corsika_jobs`
intersects each particle trajectory with the triangulated detector region, and
`build_corsika_argv` converts both endpoints to ECEF metres for the CLI. The
orchestrator also generates the PLY mesh files from the JLD2 GCD bundle at run
time, so no prebuilt PLYs are shipped.

**Note:** the output directory must not already exist. Remove it before re-running:
```bash
rm -rf output_dir
```

### Key options

| Option | Description | Default |
|--------|-------------|---------|
| `-Z -A` | Atomic number and mass of primary | required (or `--pdg`) |
| `-p,--pdg` | Primary PDG code (e.g. 2212=proton, 22=gamma) | required (or `-Z -A`) |
| `-E,--energy` | Primary energy (GeV) | required (or `--energy_range`) |
| `--inject-x/y/z` | Injection point in ECEF metres | required |
| `--intercept-x/y/z` | Shower-core intercept on detection region in ECEF metres | required |
| `--obs-mesh` | Path to observation-region PLY (ECEF m) | required |
| `--site-file` | Path to a site TOML: atmosphere layers + geomagnetic field (see `resources/sites/`) | required |
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

The injection point (`--inject-x/y/z`) and the shower-core intercept
(`--intercept-x/y/z`) are supplied directly on the command line in ECEF
metres — the binary does not compute them. The shower propagation direction
is the normalized vector from the injection point to the intercept, and a
local ENU (East-North-Up) frame is derived at the intercept to orient the
geomagnetic field.

In normal use both points come from the Julia `corsika_run!` orchestrator
(see Step 3).

## Output

Output is written to `<filename>/`, one subdirectory per writer:

- `particles/` — particles crossing the observation mesh (`particles.parquet`)
- `profile/` — longitudinal shower profile (`profile.parquet`)
- `energyloss/` — longitudinal energy-deposit profile (`dEdX.parquet`)
- `interactions/` — first-interaction secondaries (`interactions.parquet`)
- `primary/` — primary-particle record (`summary.yaml` only; this writer
  emits no parquet)

A top-level `config.yaml` (run configuration), `summary.yaml` (shower count,
seed, timing) and `site.toml` (a copy of the `--site-file` input) are written
alongside the subdirectories.

## Notes on the terrain mesh

The terrain mesh can be large (~90k vertices, ~180k triangles for the Colca
Valley site); building its BVH takes a few seconds at startup. It is
registered as a `HomogeneousMedium` standard-rock volume (2.65 g/cm³):
particles propagate *through* it with rock physics rather than being absorbed
at the surface, and no readout is attached. Dedicated boundary-crossing
processes — `RockExitRelocator`, `RockEMAbsorber`, `RockInterfaceTripwire` —
handle the rock/air interface. Omit `--terrain-mesh` to disable the rock
volume.