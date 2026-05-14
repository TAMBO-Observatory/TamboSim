# TamboSim examples

This directory holds runnable examples for the TamboSim simulation
pipeline, its data model, and common analysis patterns. There are two
different kinds of examples, kept in separate subdirectories:

1. Walkthroughs in `interactive/` are designed for Shift+Enter — each
section is a self-contained block of expressions that display values in
the REPL. 

2. Templates in `templates/` are ArgParse CLIs you edit and run
end-to-end.

```
examples/
├── interactive/    paste into the REPL section by section
├── templates/      edit constants, run as a script or CLI
├── resources/      small precomputed assets (committed)
├── output/         where templates write results (gitignored)
└── _internal/      TamboSim-collab batch ops; not curated examples
```

Both subdirectories are numbered by concept complexity
(basic → advanced) and/or processing step.

## Where do I start?

It depends on what you came here to do.

| You want to… | Start here | Then |
|---|---|---|
| **Read TamboSim output** — load a `.jld2`, navigate the frame container, compute weights, classify decays | [`interactive/1_frame_usage.jl`](interactive/1_frame_usage.jl) | [`interactive/2_analyze_output.jl`](interactive/2_analyze_output.jl) |
| **Run the full pipeline for yourself** — build a site, place modules, inject events, propagate, shower, project hits | [`templates/1_create_geometry.jl`](templates/1_create_geometry.jl) | templates 2 → 6, in order |
| **Understand how TamboSim works internally** — `inject!`, `proposal_propagation!`, `corsika_run!`, weighting, OBB placement | [`interactive/3_injection_walkthrough.jl`](interactive/3_injection_walkthrough.jl) | walkthroughs 4, 5, 6, 7 |

If you're new to TamboSim entirely, **start with `interactive/1_frame_usage.jl`** — every other walkthrough assumes you've seen how a `TamboFrames` container is laid out and how key inheritance works.

## Interactive walkthroughs

These are read-only explorations of the TamboSim API. Every file loads
the canonical example output (`resources/example_output.jld2` — a small
precomputed run of 50 nu_tau CC events through inject + PROPOSAL, no
CORSIKA), so the walkthroughs work on a fresh checkout without your
having to regenerate any artifacts first.

| File | Role |
|---|---|
| [`1_frame_usage.jl`](interactive/1_frame_usage.jl) | load + explore a TamboFrames; G/M/Q hierarchy, key inheritance, the TOML config that produced it |
| [`2_analyze_output.jl`](interactive/2_analyze_output.jl) | filter to air decays, compute one-weights via `oneweights(tf)`, classify decay-product flavor |
| [`3_injection_walkthrough.jl`](interactive/3_injection_walkthrough.jl) | what `inject!` does: samplers + cross section, the sampling-inversion trick, the three injection states, the `phase_space_point` handoff to weighting |
| [`4_propagation_walkthrough.jl`](interactive/4_propagation_walkthrough.jl) | what `proposal_propagation!` does: PROPOSAL backend init, per-event call, the four output keys, the per-PDG rest-energy guard |
| [`5_corsika_walkthrough.jl`](interactive/5_corsika_walkthrough.jl) | what `corsika_run!` does: per-event work, trajectory→detector intersect, the `tambo_shower` CLI shape (read-only — does not invoke the binary) |
| [`6_weighting_walkthrough.jl`](interactive/6_weighting_walkthrough.jl) | what `oneweights(tf)` does: PhaseSpace + PhaseSpacePoint structs, the two-method `_compatible` check, the per-event density functor, multi-campaign aggregation |
| [`7_detector_layout.jl`](interactive/7_detector_layout.jl) | how `templates/2_create_detector.jl` places OBBs: area-weighted plane, hex grid with tilt correction, vertical projection, per-point OBB construction with slope filter |

## Templates (production pipeline)

These are edit-and-run CLIs that together form the full production
pipeline. The default `--infile` and `--outfile` paths chain through
the sequence, so the natural way to use them is to run them in order
and let each one pick up where the previous one left off. Override the
path flags whenever you want to fan out runs to a different working
directory.

```
1_create_geometry  →  2_create_detector  →  3_inject  →  4_propagate  →  5_run_corsika  →  6_corsika_hits
   geometry/<name>.jld2     (overwrites)         injected.jld2   propagated.jld2     corsika_ready.jld2 + corsika/   (overwrites)
```

By default, every template loads its geometry from
`resources/geometry/colca_valley_3000.jld2` (the canonical Colca-valley
site). To use your own site instead, pass `--geometry` — and if you
don't have a site yet, templates 1 and 2 will build one for you.

| File | Role |
|---|---|
| [`1_create_geometry.jl`](templates/1_create_geometry.jl) | build a TamboSim geometry HDF5 + PLY + GCD-bundle JLD2 from a flat-square placeholder terrain. Replace `build_terrain_patch` with a DEM-interpolating function for real topography |
| [`2_create_detector.jl`](templates/2_create_detector.jl) | place detector OBBs on a single GC bundle (hex grid + slope filter), write back to the D frame |
| [`3_inject.jl`](templates/3_inject.jl) | wraps `inject!`. Loads geometry + `[injection]` config, samples primaries, writes Q frames with injection states + the per-event `phase_space_point` consumed by `oneweights` |
| [`4_propagate.jl`](templates/4_propagate.jl) | wraps `proposal_propagation!`. Loads inject output, propagates leptons through PROPOSAL, optionally drops events that range out inside the mountain |
| [`5_run_corsika.jl`](templates/5_run_corsika.jl) | wraps `corsika_run!`. For each surviving propagation event, dispatches a `tambo_shower` job per non-neutrino decay product. Set `executor = "run_sbatch"` (with `executor_sbatch_prefix`) or `executor = "dump_to_file"` in the `[corsika]` TOML for cluster / external-scheduler dispatch |
| [`6_corsika_hits.jl`](templates/6_corsika_hits.jl) | reads CORSIKA output dirs, projects each shower particle onto the detector OBBs, writes `corsika_hits` per Q frame |

Note that `6_corsika_hits.jl` is the only template that requires
detector OBBs to be already placed in the D frame — its input geometry
must have gone through template 2 first. The earlier templates only
need the `detector_region` and `detector_bvh` keys that
`1_create_geometry.jl` writes by default.

## Resources

`resources/example_output.jld2` is a small precomputed pipeline output
(50 nu_tau CC events through inject + PROPOSAL, fixed seed 1234)
that all of the interactive walkthroughs load. If the on-disk schema
ever changes, you can regenerate it with
`_internal/make_example_output.jl`.

The canonical Colca-valley geometry lives one level up, at
`resources/geometry/colca_valley_3000.jld2` — in the TamboSim package's
shared `resources/`, not under `examples/`. It's the default
`--geometry` input for templates 3–6.

## What's not here

- **The CORSIKA binary itself.** `templates/5_run_corsika.jl` won't do
  anything until `tambo_shower` is built — see
  [`src/corsika/tambo_shower/src/README.md`](../src/corsika/tambo_shower/src/README.md)
  for the build instructions.
- **The `_internal/` directory.** These are scripts the TamboSim
  collaboration uses for batch geometry surveys and example-artifact
  regeneration. They aren't curated examples, so feel free to ignore
  them unless you specifically need one.
- **Plotting helpers.** Visualization tools live in the sibling
  `TamboMakie.jl` package.
