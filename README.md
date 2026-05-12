
# Hola y bienvenidos!

Welcome to TamboSim! This is the main simulation code for the TamboSim Collaboration, and is (thus far) capable of:
- Injecting (and forcing the interaction of) neutrinos, protons, in a realistic canyon geometry
- Propagating charged leptonic secondaries through rock and air with PROPOSAL,
- Passing particles to CORSIKA to simulate air shower propagation in a realistic canyon topography,
- Aggregating CORSIKA hits on smaller detection units placed on that surface.

The entire codebase has been designed to use triangulated mesh parameterizations of the local topography. By default, TamboSim ships with the topography of the Colca Canyon in Peru; there are instructions in the examples on how to substitute alternate topographies.

We welcome new users of TamboSim! If you have any questions or concerns, please feel free to create an [issue in the GitHub repo](https://github.com/TAMBO-Observatory/TAMBOSim/issues). You should also feel free to email the developers, [Jeff Lazar](mailto:jlazar@icecube.wisc.edu) and [Will Thompson](mailto:will_thompson@g.harvard.edu). Finally, if you feel up to it, you can also fork this repo, make the change, and initiate a pull request yourself. `:-)`

## Basics

The output of any stage of TamboSim simulation is a `TamboSim.TamboFrames` collection — a vector of `TamboSim.Frame` objects representing the events and their per-stage metadata. A Frame is a hierarchical, dictionary-like container that stores simulation data and can reference parent Frames, enabling transparent key lookup up the chain across processing stages. Frames are organized into streams (`G` geometry → `C` detector configuration → `D` detector layout → `M` simulation metadata → `Q` per-event → `R` reconstructed), and the Frame objects implemented here are inspired by the similar data structures used in the IceTray software of the IceCube Collaboration.

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
    phase_space_point
    proposal_continuous_losses
    proposal_decay_products
    proposal_final_state
    proposal_stochastic_losses

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
cd TAMBOSim
julia
```

```julia
julia> using Pkg

julia> Pkg.activate(".")

julia> Pkg.resolve()
    No packages added to or removed from `~/TAMBOSim/Project.toml`

julia> Pkg.instantiate()
```
Warning: Julia's package manager can be slow on distributed filesystems, such as Harvard's FASRC cluster. It may take a while for Julia to start up for the first time, for packages to download, and for packages to precompile for the first time. Some patience is needed.

To use TamboSim as a base package for analysis and plotting, e.g. using TamboMakie, no further steps are needed. If you wish to generate air shower simulations using TamboSim, you need to proceed to the next step: 

### [2] Installing and compiling CORSIKA

TamboSim relies on the C++ implementation [CORSIKA 8](https://corsika-8.readthedocs.io/en/latest/) for simulating the extensive air showers produced by charged particles in air. Specifically, you will need the `mesh-bvh-geometry-framework` branch of CORSIKA 8 developed by Jeff Lazar, which adds functionality for simulating air shower development over complex 3D terrain (see section 2.2.1 of the [CORSIKA 8 publication](https://arxiv.org/abs/2604.01850)). On top of that, you will need to build TamboSim's own `tambo_shower` executable, whose source ships in this repo at [`src/corsika/tambo_shower/src/`](src/corsika/tambo_shower/src/).

Running CORSIKA is computationally expensive, so it typically only makes sense to install on a high-performance computing cluster, e.g. [Harvard's FASRC](https://www.rc.fas.harvard.edu). Two paths:

- **On FASRC, linking against the shared install** (recommended unless you are actively developing CORSIKA itself). The shared CORSIKA installation maintained by [Kiara Carloni](mailto:kcarloni@g.harvard.edu) and [Will Thompson](mailto:will_thompson@g.harvard.edu) lives at
    ```
    /n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika
    ```
    Build only `tambo_shower` against it; instructions are in the on-cluster README at
    ```
    /n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/README.md
    ```
    Please reach out to Kiara or Will if you run into any issues with the shared install.

- **Building CORSIKA yourself, anywhere else.** The full step-by-step — CORSIKA 8 install, `tambo_shower` build, run, and CLI reference — lives in [`src/corsika/tambo_shower/src/README.md`](src/corsika/tambo_shower/src/README.md).

### [3] Examples
Example uses of `TamboSim` can be found in the `examples/` directory. 

If you are a member of the TAMBO Collaboration and interested in producing *lots* of simulation, you should look at the related package [TAMBOSim-pipeline](https://github.com/TAMBO-Observatory/TAMBOSim-pipeline).

## Citation
Tell people how to cite us.

