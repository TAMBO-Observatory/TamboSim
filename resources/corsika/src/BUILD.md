# Building tambo_shower against CORSIKA 8

## Prerequisites

- A built and installed CORSIKA 8 installation (see below)
- cmake 3.14+
- A C++17-capable compiler (GCC 9+ or Clang 10+)
- Conan 2 (used by CORSIKA 8 to manage dependencies)

## Step 1: Build and install CORSIKA 8

`tambo_shower` requires the `mesh-bvh-geometry-framework` branch of CORSIKA 8,
which provides `TriangularMesh`, `ObservationMesh`, and PLY mesh loading. These
features are not yet in the CORSIKA 8 mainline.

Clone the upstream repository (or use an existing local copy):

```bash
git clone --branch mesh-bvh-geometry-framework \
  https://gitlab.iap.kit.edu/AirShowerPhysics/corsika.git corsika
cd corsika
pip install conan
conan install . --output-folder=build --build=missing
cd build
cmake .. -DCMAKE_INSTALL_PREFIX=$HOME/.local \
         -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_TOOLCHAIN_FILE=conan_toolchain.cmake
cmake --build . -j8
cmake --install .
```

The install step places headers under `$HOME/.local/include/corsika/` and the
CORSIKA 8 cmake package into `$HOME/.local/lib/cmake/corsika/`.

If you are on a shared cluster (e.g. Harvard FAS RC) that memory-limits login
nodes, use `-j1` or submit the build as a job.

### Harvard FAS RC

CORSIKA 8 requires GCC 13 and cmake 3.14+, neither of which are in the default
environment.  Load them before building and running:

```bash
module load gcc/13.2.0-fasrc01 cmake/3.30.3-fasrc01
```

The Conan toolchain file at `~/corsika/build/conan_toolchain.cmake` must be
passed to cmake (see Step 2).

## Step 2: Build the application

```bash
cd resources/corsika/src
mkdir -p build && cd build
cmake .. \
  -Dcorsika_DIR=$HOME/.local/lib/cmake/corsika \
  -DCMAKE_TOOLCHAIN_FILE=$HOME/corsika/build/conan_toolchain.cmake
cmake --build . -j4
```

To build with FLUKA as the low-energy hadronic model instead of UrQMD, add
`-DWITH_FLUKA=ON` (requires FLUKA support in your CORSIKA 8 installation):

```bash
cmake .. \
  -Dcorsika_DIR=$HOME/.local/lib/cmake/corsika \
  -DCMAKE_TOOLCHAIN_FILE=$HOME/corsika/build/conan_toolchain.cmake \
  -DWITH_FLUKA=ON
```

## Step 3: Run

On Harvard FAS RC, load gcc before running:

```bash
module load gcc/13.2.0-fasrc01
```

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
  --obs-mesh    /path/to/injection_region_corsika.ply \
  --terrain-mesh /path/to/terrain_corsika.ply \
  -f output_dir
```

In normal use the injection and intercept coordinates are computed by the Julia
`corsika_run(particle, earth, ...)` wrapper, which traces the particle trajectory
to the detector region of the `Earth` struct and converts both endpoints to ECEF.

The PLY mesh files (`injection_region_corsika.ply`, `terrain_corsika.ply`) are
in `resources/` in this repository.

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

`terrain_corsika.ply` (~90k vertices, ~180k triangles) is a large mesh. Building
its BVH takes a few seconds at startup. It is used as an absorbing
`ObservationMesh` — particles that strike the terrain are recorded in
`terrain/` and removed from the simulation. Omit `--terrain-mesh` to disable it
and run faster.
