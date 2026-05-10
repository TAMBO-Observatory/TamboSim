
## Why CORSIKA in TAMBO?

TAMBO is a planned km-scale extended air shower array deployed along the face of a wide, steep canyon.
The primary signature TAMBO will look for will be inclined air showers produced by the decays of tau leptons, themselves produced by tau-neutrino interactions in the opposing rock face. 
These signals will need to be picked out from underneath a huge background of cosmic ray air showers. Cosmic ray air showers arriving from just above the opposite canyon horizon will trigger the detector at a huge rate; in addition, high energy inclined muons produced in these air showers can also punch through up to several kilometers of rock and produce secondary air showers of their own. 

Modeling all these geometrical propagation effects will be important to understanding the separation between TAMBO's signal and background region. To do this, we rely on our Tambo's local CORSIKA 8 application `tambo_shower`, which lives at [src/corsika/tambo_shower/src/](../src/corsika/tambo_shower/src/). `tambo_shower` is built against the `mesh-bvh-geometry-framework` branch of CORSIKA 8, which was developed by Jeff Lazar for TAMBO. 

`tambo_shower` runs one shower per invocation. Given an injection point and a downstream intercept, it writes per-shower particle records that TamboSim then reads back and feeds into the detector simulation.


## Breakdown of how `tambo_shower` is built:


## Detailed Q+A on CORSIKA internals:

<details>
<summary><h3>What does it mean for the atmosphere to be "layered" in CORSIKA?</h3></summary>

Not what you might intuitively guess. Geometrically, the atmosphere is not a stack of spherical *shells* — it is a set of nested filled *balls*.

Each layer in CORSIKA's `LayeredSphericalAtmosphereBuilder` is constructed as a `Sphere` of radius `R_earth + upper_boundary_altitude`. The builder pushes them in ascending-radius order onto a stack and then, in `assemble()`, chains them as ancestors-of-descendants: the largest ball becomes a child of `Universe`, the next-largest is added as a child of that one, and so on. So in the volume tree, the innermost layer is the deepest descendant.

`getContainingNode(p)` walks this tree depth-first and returns the *smallest* node whose `Sphere::contains(p)` is true. So at any point inside layer N, all layers ≥ N also geometrically contain that point — but the depth-first traversal picks the innermost one, and only that layer's medium properties apply.

**The non-obvious consequence:** the innermost layer's ball extends all the way down to r=0. Anywhere below the Earth surface that's not claimed by another child node (e.g. the rock `TriangularMesh` in `tambo_shower`), the innermost atmosphere layer "owns" the point — including the entire Earth interior. The layer's exponential-density model is evaluated there with negative altitude, producing extrapolated densities that grow exponentially with depth: ~1.15 mg/cm³ at h=0 (normal sea-level air), ~3.3 mg/cm³ at h=−11 km, ~16 g/cm³ at h=−100 km, nonsense further down. This is numerically defined and harmless for descending particles in the air-outside-the-terrain-footprint case, but it does mean "the simulation treats Earth's interior as fictitious-density air" wherever the rock node isn't.

Source pointers (all under `corsika/` in the CORSIKA 8 source tree, e.g. on FASRC at `/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika/corsika/`):

- `detail/media/LayeredSphericalAtmosphereBuilder.inl` — `addExponentialLayer` (line 54), `addLinearLayer` (line 90), `addTabularLayer` (line 126) all wrap a `Sphere(center_, planetRadius_ + upperBoundary)` in a `VolumeTreeNode`. `assemble()` at lines 162–170 chains them largest-first as nested children.
- `detail/framework/geometry/Sphere.inl` (lines 15–16) — `Sphere::contains(p)` returns `radius² > |center − p|²` (strict, so surface points belong to the parent).
- `detail/media/VolumeTreeNode.inl` (lines 36–51) — `getContainingNode(p)` recurses into the first child whose `contains()` is true.

</details>

<details>
<summary><h3>What happens to particles that exit the outermost atmosphere layer?</h3></summary>

They are deleted cleanly, with a log line, and no further tracking. CORSIKA 8 has an explicit erase path for this case.

The volume tree at the root is `Universe`, an infinite-radius `Sphere` whose `contains(p)` always returns true. Universe is *not* given any `HomogeneousMedium` or other model properties in `tambo_shower` — it is an empty container. Its direct child is the largest atmosphere layer (the 5000 km-radius outermost ball, in the Colca 5-layer config). When a particle inside that outermost layer steps far enough outward to cross its surface, the tracking machinery in `Intersect.inl` resolves the next volume as `volumeNode.getParent()` — which is Universe. At that point `Cascade::step` (lines 278–281 of `Cascade.inl`) sees `nextVol == environment_.getUniverse().get()`, calls `particle.erase()` *before* updating the particle's logical node, and emits a log message reading:

> `particle left physics world, is now in unknown space -> delete`

So upward escape is handled cleanly: the particle is removed and counted as having left the simulation universe. No assert, no undefined behaviour, no propagation through empty space.

