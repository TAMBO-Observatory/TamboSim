
# Hola y bienvenidos!

Welcome to TamboSim! This is the main simulation code for the TamboSim Collaboration, and is (thus far) capable of:
- Injecting (and forcing the interaction of) neutrinos, protons, in a realistic canyon geometry
- Propagating charged leptonic secondaries through rock and air with PROPOSAL,
- Passing particles to CORSIKA to simulate air shower propagation in a realistic canyon topography,
- Aggregating CORSIKA hits on smaller detection units placed on that surface.

The entire codebase has been designed to use triangulated mesh parameterizations of the local topography. By default, TamboSim ships with the topography of the Colca Canyon in Peru; there are instructions in the examples on how to substitute alternate topographies.

We welcome new users of TamboSim! If you have any questions or concerns, please feel free to create an [issue in the GitHub repo](https://github.com/Harvard-Neutrino/TAMBO-MC/issues). You should also feel free to email the developers, [Jeff Lazar](mailto:jlazar@icecube.wisc.edu) and [Will Thompson](mailto:will_thompson@g.harvard.edu). Finally, if you feel up to it, you can also fork this repo, make the change, and initiate a pull request yourself. `:-)`

## Basics

The output of any stage of TamboSim simulation is a `TamboSim.TamboFrames` collection — a vector of `TamboSim.Frame` objects representing the events and their per-stage metadata. A Frame is a hierarchical, dictionary-like container that stores simulation data and can reference parent Frames, enabling transparent key lookup up the chain across processing stages. Frames are organized into streams (`G` geometry → `C` detector configuration → `D` detector layout → `M` simulation metadata → `Q` per-event → `P` per-particle), and the Frame objects implemented here are inspired by the similar data structures used in the IceTray software of the IceCube Collaboration.

`TamboFrames` are stored in `.jld2` files written in the native Julia binary format [`JLD2`](https://juliapackages.com/p/jld2), and `load_frames` reconstructs the parent chain from stream order on read. For example:
```julia
julia> using TamboSim

julia> frames = load_frames("examples/resources/example_output.jld2")
TamboFrames (1 M, 29 Q)
└─ M → Q × 29
```
The header line summarizes per-stream counts; the tree below shows the parent/child structure, with long runs of single-child stream collapsed into a horizontal `A → B × N` chain. Each stream is also exposed as a property on the collection — `frames.m_frames`, `frames.q_frames`, etc. — for direct access:
```julia
julia> qf = frames.q_frames[1]
Frame (stream='Q', parents: M)
  keys (9):
    event_id
    injection_close_state
    injection_final_state
    injection_initial_state
    proposal_continuous_losses
    proposal_decay_products
    proposal_final_state
    proposal_stochastic_losses
    weight_params

julia> frames.m_frames[1]
Frame (stream='M', no parents)
  keys (2):
    injection
    proposal
```
The simulation's configuration lives on the `M` frame under the `injection`, `proposal`, and (where applicable) `corsika` keys; per-event payloads live on the `Q` frame and inherit from `M` via the parent chain, so `qf["injection"]` resolves up to the M-frame configuration without the user having to walk the hierarchy.

For a guided tour of `TamboFrames` and the rest of the simulation framework, see [`examples/`](examples/).

## Related Packages
- [TAMBOSim-pipeline](https://github.com/TAMBO-Observatory/TAMBOSim-pipeline): Scripts for mass producing simulation, for the TamboSim Collaboration.
- [TamboMakie](https://github.com/TAMBO-Observatory/TamboMakie.jl): Plotting and visualization software, built on top of TamboSim.

## Getting Started

### [0] Jump into Julia
TamboSim is written in Julia, a high-performance numerical computing language which blends the user-friendly syntax of Python with the performance of C++. To install Julia and learn more about the language, see [the JuliaLang website](https://julialang.org/downloads/).

### [1] Installing TamboSim
Once you have downloaded Julia, TamboSim can be installed by simply git cloning this repository and then instantiating the package in Julia:
```shell
git clone git@github.com:TAMBO-Observatory/TAMBOSim.git
julia
```

```julia
julia> using Pkg

julia> Pkg.activate("TamboSim")

julia> Pkg.resolve()
    Project No packages added to or removed from `/n/holylfs05/LABS/arguelles_delgado_lab/Users/kcarloni/research_projects/tambo/TamboSim_mesh/Project.toml`
    
julia> Pkg.instantiate()
```
Warning: Julia's package manager can be slow on distributed filesystems, such as Harvard's FASRC cluster. It may take a while for Julia to start up for the first time, for packages to download, and for packages to precompile for the first time. Some patience is needed.

To use TamboSim as a base package for analysis and plotting, e.g. using TamboMakie, no further steps are needed. If you wish to generate air shower simulations using TamboSim, you need to proceed to the next step: 

### [2] Installing and compiling CORSIKA 

TamboSim relies on the new C++ implementation of the CORSIKA software, [CORSIKA 8](https://corsika-8.readthedocs.io/en/latest/), for simulating the extensive air showers produced by charged particle interactions in air. In order to run the final steps of the simulation code, you will need to install and compile CORSIKA.

In particular, TamboSim requires the `mesh-bvh-geometry-framework` branch of CORSIKA 8 developed by Jeff Lazar, which has added functionality that allows for simulating air shower development near complex 3D terrain environments. For more information, see section 2.2.1 of the recent CORSIKA 8 publication, [CORSIKA 8: A General Framework for Particle Cascade Simulations](https://arxiv.org/abs/2604.01850). 

Since running CORSIKA is fairly computationally expensive, it typically makes sense only to install and compile CORSIKA on a high-performance distributed computing cluster, e.g. [Harvard's FASRC](https://www.rc.fas.harvard.edu). 
Additionally, if you plan on using Harvard's research computing cluster and are not planning on actively developing or debugging CORSIKA, it likely makes sense to just link against our shared CORSIKA installation. Instructions in this scenario are described in **Section 2A** below. 

Otherwise, if you *are* interested in installing CORSIKA for yourself, you should follow the general instructions in **Section 2B** below.

#### [2A] Compiling the `tambo_shower` executable on Harvard's FASRC

The shared CORSIKA installation on the Harvard research computing cluster can be found here:
```
/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika
```
[Kiara Carloni](mailto:kcarloni@g.harvard.edu) and [Will Thompson](mailto:will_thompson@g.harvard.edu) are responsible for maintaining this shared resource; if you run into any issues, please contact them. 

Your final step before running your own simulations is to compile your copy of TamboSim's `tambo_shower` executable. The source code for this ships natively with TAMBOSim and can be found at `TAMBOSim/src/corsika/corsika_cpp/src/tambo_shower.cpp`. Instructions for compiling this against the provided CORSIKA library can be found in this README: 
```
/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/README.md
```

#### [2B] Installing and compiling your own copy of CORSIKA.  

The general instructions for installing CORSIKA-8 [can be found here](https://gitlab.iap.kit.edu/AirShowerPhysics/corsika). The instructions below are based on this resource. 

1. As a first step, you will need to clone the `mesh` branch CORSIKA:
```shell
git clone --recursive --branch mesh-bvh-geometry-framework \
  https://gitlab.iap.kit.edu/AirShowerPhysics/corsika.git corsika
```

2. CORSIKA uses Conan to manage its C++ dependencies, so you will need to install Conan via python. If you don't already have a copy of Conan, we suggest setting up a dedicated python virtual environment and installing via pip.

3. Optionally, you should ensure you have a copy of FLUKA, which is one of two packages that can be used for the low energy hadronic interactions in CORSIKA. FLUKA is not strictly required, but it is significantly faster than the alternative. To install FLUKA, you will need to register for an account [on the FLUKA website](http://www.fluka.eu/Fluka/www/html/fluka.php?). To then compile CORSIKA with FLUKA, you simply need to provide the runtime environment variables `FLUPRO`, which points to the directory containing the executable `flupro`, and `FLUFOR`, which points to the fortran executable used to compile FLUKA.

4. Next step is to use Conan to install and precompile all the C++ packages CORSIKA depends on. This looks something like the following: 
```shell
mkdir -p "${CORSIKA_PREFIX}/corsika-build"
cd "${CORSIKA_PREFIX}/corsika-build"

# Step 1a: install conan dependencies (generates conan_cmake/ with conan_toolchain.cmake)
 ../corsika/conan-install.sh --source-directory ../corsika --release-with-debug

# Step 1b: configure (conan-install.sh generates corsika-cmake.sh in the corsika/ dir)
../corsika/corsika-cmake.sh -c "-DWITH_FLUKA=ON -DCMAKE_INSTALL_PREFIX=../corsika-install"
```

5. Final step is to actually compile CORSIKA:
```shell
make -j4
make install
```

### [3] Examples
Example uses of `TamboSim` can be found in the `examples/` directory. 

If you are a member of the TAMBO Collaboration and interested in producing *lots* of simulation, you should look at the related package [TAMBOSim-pipeline](https://github.com/TAMBO-Observatory/TAMBOSim-pipeline).

## Citation
Tell people how to cite us.

