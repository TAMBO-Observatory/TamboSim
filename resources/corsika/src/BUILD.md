# Building tambo_shower against CORSIKA 8

## Prerequisites

- A built and installed CORSIKA 8 installation (see below)
- cmake 3.14+
- A C++17-capable compiler (GCC 9+ or Clang 10+)

## Step 1: Build and install CORSIKA 8

Clone the upstream repository (or use an existing local copy):

```bash
git clone https://gitlab.ikp.kit.edu/AirShowerPhysics/corsika.git corsika_upstream
cd corsika_upstream
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=$HOME/corsika-install \
         -DCMAKE_BUILD_TYPE=Release
cmake --build . -j8
cmake --install .
```

The install step places headers under `$HOME/corsika-install/include/corsika/` and
the `CORSIKA8` cmake target into `$HOME/corsika-install/lib/corsika/cmake/`.

If you are on a shared cluster (e.g. Harvard FAS RC) that memory-limits login nodes,
use `-j1` instead of `-j8`.

## Step 2: Create a CMakeLists.txt for the application

Create `CMakeLists.txt` in this directory (`resources/corsika/src/`):

```cmake
cmake_minimum_required(VERSION 3.14)
project(tambo_shower CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Point cmake to the installed CORSIKA 8 package
find_package(CORSIKA8 REQUIRED
  PATHS $ENV{HOME}/corsika-install/lib/corsika/cmake
)

add_executable(tambo_shower tambo_shower.cpp)
target_link_libraries(tambo_shower PRIVATE CORSIKA8)

# Keep rpath so the binary finds CORSIKA shared libraries at runtime
set_target_properties(tambo_shower PROPERTIES
  INSTALL_RPATH "$ORIGIN/../lib/corsika"
  BUILD_RPATH   "${CMAKE_INSTALL_PREFIX}/lib/corsika"
)
```

## Step 3: Build the application

```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release \
         -DCORSIKA8_DIR=$HOME/corsika-install/lib/corsika/cmake
cmake --build . -j4
```

## Step 4: Run

The PLY mesh files are expected to be in ECEF coordinates in metres.  Place
`injection_region_corsika.ply` and `terrain_corsika.ply` in your working
directory, or pass explicit paths:

```bash
./tambo_shower \
  -p 2212 \
  -E 1e6 \
  -z 45 \
  -a 180 \
  --obs-mesh    /path/to/injection_region_corsika.ply \
  --terrain-mesh /path/to/terrain_corsika.ply \
  --injection-distance 500000 \
  -N 10 \
  -f output_dir
```

### Key options

| Option | Description | Default |
|--------|-------------|---------|
| `-p / -Z -A` | Primary PDG code or (Z, A) | required |
| `-E` | Primary energy (GeV) | required |
| `-z` | Zenith angle in local ENU frame (deg, 0=vertical) | 0 |
| `-a` | Azimuth clockwise from North in local ENU frame (deg) | 0 |
| `--obs-mesh` | Path to observation-region PLY (ECEF m) | `injection_region_corsika.ply` |
| `--terrain-mesh` | Path to terrain PLY (ECEF m); empty/missing to disable | `terrain_corsika.ply` |
| `--injection-distance` | Distance from mesh centroid to injection point (m) | 500000 |
| `-N` | Number of showers | 1 |
| `-f` | Output directory name | required |
| `--emcut / --hadcut / --mucut / --taucut` | Energy cuts (GeV) | 1e-3 / 0.5 / 1e-3 / 1e-3 |
| `-M` | Hadronic model (SIBYLL-2.3d, QGSJet-II.04, ...) | SIBYLL-2.3d |
| `-s` | Random seed (0 = auto) | 0 |
| `--force-interaction` | Force first interaction at injection point | off |

## Coordinate system

The PLY files must be in Earth-Centered Earth-Fixed (ECEF) coordinates in
metres.  CORSIKA 8's root coordinate system is also ECEF, so vertices are
loaded directly with `scale=1_m`.

The injection geometry is computed as follows:

1. The area-weighted centroid of the observation mesh triangles is computed in
   ECEF.
2. The local ENU (East-North-Up) frame is derived at that centroid using
   spherical-Earth approximation.
3. The shower propagation direction is resolved in ECEF from the requested
   zenith and azimuth (azimuth measured clockwise from North).
4. The injection point is placed `--injection-distance` metres upstream from
   the centroid along the shower axis.

## Output

Output is written to `<filename>/` in parquet format:

- `particles/particles.parquet` — particles crossing the observation mesh
- `terrain/terrain.parquet` — particles absorbed by the terrain mesh (if loaded)
- `primary/` — primary particle record
- `energyloss/`, `profile/`, `production_profile/` — longitudinal profiles
- `interactions/` — first-interaction writer
- `interaction_hist/` — interaction histograms (numpy `.npz`)

The `particles` parquet file has columns:
`shower`, `pdg`, `kinetic_energy` (GeV), `x`, `y`, `z` (m, relative to mesh
bounding-box center), `nx`, `ny`, `nz`, `time` (s), `weight`.

## Notes on the terrain mesh

`terrain_corsika.ply` (~90k vertices, ~180k triangles) is a large mesh.
Building its BVH takes a few seconds at startup.  It is used as an absorbing
`ObservationMesh` — particles that strike the terrain are recorded in
`terrain/terrain.parquet` and removed from the simulation.  Omit
`--terrain-mesh` (or pass a non-existent path) to disable it and run faster.
