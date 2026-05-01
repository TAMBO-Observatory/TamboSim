# `examples/_internal/`

Maintenance scripts for the artifacts shipped with TamboSim. **Not curated
examples** — external users do not need anything here. For curated
user-facing examples, see [`../interactive/`](../interactive) and
[`../templates/`](../templates).

## Files

| File | What it does |
|---|---|
| [`make_example_output.jl`](make_example_output.jl) | Regenerate `../resources/example_output.jld2`, the small precomputed pipeline output that all the interactive walkthroughs load. Re-run when the on-disk schema changes. |
| [`rebuild_geometry_jld2.jl`](rebuild_geometry_jld2.jl) | Rebuild a tracked GCD-bundle JLD2 fixture (e.g. `colca_valley_3000.jld2`) from its HDF5 source. Re-run when JLD2's stored type names go stale (renames, struct-layout changes). |

## Conventions

- Both scripts compute `tambo_path` from `ENV["TAMBOSIM_PATH"]` (falling
  back to `dirname(dirname(@__DIR__))`) and activate the `examples/` env
  via `Pkg.activate(joinpath(@__DIR__, ".."))`, so they can be run
  directly with:
   
  ```bash
  julia path/to/script.jl
  ```
