# Site files

A *site file* describes the two location-dependent inputs to a CORSIKA 8 air
shower: the **atmosphere layer profile** and the **local geomagnetic field**.
They are physically tied to a location, so they travel together in one file.

Nothing about a site is compiled into `tambo_shower` — adding or editing a site
means writing a TOML file, with no rebuild.

## Using one

From the C++ binary directly:

```bash
tambo_shower --site-file /path/to/my_site.toml ...
```

From a TamboSim config, via the required `[corsika] site_file` key:

```toml
[corsika]
site_file = "resources/sites/colca.toml"    # package-relative
# site_file = "/abs/path/to/my_site.toml"   # absolute
```

The value is always a path -- there is no name registry. A relative path is
resolved against the package root, and `TamboSim.site_file_path`
(`src/corsika/run_corsika.jl`) checks the file exists, so a missing or
misspelled path fails before the binary is spawned.

For provenance, `tambo_shower` copies the resolved site file into the run's
output directory as `site.toml`, since the `config.yaml` argv record pins only
the path.

## Shipped sites

| File | Description |
|------|-------------|
| `colca.toml` | TAMBO site, Colca Valley, Peru. Local radiosonde / reanalysis fit. |
| `lima.toml`  | TAMBO-4 Lima validation site. ERA5 garua-season fit. |

## Schema

```toml
name = "colca"            # optional, for logs
description = "..."       # optional, for logs

[geomagnetic_field]       # required, all three keys required
east_uT  = -2.5           # local ENU components, microtesla
north_uT = 22.9
up_uT    = 3.7            # positive UP

[[atmosphere.layer]]      # required, at least one
type            = "exponential"   # or "linear"
top_altitude_km = 3.8             # outer boundary, km above sea level
offset_g_cm2    = 1208.0663       # > 0
scale_height_cm = 1045629.03      # > 0
```

Unknown keys are rejected, at both the top level and inside a layer: a typo'd
`offset_g_cm2` would otherwise silently produce a different atmosphere.

### Layers

Layers are listed **innermost first** and `top_altitude_km` must **strictly
increase** — CORSIKA's `LayeredSphericalAtmosphereBuilder` builds concentric
spheres outward and rejects a non-increasing boundary.

The density profile depends on `type`:

- `exponential` — `rho(h) = offset_g_cm2 / scale_height_cm * exp(-(h - top_altitude) / scale_height)`
  (a `SlidingPlanarExponential` medium; `offset / scaleHeight` is the density at
  `top_altitude`).
- `linear` — `rho(h) = offset_g_cm2 / scale_height_cm`, constant
  (a `HomogeneousMedium`).

**Any number of layers is supported, in any mix of the two types.** The
familiar "4 exponential + 1 linear" shape is the CORSIKA 7 preset convention,
not a limit.

The **outermost layer must top out above the injection altitude**. A primary
injected outside the topmost layer lands in CORSIKA's universe node and is
erased, so `tambo_shower` refuses to run in that case rather than silently
losing the shower. Both shipped files end with an effective-vacuum layer
(`rho ~ 1e-9 g/cm^3`) at 5000 km, well above the ~112 km injection altitudes
used by the pipeline.

### Geomagnetic field

Values are the field in the local East-North-Up frame at the site, in
microtesla. `tambo_shower` derives the ENU basis at the shower-core intercept
and rotates the triplet into ECEF.

`up_uT` is **positive up**. The NOAA/WMM calculator
(<https://www.ngdc.noaa.gov/geomag/calculators/magcalc.shtml#igrfwmm>) reports
`Z` positive *down*, so `up_uT = -Z`.

## Not (yet) configurable

The nuclear composition is fixed to CORSIKA's `standardAirComposition`, and
CORSIKA's tabular density profiles (`addTabularLayer`) are not exposed. Both
would be natural extensions of this file format.
