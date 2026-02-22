# Hola y bienvenidos.
Welcome to TAMBOSim! This quickstart guide will show you how to install TAMBOSim and run your first TAMBO simulation. Some of the functions and utilities we will go over have docstrings in the code, but many others do not. With that in mind, if things don't work, or there is a change you would like to see, or something is just annoying but you don't know what the fix would look like, please feel free to create an [issue in the GitHub repo](https://github.com/Harvard-Neutrino/TAMBO-MC/issues). You should also feel free to email [Jeff Lazar](mailto:jlazar@icecube.wisc.edu) or [Will Thompson](mailto:will_thompson@g.harvard.edu). If you feel up to it, you can fork this repo, make the change, and initiate a pull request yourself.

Lastly, please don’t hesitate to get in contact with us if you run into any problems along the way. We’d love to help you get your simulation running.

Alright, let's get things moving!

## [0] Prerequisites
### [0.1] Jump into Julia
The code reies mostly on the Julia language so you will need to install that. This was developed using Julia version 1.11. Get that one if you can, but more recent versions should work fine. You can find instructions for installing Julia [here](https://julialang.org/install/). 

If you are new to Julia, it’s borderline life-changing, but there are definitely some differences from Python. To run the code, you won't need anything advanced, but it might be good to dip you toes into some of the basics. When I started with Julia, I had a decent handle on Python, and I used [these resources](https://github.com/JuliaAcademy/JuliaTutorials) to fill in the gaps. There were still some growing pains, but I felt it gave me enough information to get started. The Julia manual also has a dedicated page on
[difference from Python](https://docs.julialang.org/en/v1/manual/noteworthy-differences/#Noteworthy-differences-from-Python).

Also, I highly recommend joining the [Julia Slack](https://julialang.org/slack/). It is very active, and everyone there is extremely helpful. 

### [0.2] CORSIKA 8
TAMBOSim also relies on the new C++ implementation of CORSIKA, CORSIKA 8. We assume here that you have installed and built CORSIKA 8; you can find instructions for doing so [here](https://gitlab.iap.kit.edu/AirShowerPhysics/corsika).

## [1] Installing Dependencies
The physics of TAMBOSim relies primarily on three external software packages: PROPOSAL, TauRunner, and CORSIKA. PROPOSAL and TauRunner have native Julia implementations. CORSIKA is written in C++ and TAMBOSim interfaces directly with its executable.

Neither [PROPOSAL.jl](https://github.com/jlazar17/PROPOSAL.jl) nor [TauRunner.jl](https://github.com/icecube/TauRunner) are registered in the Julia General registry, but both are fetched automatically from their git repositories when you run `Pkg.instantiate()`. Their native library binaries are distributed as [JLL packages](https://docs.binarybuilder.org/stable/jll/), so no C++ compiler or system libraries are required.

### [1.1] Prerequisites

You will need:
- Julia 1.11+ (see section [0.1])

### [1.2] PROPOSAL.jl

[PROPOSAL.jl](https://github.com/jlazar17/PROPOSAL.jl) provides native Julia bindings for the [PROPOSAL](https://github.com/tudo-astroparticlephysics/PROPOSAL) C++ charged lepton propagation library. The pre-built native library (`PROPOSAL_jll v7.6.2+1`) is downloaded automatically during `Pkg.instantiate()`. No manual cloning or compilation is required.

### [1.3] TauRunner.jl

[TauRunner.jl](https://github.com/icecube/TauRunner) is used to propagate high-energy tau neutrinos through the Earth, taking into account the effects of [tau regeneration](https://doi.org/10.48550/arXiv.hep-ph/9804354). It is also fetched automatically during `Pkg.instantiate()`. No manual cloning is required.

### [1.4] CORSIKA TAMBO application
In addition to building and installing CORISKA8, you will need to build the specific CORSIKA application that is used to simulate air showers in TAMBOSim. This ships with TAMBOSim, so go ahead and clone this repo. Next, navigate to `/path/to/TAMBOSim/src/corsika/`. In this directory, execute the following:
```
mkdir build

export CORSIKA_PREFIX=/path/to/corsika8/top/level/directory
export CONAN_DEPENDENCIES=${CORSIKA_PREFIX}/corsika-install/lib/cmake/dependencies
export FLUPRO=/path/to/fluka/top/level/directory
export FLUFOR=<name of FORTRAN you built CORSIKA against, like gfortran>
export WITH_FLUKA=ON

cmake -DCMAKE_TOOLCHAIN_FILE=${CONAN_DEPENDENCIES}/conan_toolchain.cmake \
    -DCMAKE_PREFIX_PATH=${CONAN_DEPENDENCIES} \
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -Dcorsika_DIR=${CORSIKA_PREFIX}/corsika-build \
    -DWITH_FLUKA=ON \
    -S $PWD/source \
    -B $PWD/build

cd build
make
```
This will build our CORSIKA executable, named `c8_air_shower`.

## 2. Setting up the Julia environment
### [2.1] Configuring Your Environment
After installing the required packages as described above, we now need to configure your environment.

You should define environmental variables that specify where `TAMBOSim` is installed and where your top-level data directory for all `TAMBOSim` simulations is located. In a shell, run
```
export TAMBOSIM_PATH=/path/to/TAMBOSim
export TAMBO_DATA_PATH=/path/to/data
```
We also need to tell `TAMBOSim` where to find `CORSIKA` and files needed by `CORSIKA`. This information is handled within a simulation configuration file. Open up the config file at `$TAMBOSIM_PATH/resources/configuration_examples/fast_test.toml` and edit
* `FLUPRO` to point to the version of `FLUKA` for `CORSIKA` to use
* `FLUFOR` to point to the version of `FORTRAN` used by `FLUKA`

### [2.2] Precompile `TAMBOSim`
Now that our dependencies are ready, we'll set up the Julia TAMBOSim package. Install and precompile everything with:
```bash
julia --project=$TAMBOSIM_PATH -e 'import Pkg; Pkg.instantiate()'
```

This will automatically fetch PROPOSAL.jl and TauRunner.jl from their git repositories and download the pre-built PROPOSAL_jll binary. No manual cloning or path editing is needed.

To use `TAMBOSim` run:
```julia-repl
julia> using Tambo
```

### [2.3] Snakemake
Lastly, we will install Snakemake. While all the elements in the TAMBOSim chain can be run manually, it also supports the use of Snakemake. Install Snakemake and some other needed packages by running `pip install snakemake toml h5py snakemake-executor-plugin-slurm`.

## 3. Running the Code
### [3.1] Let’s Simulate Some Events
Several examples on how to use `TAMBOSim` can be found in the `examples/` directory. For now, we will run a simulation that passes through the whole simulation chain to ensure everything is running properly.

`TAMBOSim` makes use of the `Snakemake` workflow management system. More details on `Snakemake` can be found [here](https://snakemake.github.io). By default, `TAMBOSim` will output the results of the simulation to a directory with the name of the config file in the `TAMBO_DATA_PATH` directory. For example, the name of the config file we will use here is `fast_test.toml`, so the output files will be written to `TAMBO_DATA_PATH/fast_test/`. Go ahead and create and change to this directory, creating it if needed.

To do a full run of `TAMBOSim`, execute `snakemake -p --cores 1 -s $TAMBOSIM_PATH/scripts/Snakefile $TAMBO_DATA_PATH/fast_test/triggered/2300_3700_5000_150_small/whitepaper_trigger/triggered_events_00000.jld2`. Feel free to change the number of cores to suit your machine. This will launch the full simulation chain, where `TAMBOSim` will:
* Inject tau neutrinos into the simulation volume using `TauRunner` and compute the location of the associated tau lepton decay with `PROPOSAL`
* Simulate the tau-induced air shower using `CORSIKA`
* Identify events that trigger the detector array
If all has worked as expected, Snakemake will issue you a success message and the final triggered event file will be produced.

If you run into any problems along the way, please don’t hesitate to get in contact with us. We’d love to help you get your simulation running.

### [3.2] Simulating a Lot of Events
By default, `Snakemake` can be used to generate a `TAMBOSim`  dataset in parallel on a cluster with minimal alterations to the above procedure. All you need to do is to open up the Snakefile at `$TAMBOSIM_PATH/scripts/Snakefile` and change the variable `slurm_partition` to a comma-separated list of the slurm partitions you’d like to run the simulation on. Then, simply run `snakemake -p --executor slurm --jobs N -s $TAMBOSIM_PATH/scripts/Snakefile $TAMBO_DATA_PATH/fast_test/triggered/2300_3700_5000_150_small/whitepaper_trigger/triggered_events_00000.jld2`, where `N` is the maximum number of slurm jobs to run in parallel.

###	[3.3] Changing the Simulation Configuration
Several example configuration files are provided in `resources/configuration_examples/`, including both realistic and idealized valley geometries. If you’d like to run a simulation with a different configuration, copy the configuration file into a new file, e.g. `my_configuration.toml` and alter the parameters as you see fit. Then, you can run your new simulation by running `snakemake -p --executor slurm --jobs N -s $TAMBOSIM_PATH/scripts/Snakefile $TAMBO_DATA_PATH/my_configuration/triggered/2300_3700_5000_150_small/whitepaper_trigger/triggered_events_00000.jld2`.
Notice that the way Snakemake figures out what config file to used is based on the name of output data directory you specify, so this should match the name of your configuration file.

Would you like to simulate your own custom geometry? We’re working on a script to allow a user to create custom geographies, but it’s still in the works. For now, email  [Will Thompson](mailto:will_thompson@g.harvard.edu) and he’ll be able to spin up a spline for you to use.

## Citation
Tell people how to cite us.


## 4. Troubleshooting

This section documents common issues encountered during installation and their solutions.

### [4.1] Running Examples from the `examples/` Directory

**Symptom:** Running examples fails with:
```
ERROR: package `Tambo` has the same name or UUID as the active project
```

**Cause:** The example scripts contain `Pkg.develop(path=tambo_path)` which conflicts when run from within the TAMBO-MC directory.

**Solution:** The examples directory has its own `Project.toml` that references the Tambo package. To run examples:

1. Update `examples/Project.toml` to point to your TAMBO-MC installation:
   ```toml
   [sources]
   Tambo = {path = "/your/path/to/TAMBO-MC/"}
   ```

2. Run examples from the `examples/` directory:
   ```bash
   cd /path/to/TAMBO-MC/examples
   julia -e 'using Pkg; Pkg.activate("."); Pkg.instantiate()'
   ```

3. When running example scripts, you can skip the `Pkg.develop()` line since the source is already configured in `Project.toml`:
   ```julia
   export TAMBOSIM_PATH=/path/to/TAMBO-MC
   cd /path/to/TAMBO-MC/examples
   julia -e '
   tambo_path = ENV["TAMBOSIM_PATH"]
   import Pkg
   Pkg.activate(".")
   # Skip Pkg.develop since source is in Project.toml
   using JLD2
   using Tambo
   # ... rest of script
   '
   ```

### [4.2] PROPOSAL Warnings During Lepton Propagation

**Symptom:** When running `lepton_propagation.jl`, you see many warnings like:
```
[warning] Negative dNdx value for E = X.XXX MeV, vbar = 1.0000 detected in interaction type Ioniz. Setting dNdx to zero.
```

**Cause:** These are normal numerical warnings from the PROPOSAL library at very low energies.

**Solution:** These warnings can be safely ignored. They do not affect the simulation results. The simulation may take significant time due to the physics calculations involved.

### [4.3] TAMBOSIM_PATH Not Set

**Symptom:** Loading Tambo fails with:
```
ERROR: InitError: KeyError: key "TAMBOSIM_PATH" not found
```

**Solution:** Set the environment variable before starting Julia:
```bash
export TAMBOSIM_PATH=/path/to/TAMBO-MC
```

Or within Julia before loading Tambo:
```julia
ENV["TAMBOSIM_PATH"] = "/path/to/TAMBO-MC"
```