**The asymmetry worth knowing:** this clean-erase path only fires for *boundary crossings*. If a particle somehow ends up with its logical node already set to Universe — for example via a numerical edge case where a tracking step overshoots all known geometry without crossing the boundary cleanly — `Cascade::step` opens with an `assert` (lines 127–130 of `Cascade.inl`):

```cpp
assert((currentLogicalNode != &*environment_.getUniverse() ||
        environment_.getUniverse()->hasModelProperties()) &&
       "FATAL: The environment model has no valid properties set!");
```

In debug builds this aborts; in release builds it's undefined behaviour from dereferencing a null `modelProperties_` pointer when physics modules later try to read the composition. 

Source pointers:

- `detail/media/Universe.inl` — `Universe::contains()` always returns `true`; radius is infinite.
- `detail/framework/core/Cascade.inl` lines 127–130 — the `assert` that fires if a particle is logically inside Universe.
- `detail/framework/core/Cascade.inl` lines 278–281 — the explicit `particle.erase()` path on outermost-layer exit.
- `detail/modules/tracking/Intersect.inl` — `nextIntersect` sets `minNode = volumeNode.getParent()` on layer exit, which for the outermost atmosphere ball resolves to Universe.

</details>

<details>
<summary><h3>What happens in a release build if a particle accidentally overshoots into Universe?</h3></summary>

A deterministic segfault at `Cascade.inl` line 132. Not silent garbage propagation — the simulation crashes immediately the first time any particle's step executes with Universe as its logical node.

Mechanism: `Cascade::step` opens with the assert described in the previous Q+A, but that assert is compiled out in release builds (`NDEBUG` defined). The next executed line that touches the current node's medium is:

```cpp
media::NuclearComposition const& composition =
    currentLogicalNode->getModelProperties().getNuclearComposition();
```

`getModelProperties()` is defined in `VolumeTreeNode.hpp` line 67 as `return *modelProperties_;`, where `modelProperties_` is a `std::shared_ptr<IModelProperties>`. For Universe, this pointer was never populated — it is null. The dereference `*modelProperties_` is therefore a null-pointer dereference, which crashes on every real platform before `getNuclearComposition()` is even reached. No cross-section sampling, no energy-loss evaluation — the process simply dies.

**The practical implication is actually reassuring:** the failure mode is a hard crash, not silent wrong-result propagation.

Source pointers:

- `framework/geometry/VolumeTreeNode.hpp` line 67 — `getModelProperties()` returns `*modelProperties_` (no null check).
- `detail/framework/core/Cascade.inl` lines 132–133 — the first use of `currentLogicalNode`'s model properties after the assert, where the crash lands in release.

</details>

<details>
<summary><h3>Does an absorbing <code>ObservationPlane</code> only absorb particles that pass in a given direction? What does the direction argument control?</h3></summary>

No — absorption is **unconditionally bi-directional**. The constructor signature looks directional but isn't:

```cpp
ObservationPlane(plane, xRefDir, absorbing=false, padding=1um)
```

The `xRefDir` argument is **not** a directional gate on absorption. It is a *reference direction in the plane* used to define the in-plane x-axis of the recorded coordinate frame — i.e., when a particle is recorded into `particles.parquet`, its position is written in a 2D frame anchored by the plane normal and the `xRefDir` tangent vector. It controls output orientation only.

Absorption itself has no directional logic anywhere in the class:

- `ObservationPlane::getMaxStepLength()` calls `TrackingStraight::intersect(particle, plane)`, which returns a signed time-to-crossing `t = n · delta / n · v` — but the rejection criterion is only `t ≤ 0` (i.e. plane in the past or motion parallel). There is no sign check on `n · v`. A particle moving into the positive-normal half-space (upward, if the normal is upward) produces a positive `t` just as much as one moving into the negative-normal half-space (downward).
- `ObservationPlane::doContinuous()` then writes the hit and, if `absorbing=true`, returns `ProcessReturn::ParticleAbsorbed`. The entire body contains zero directional logic — no `n · v` check, no comparison of particle direction against plane normal.

So every crossing of the plane, in either direction, fires absorption.

**Contrast with `ObservationMesh`.** `ObservationMesh` *does* accept `recordEntry_` / `recordExit_` flags, and its `doContinuous()` computes `normalDotDir` and gates the recording on those flags. But those flags only gate the *parquet write*, not the absorption: a particle whose crossing is filtered out by `recordExit_=false` is still absorbed if `absorbing=true`. The architectural limitation — "absorbing means absorbing in any direction" — is the same in both classes; the mesh just has finer control over what gets written.

Source pointers:

- `detail/modules/ObservationPlane.inl` — `getMaxStepLength()` and `doContinuous()` bodies; no directional logic anywhere.
- `detail/modules/tracking/TrackingStraight.inl` lines 146–158 — unsigned plane-intersection time computation.
- `detail/modules/ObservationMesh.inl` — for comparison, shows how `normalDotDir`, `recordEntry_`, `recordExit_` gate the write (but not absorption) in that class.

</details>

