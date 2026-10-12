# Site files

A *site file* describes the **environment** an air shower develops in: the
**atmosphere layer profile** and the **local geomagnetic field**. Both depend
on where the observatory is, so they travel together in one file.

A site file does **not** describe the local topography. The ground is a
separate input: the observation surface and the terrain are mesh files, passed
to `tambo_shower` as `--obs-mesh` and `--terrain-mesh` and generated from the
geometry bundles in `resources/geometry/`. The two are independent — the same
site file can be used with any terrain, and the same terrain with any site.

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

The value is a path. A relative path is resolved against the package root, and
`TamboSim.site_file_path` (`src/corsika/run_corsika.jl`) checks that the file
exists, so a missing or misspelled path fails before the binary is spawned.

`tambo_shower` copies the resolved site file into the run's output
directory as `site.toml`, so the run has a stable record of the site parameters.

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

Layers are listed as radial shells from sea level outwards. `top_altitude_km` must **strictly
increase**: each entry gives the top of one layer, which is also the bottom of
the next. A file whose altitudes do not increase is rejected.

There are two density profile options supported, selected by the `type` parameter:

- `exponential` — `rho(h) = (offset_g_cm2 / scale_height_cm) * exp(-h / scale_height_cm)`
- `linear` — `rho(h) = offset_g_cm2 / scale_height_cm`, constant

Here `h` is the altitude above **sea level** 
and `top_altitude_km` is the altitude at which the current layer ends and the next begins. `offset_g_cm2` and `scale_height_cm`
are the coefficients of a profile anchored at sea level, so
`offset / scale_height` is the density that profile would give at `h = 0`. For a
high layer that is an extrapolation rather than a physical density: in
`colca.toml` the 26.5–100 km layer works out to 2.15e-3 g/cm^3, denser than air
at sea level, which is expected.

**Any number of layers is supported, in any mix of the two types.** For reference, the CORSIKA 7 convention was "4 exponential + 1 linear".

The **outermost layer must extend above the injection altitude**, since a
primary injected above the atmosphere would never enter it. `tambo_shower`
checks this at startup and refuses to run if it fails, reporting both
altitudes. Both shipped files top out at 5000 km with an effective-vacuum layer
(about 1e-9 g/cm^3).

### Geomagnetic field

Values are the field in the local East-North-Up frame at the site, in
microtesla. `tambo_shower` derives the ENU basis at the shower-core intercept
and rotates the triplet into ECEF.

`up_uT` is **positive up**. The NOAA/WMM calculator
(<https://www.ngdc.noaa.gov/geomag/calculators/magcalc.shtml#igrfwmm>) reports
`Z` positive *down*, so `up_uT = -Z`.

## What a site file cannot set

Two properties of the atmosphere are fixed and cannot be changed from this
file. The air composition is always CORSIKA's standard dry-air mixture, so a
site cannot specify its own. And every layer must be either exponential or
constant density, so a profile supplied as a table of measured densities is not
supported. Adding either in the future would require extending both this file format and the
loader that reads it.
