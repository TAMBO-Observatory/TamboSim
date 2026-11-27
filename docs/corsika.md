
## Why CORSIKA in TAMBO?

TAMBO is a planned km-scale extended air shower array deployed along the face of a wide, steep canyon.
The primary signature TAMBO will look for will be inclined air showers produced by the decays of tau leptons, themselves produced by tau-neutrino interactions in the opposing rock face. 
These signals will need to be picked out from underneath a huge background of cosmic ray air showers. Cosmic ray air showers arriving from just above the opposite canyon horizon will trigger the detector at a huge rate; in addition, high energy inclined muons produced in these air showers can also punch through up to several kilometers of rock and produce secondary air showers of their own. 

Modeling all these geometrical propagation effects will be important to understanding the separation between TAMBO's signal and background region. To do this, we rely on our Tambo's local CORSIKA 8 application `tambo_shower`, which lives at [src/corsika/tambo_shower/src/](../src/corsika/tambo_shower/src/). `tambo_shower` is built against the `tambo/mesh` branch of CORSIKA 8, at the commit pinned in [its build instructions](../src/corsika/tambo_shower/src/README.md): the mesh geometry developed by Jeff Lazar for TAMBO (CORSIKA MR !753), plus fixes and speedups under review upstream separately. 

`tambo_shower` runs one shower per invocation. Given an injection point and a downstream intercept, it writes per-shower particle records that TamboSim then reads back and feeds into the detector simulation.


## Breakdown of how `tambo_shower` is built:


## Detailed Q+A on CORSIKA internals:

<details>
<summary><h3>What does it mean for the atmosphere to be "layered" in CORSIKA?</h3></summary>

Not what you might intuitively guess. Geometrically, the atmosphere is not a stack of spherical *shells* — it is a set of nested filled *balls*.

Each layer in CORSIKA's `LayeredSphericalAtmosphereBuilder` is constructed as a `Sphere` of radius `R_earth + upper_boundary_altitude`. The builder pushes them in ascending-radius order onto a stack and then, in `assemble()`, chains them as ancestors-of-descendants: the largest ball becomes a child of `Universe`, the next-largest is added as a child of that one, and so on. So in the volume tree, the innermost layer is the deepest descendant.

`getContainingNode(p)` walks this tree depth-first and returns the *smallest* node whose `Sphere::contains(p)` is true. So at any point inside layer N, all layers ≥ N also geometrically contain that point — but the depth-first traversal picks the innermost one, and only that layer's medium properties apply.

**The non-obvious consequence:** the innermost layer's ball extends all the way down to r=0. Anywhere below the Earth surface that's not claimed by another child node (e.g. the rock `ClosedMesh` in `tambo_shower`), the innermost atmosphere layer "owns" the point — including the entire Earth interior. The layer's exponential-density model is evaluated there with negative altitude, producing extrapolated densities that grow exponentially with depth: ~1.15 mg/cm³ at h=0 (normal sea-level air), ~3.3 mg/cm³ at h=−11 km, ~16 g/cm³ at h=−100 km, nonsense further down. This is numerically defined and harmless for descending particles in the air-outside-the-terrain-footprint case, but it does mean "the simulation treats Earth's interior as fictitious-density air" wherever the rock node isn't.

Source pointers (all under `corsika/` in the CORSIKA 8 source tree, e.g. on FASRC at `/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika/corsika/`):

- `detail/media/LayeredSphericalAtmosphereBuilder.inl` — `addExponentialLayer` (line 54), `addLinearLayer` (line 90), `addTabularLayer` (line 126) all wrap a `Sphere(center_, planetRadius_ + upperBoundary)` in a `VolumeTreeNode`. `assemble()` at lines 162–170 chains them largest-first as nested children.
- `detail/framework/geometry/Sphere.inl` (lines 15–16) — `Sphere::contains(p)` returns `radius² > |center − p|²` (strict, so surface points belong to the parent).
- `detail/media/VolumeTreeNode.inl` (lines 36–51) — `getContainingNode(p)` recurses into the first child whose `contains()` is true.

</details>

<details>
<summary><h3>What is an "overlap-exclusion" (<code>excludeOverlapWith</code>) and what does it do?</h3></summary>

CORSIKA's volume tree normally expects **strictly nested, disjoint** volumes: each node's children sit fully inside it and don't overlap each other, so `getContainingNode` (first child that `contains(p)`, then recurse) and the tracker (test the current node's direct children) both resolve unambiguously. An **overlap-exclusion** is the escape hatch for a volume that does *not* fit that mould — one that overlaps a node (or several) without being a clean nested child of it.

`node->excludeOverlapWith(otherNode)` registers `otherNode` as a region "carved out of" `node`: within their overlap, `otherNode` takes precedence over `node`. Mechanically (all in `VolumeTreeNode`):

- It appends a **non-owning raw pointer** to `node`'s `excludedNodes_` (a `std::vector<VolumeTreeNode const*>`). `excludeOverlapWith` does **not** take ownership — the excluded node's lifetime must be guaranteed elsewhere (it still has to be `addChild`'d to some node so a `unique_ptr` owns it; the exclude list only *references* it).
- **Point→medium** (`getContainingNode(p)`): a node first checks its children; if none contains `p` it checks `excludes(p)` (the first excluded node whose `contains(p)` is true) and recurses into it; only if that also fails does it return itself. So an excluded node wins over the node's own medium, but a genuine child still wins over an excluded node.
- **Tracking** (`nextIntersect`): for the particle's current logical node, the tracker tests its direct children **and** its excluded nodes for the next boundary, so crossing into or out of an excluded node is a normal step boundary.

The net effect: one physical volume can be made visible — for *both* medium lookup and tracking — to several tree nodes it overlaps, without being a child of any of them and without breaking the disjoint-nesting invariant the rest of the tree relies on. The cost is one `contains()` / mesh-intersection test per excluded node per step while a particle is resident in a node that lists it, so a volume should be excluded only on the nodes it actually overlaps.

Source pointers (under `corsika/`; FASRC `/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika/`):

- `media/VolumeTreeNode.hpp` — `excludedNodes_` is `std::vector<VTN_type const*>` (non-owning); `childNodes_` is `std::vector<VTNUPtr>` (owning); `excludeOverlapWith` / `excludes` / `getExcludedNodes` declarations.
- `detail/media/VolumeTreeNode.inl` — `excludeOverlapWith` pushes `pNode.get()` into `excludedNodes_`; `excludes(p)` (lines 21–29) returns the first excluded node containing `p`; `getContainingNode` (lines 36–53) checks children, then `excludes(p)`, then returns `this`.
- `detail/modules/tracking/Intersect.inl` — `nextIntersect` tests the current node's direct children (lines 59–81) **and** its `getExcludedNodes()` (lines 85–104) for the next boundary.

</details>

<details>
<summary><h3>How does <code>tambo_shower</code>'s terrain rock volume nest within the multiple atmosphere layers?</h3></summary>

`tambo_shower` registers the terrain as a single `ClosedMesh` node (closed, consistently oriented, outward-facing; the constructor throws otherwise) carrying a `HomogeneousMedium` (standard rock, 2.65 g/cm³). The atmosphere is a *nested single-child chain* of filled balls centred at Earth's centre (universe → outermost layer → … → innermost layer; see the layered-atmosphere Q+A). The terrain mesh **straddles several of these layers** — an Earth-skimming particle can be logically resident in different atmosphere layers at different points along its crossing of the terrain. For the particle to actually lose energy in the rock, *two* independent CORSIKA mechanisms must each resolve to the rock node **from whatever layer the particle currently occupies** — the **point→medium lookup** and the **tracking step-boundary detection**. A *third* requirement is distinct: when the particle *leaves* the rock it must be returned to the medium that geometrically contains it, not left in whatever node the tracker happens to assign. The first two are set up by the `CRITICAL` comment at the rock-volume registration in [tambo_shower.cpp](../src/corsika/tambo_shower/src/tambo_shower.cpp); the third is done by CORSIKA's `Cascade` after every mesh crossing.

The first two are addressed by how the rock node is registered: as an **overlap-exclusion** (`excludeOverlapWith`; see the overlap-exclusion Q+A above) on every atmosphere layer the terrain spans — from the innermost layer up to the highest one the terrain reaches (found via `getContainingNode` at the terrain's maximum radius) — and *owned* (via `addChild`) by the topmost of those spanned layers. The third is handled in CORSIKA itself. All three then work properly: 

- **1. Point→medium lookup.** `getContainingNode(p)` descends from the universe root: at each level it recurses into the *first child* that `contains(p)`; if no child contains `p` it consults that node's **excluded-overlap nodes** via `excludes(p)`; only if that also fails does it return the layer itself. Because the atmosphere layers are filled balls, the descent always bottoms out at the innermost layer whose sphere contains `p`. With the rock registered as an excluded-overlap on that layer, a sub-surface point inside the mesh resolves to the rock (excludes are consulted *before* the layer's own air, *after* its children), so the medium at a rock point is StandardRock no matter which layer the point falls in. The `ShowerAxis` builds its longitudinal grammage axis with this same full-tree `getContainingNode` walk at construction, so the grammage coordinate correctly accumulates rock density along the axis.

- **2. Tracking step-boundary detection.** Resolving the medium at a point isn't enough — the tracker must also *end the step* at the rock surface so the medium switches mid-flight. For the particle's *current* logical node, `nextIntersect` tests both its **direct children and its excluded-overlap nodes**, one level deep (no tree descent). Because the rock is an excluded-overlap of every layer the terrain spans, whichever layer the particle is logically in as it reaches the terrain has the rock mesh in its candidate set: the step ends at the rock surface, the logical node becomes the rock node, and StandardRock + PROPOSAL losses apply. The rock is owned by (a child of) the topmost spanned layer, so on exit `getParent()` returns a real atmosphere layer — never the universe, which would erase the particle.

- **3. Correct logical-node placement on rock exit.** `nextIntersect` sets a particle's post-exit logical node to `rock.getParent()` (the topmost spanned layer) regardless of where the exit point actually is, and the step ends on the rock surface. CORSIKA's `Cascade` corrects both after every crossing of a padded (`ClosedMesh`) boundary: it moves the particle 2 x `boundaryPadding` (2 µm) along its direction, off the surface band, and places it in the node `getContainingNode` returns there, which off the band is unambiguous. See **"When a particle leaves the terrain rock, where is it placed?"** below.

In summary: the rock is registered as an overlap-exclusion on each atmosphere layer the terrain spans and owned by the topmost of them, so both the point→medium lookup and the tracking step resolve to the rock from whatever layer a particle occupies while crossing the terrain; and `Cascade` places the particle in the geometrically containing layer, 2 µm off the surface, after every rock exit.

Source pointers (under `corsika/` in the CORSIKA 8 source tree; FASRC `/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika/`):

- `detail/media/VolumeTreeNode.inl` — `getContainingNode(p)` (lines 36–53) recurses into the first child containing `p`, else consults `excludes(p)` (excluded-overlap nodes) before returning the node itself; `excludes()` (lines 21–29) scans `excludedNodes_`; `excludeOverlapWith` registers a *non-owning* pointer in `excludedNodes_`; `addChild` sets `parentNode_` (ownership).
- `detail/media/LayeredSphericalAtmosphereBuilder.inl` (lines 161–170) — `assemble()` chains the atmosphere layers as a single nested-child path under `Universe` (outermost → innermost).
- `detail/modules/tracking/Intersect.inl` — `nextIntersect` tests the current logical node's direct children (lines 59–81) **and** its excluded-overlap nodes (lines 85–104) for the next entry; one level, no descent.
- `detail/framework/geometry/ClosedMesh.inl` — `contains()` is the sign of the generalised winding number (> 0.5); `inside()` adds `kSurface` within `boundaryPadding` (1 µm) of the surface. A sub-surface point inside the mesh resolves through `contains()`.
- `detail/media/ShowerAxis.inl` (lines 37–65) — the grammage axis (`X_[]`) is built at construction by integrating density sampled via `universe->getContainingNode(p)` (full tree descent), so it includes rock density along the axis.
- `tambo_shower.cpp` (local, [src/corsika/tambo_shower/src/](../src/corsika/tambo_shower/src/)) — terrain mesh registered as a StandardRock `HomogeneousMedium` via `excludeOverlapWith` on each spanned atmosphere layer and owned by the topmost spanned layer (the `CRITICAL` comment at the rock-volume registration).

</details>

<details>
<summary><h3>When a particle leaves the terrain rock, where is it placed?</h3></summary>

When a particle crosses out of the terrain rock, the tracker leaves two things the next step cannot use directly:

- **The logical node.** `nextIntersect` sets the post-exit node to `rock.getParent()`, the topmost atmosphere layer the terrain spans (the rock is owned by it so `getParent()` is a real layer, never the universe). That is not necessarily the layer that geometrically contains the exit point.
- **The position.** The step ends on the rock surface, inside the 1 µm `boundaryPadding` band where inside/outside is ambiguous.

CORSIKA's `Cascade::step` fixes both after every crossing of a boundary with a padding band (any `ClosedMesh`; nothing changes for spheres and planes): it moves the particle 2 x `boundaryPadding` along its direction, clear of the band, and sets its node to `getContainingNode` at the new position. Off the band that lookup is unambiguous, so the particle lands in the innermost atmosphere layer containing it. If the lookup returns the node the step started in, nothing was crossed (a step limited at a crossing estimate can end short of the surface) and no boundary process runs.

`Cascade` also checks, after every step, that a particle logically in a mesh is geometrically inside it. A particle that is definitely outside (`kOutside`) is re-rooted to its containing node at once; within the surface band (`kSurface`) it waits, and the run aborts only if the particle stays in the band for 1000 consecutive steps. The opposite desync, logically in air while geometrically in the rock, is resolved by the tracker: it reads the side from the ray's first mesh crossing (entering or leaving, by the face normal) and enters the rock at zero distance.

Before CORSIKA did this, `tambo_shower` carried two processes for it, `RockExitRelocator` and `RockInterfaceTripwire`; they were removed once validation showed `Cascade` placing every exit identically (zero disagreements) and a per-step audit found no step in the wrong medium.

Source pointers (CORSIKA 8, mesh branch):

- `detail/framework/core/Cascade.inl` — the post-crossing clearance and containing-node placement in the boundary-crossing branch of `Cascade::step`, and the boundary-desync backstop before it.
- `detail/modules/tracking/TrackingStraight.inl` — `intersect(particle, ClosedMesh)`: entry and exit from `TriangularMesh::crossings()`, classified by the outward face normal.
- `detail/framework/geometry/ClosedMesh.inl` — validation at construction, `contains()` (winding-number sign), `inside()` (three-state).

</details>

<details>
<summary><h3>Why doesn't <code>tambo_shower</code> track the EM shower a muon produces inside the terrain rock?</h3></summary>

Because it is both computationally intractable and physically unobservable, so `tambo_shower` deliberately suppresses it.

An Earth-skimming muon crossing the canyon rock is typically multi-TeV. In 2.65 g/cm³ standard rock its stochastic bremsstrahlung and pair-production losses are frequent and large, and each energy transfer seeds an electromagnetic shower. The radiation length of rock is ~10 cm, so CORSIKA would track that shower — recursively, e± → γ → e± — all the way down to the EM cut (`--emcut`, ~1 MeV in production). That is ~10⁶–10⁸ secondaries for a single muon crossing, each one stepped with a ray–mesh intersection against the ~180k-triangle terrain in its candidate set: it does not complete on any reasonable per-shower budget. And it is wasted work: an e±/γ created inside the rock has an EM range of ~cm–m and cannot escape the hundreds of metres to kilometres of rock the muon traverses, so it is never observed. TAMBO sees the *air* shower produced by the muon (and by the μ/τ/hadrons that can escape the rock), not the EM cascade buried inside the mountain.

`tambo_shower` therefore registers `RockEMAbsorber`, a process that **discards e±/γ whose logical node is the rock**, while keeping μ±, τ±, hadrons and neutrinos (those can escape the rock and seed the observable shower). The muon's energy degradation is preserved exactly: PROPOSAL removes the lost energy from the muon at the interaction vertex and applies the continuous dE/dx independently of whether the EM secondary is subsequently tracked — so the surviving muon energy, and any μ-pair or photonuclear-hadron secondaries, are unaffected. It acts through two hooks:

- **At creation (`doSecondaries`).** A secondary inherits its projectile's volume node at the moment it is added to the stack (`GeometryNodeStackExtension`: *"copy Node from parent particle!"*). So when the muon interacts while inside the rock, its e±/γ children carry `node == rock` immediately and are erased before they are ever transported — a zero-cost removal of the rock-born exponential at its source.
- **On the first step (`doContinuous`).** Any e±/γ whose *current* logical node is the rock is absorbed (`ProcessReturn::ParticleAbsorbed`) on its first tracked step. This is the comprehensive backstop: it also catches EM particles produced in air that later travel into the rock, which the creation-time hook does not see.

There is one deliberate approximation: an e±/γ produced within ~an EM range of the rock *surface* could in principle leave the rock into air, and it is discarded too. This is negligible — the EM range in rock (~cm–m) is tiny against the rock thickness the muon crosses, and a sub-GeV EM particle exiting the rock face is insignificant next to the muon and hadrons for a TAMBO air-shower observable. The process is a no-op when the terrain mesh is disabled (the rock node pointer is null), so pure-atmosphere showers are unaffected.

Source pointers (under `corsika/` in the CORSIKA 8 source tree; FASRC `/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika/`):

- `stack/GeometryNodeStackExtension.hpp` — `setParticleData(parent, …)` does `setNode(parent.getNode())` ("copy Node from parent particle!"), so a secondary's volume node is valid at birth and equals the projectile's; this is what makes the `doSecondaries` node test reliable.
- `detail/framework/stack/SecondaryView.inl` — `addSecondary(proj, …)` routes secondary creation through that parent-copy path.
- `corsika/modules/ParticleCut.hpp` / `detail/modules/ParticleCut.inl` — the in-tree precedent: a species-filtered absorber implementing both `doSecondaries` (`particle.erase()`) and `doContinuous` (`ProcessReturn::ParticleAbsorbed`); `RockEMAbsorber` mirrors its interface, keyed on the rock node instead of an energy threshold.
- `framework/process/SecondariesProcess.hpp`, `framework/process/ContinuousProcess.hpp`, `framework/process/ProcessReturn.hpp` — the two process interfaces and the `ParticleAbsorbed` return.
- `tambo_shower.cpp` (local, [src/corsika/tambo_shower/src/](../src/corsika/tambo_shower/src/)) — `RockEMAbsorber` definition and its placement in the process sequence (before the EM/hadron/decay processes, so an e±/γ in rock is removed before any interaction is sampled for it that step).

</details>

<details>
<summary><h3>Do CORSIKA's medium lookup and tracking step-boundary detection agree on where a mesh surface is?</h3></summary>

The terrain rock Q+A above relies on two mechanisms — the point→medium lookup (`getContainingNode`) and the tracking step-boundary detection (`nextIntersect`) — both resolving to the same `ClosedMesh`. They ask geometrically *different* questions about that surface: the medium lookup asks "is this point inside the rock?" (a point-in-mesh test), while the tracker asks "where along this trajectory does it cross the rock surface?" (a ray–surface intersection).

They are also answered by different code:

- **Point→medium lookup.** `ClosedMesh::contains(p)` is the sign of the generalised winding number at `p` (> 0.5), built from the triangles' solid angles. It casts no rays and uses no padding.
- **Step-boundary detection.** The tracker takes every forward crossing of the particle's ray from `TriangularMesh::crossings()`, each classified as entering or leaving by the sign of direction · face normal. Hits within `boundaryPadding` of each other (an edge or vertex) count once, and a touch is not a crossing. The particle's side is read from the first crossing — a leaving crossing means it is inside — so the entry and exit the tracker reports always agree with the crossings it found, even within the surface band where the winding number cannot tell.

Both are right only for a closed, consistently oriented, outward-facing mesh: an inward-wound patch flips the winding number and turns entries into exits. `ClosedMesh` checks this when it is built (every edge shared by exactly two faces and traversed once in each direction, positive signed volume) and throws otherwise, which is why cropped terrain needs `make_watertight` to orient its skirt and cap.

Away from the surface the two agree. Within numerical precision of it — grazing, near-tangent Earth-skimming trajectories, exactly what TAMBO simulates — they can disagree. Left alone that would be pathological, not cosmetic: a particle logically in the rock while geometrically in air bleeds rock dE/dx in air, and a particle could thrash on the boundary, entering and re-exiting indefinitely. CORSIKA therefore reconciles the two rather than relying on agreement:

- **Logically in air, geometrically in rock.** The ray's first crossing is a leaving one, so the tracker reports the particle inside the rock with entry at zero distance, and the next step enters it.
- **Logically in rock, geometrically in air.** After every step `Cascade::step` checks that a particle whose node is a mesh is inside it, using `ClosedMesh::inside()` (which adds `kSurface` within `boundaryPadding` of the surface). `kOutside` re-roots the particle to its containing node at once, with a "correcting logical-node desync" warning. `kSurface` waits; the run aborts after 1000 consecutive steps in the band, or after 1000 corrections of one particle.
- **Every crossing.** `Cascade` moves the particle 2 × `boundaryPadding` along its direction and places it in its containing node (see the rock-exit Q+A), so no step starts on the surface.

Source pointers (CORSIKA 8, `tambo/mesh`):

- `detail/framework/geometry/ClosedMesh.inl` — `contains()` (winding-number sign), `inside()` (three-state), validation at construction.
- `detail/framework/geometry/TriangularMesh.inl` — `crossings()`: every BVH hit along the ray, grouped within `boundaryPadding` and classified by the face normal.
- `detail/modules/tracking/TrackingStraight.inl` — `select_mesh_crossings()` (the side from the first crossing) and `intersect(particle, ClosedMesh)`.
- `detail/modules/tracking/TrackingLeapFrogCurved.inl` — `intersect(particle, ClosedMesh)`: neutral particles go to the straight tracker; charged ones use the same `crossings()` and `select_mesh_crossings()`, timing each crossing along the curved path.
- `detail/framework/core/Cascade.inl` — the boundary-desync backstop and the post-crossing placement in `Cascade::step`.

</details>

<details>
<summary><h3>Does the terrain mesh break CORSIKA's convex-volume tracking assumption?</h3></summary>

CORSIKA's tracker documents and relies on a convention that every volume primitive is *convex*. In `nextIntersect`, the point where a particle leaves its current volume is taken as a single exit time from that volume's intersection — the in-source comment states "all Volume primitives must be convex, thus the last entry is always the exit point." Terrain is decidedly non-convex: a near-horizontal, Earth-skimming path can pierce the rock surface several times (into a ridge, out over a valley, into the next ridge), and a naive first-in/last-out pairing would mis-identify which segments are rock and which are air. This is a real assumption the generic primitive path depends on (spheres and planes satisfy it trivially) — not merely a comment.

However, the `ClosedMesh` intersection does not rely on this assumption. Rather than a convex entry/exit pair, `intersect(particle, ClosedMesh)` takes *all* forward crossings of the ray, each classified as entering or leaving by the outward face normal (`TriangularMesh::crossings()`), and `select_mesh_crossings()` returns only the next pair: if the first crossing is leaving, the particle is inside, with entry at zero and exit at that crossing; otherwise entry is the first crossing and exit the first leaving crossing after it. So the single `getExit()` that `nextIntersect` uses is the *next* exit, not the last. Because the tracker re-evaluates at every boundary it stops at, a multi-crossing non-convex path is resolved correctly, segment by segment. The convex convention therefore governs the generic primitive path but is bypassed for the mesh — by design, not by accident.

Source pointers (CORSIKA 8, `tambo/mesh`):

- `detail/modules/tracking/Intersect.inl` — `nextIntersect` takes a single `getExit()` from the current volume's `Intersections` as where the particle leaves it; the in-source comment states the convex convention this relies on.
- `detail/modules/tracking/TrackingStraight.inl` — `select_mesh_crossings()` and `intersect(particle, ClosedMesh)`: the next entry/exit pair from the classified crossings (explicit non-convex handling).
- `detail/framework/geometry/TriangularMesh.inl` — `crossings()`, which classifies each crossing by the face normal.

</details>

<details>
<summary><h3>What happens to particles that exit the outermost atmosphere layer?</h3></summary>

They are deleted cleanly, with a log line, and no further tracking. CORSIKA 8 has an explicit erase path for this case.

The volume tree at the root is `Universe`, an infinite-radius `Sphere` whose `contains(p)` always returns true. Universe is *not* given any `HomogeneousMedium` or other model properties in `tambo_shower` — it is an empty container. Its direct child is the largest atmosphere layer (the 5000 km-radius outermost ball, in the shipped `colca.toml` site file). When a particle inside that outermost layer steps far enough outward to cross its surface, the tracking machinery in `Intersect.inl` resolves the next volume as `volumeNode.getParent()` — which is Universe. At that point `Cascade::step` (lines 278–281 of `Cascade.inl`) sees `nextVol == environment_.getUniverse().get()`, calls `particle.erase()` *before* updating the particle's logical node, and emits a log message reading:

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

<details>
<summary><h3>How does CORSIKA turn PROPOSAL energy losses into air-shower particles?</h3></summary>

PROPOSAL propagates muons (and taus) with exactly four cross-sections: 
— bremsstrahlung (`BremsKelnerKokoulinPetrukhin`)
- e⁺e⁻ pair production (`EpairKelnerKokoulinPetrukhin`)
- ionization (`IonizBetheBlochRossi`)
- and photonuclear (`PhotoAbramowiczLevinLevyMaor97` with `ShadowButkevichMikheyev`). 

Each step, losses are split into continuous vs. stochastic by `EnergyCutSettings(emCut, v_cut, false)`: a loss is stochastic (and produces secondaries) only if its fractional size exceeds `v_cut = 0.01` or the absolute `emCut`; everything below is absorbed as a smooth dE/dx by `ContinuousProcess::doContinuous()` with no secondaries. 

For a stochastic loss, `InteractionModel::doInteraction()` takes PROPOSAL's sampled secondaries and maps each onto the stack:

| `InteractionType` (value) | Reachable for | PROPOSAL secondaries | CORSIKA stack mapping |
|---|---|---|---|
| `Undefined` (0) | any (error edge case) | none — returned only when `overall_rate == 0` | projectile re-stacked unchanged; `ProcessReturn::Ok` |
| `Brems` (…002) | μ±, τ±, e±, γ | surviving lepton + 1 γ | lepton + `Code::Photon` |
| `Ioniz` (…003) | μ±, τ±, e± | surviving lepton + δ-ray e⁻ | lepton + `Code::Electron` — **never stochastic in `tambo_shower`** (`v_cut=1` for ioniz forces it fully continuous) |
| `Epair` (…004) | μ±, τ±, e± | surviving lepton + e⁻ + e⁺ | lepton + `Code::Electron` + `Code::Positron` |
| `Photonuclear` (…005) | μ±, τ±, e± | surviving lepton + `Hadron` (81) | lepton + `Hadron` → `doHadronicPhotonInteraction()` (Rho0/Sibyll if E_loss > `heThreshold`, else Photon/SOPHIA) |
| `MuPair` (…006) | — (cross-section not registered for any species in this build) | μ⁻ + μ⁺ | **not registered in `cross_builder` → never fires in `tambo_shower`** |
| `WeakInt` (…009) | μ±, τ±, e± in principle | weak-partner lepton + `Hadron` | **not registered in `cross_builder` → never fires in `tambo_shower`** |
| `Compton` (…010) | γ | scattered γ + e⁻ | `Code::Photon` + `Code::Electron` |
| `Annihilation` (…012) | e⁺ | 2 γ (positron fully consumed) | 2× `Code::Photon` |
| `Photopair` (…013) | γ | e⁻ + e⁺ (photon consumed) | `Code::Electron` + `Code::Positron` (subject to `CheckForLPM()`) |
| `Photoproduction` (…014) | γ | 1 `Hadron` (full photon energy) | `Hadron` → `doHadronicPhotonInteraction()` |
| `PhotoMuPair` (…015) | γ | μ⁻ + μ⁺ (photon consumed) | `Code::MuMinus` + `Code::MuPlus` |
| `Photoeffect` (…016) | γ | 1 e⁻ (photon consumed) | `Code::Electron` (negligible at high E) |
| `Particle` (…001), `Hadrons` (…007), `ContinuousEnergyLoss` (…008), `Decay` (…011) | — | internal PROPOSAL bookkeeping labels | never reach `doInteraction()`; sub-threshold loss → `ContinuousProcess::doContinuous()`; μ/τ decay → Pythia8 `decaySequence` |

PROPOSAL handles the kinematics for the secondaries internally, so CORSIKA simply has to read + translate those values into new particles and add them to CORSIKA's stack. 

**Some details:**

- Photohadronic losses are a special case, because **PROPOSAL knows no hadron physics**. It returns only the lost energy `E_loss` and a single placeholder pseudo-particle — a `Hadron` (PDG 81). No real photon or hadrons exist at this point; the sentinel just means "a photohadronic interaction of energy `E_loss` occurred — produce its hadrons." (Both muon/tau/electron `Photonuclear` and photon `Photoproduction` emit this type-81 sentinel and take the path below.)
CORSIKA intercepts the sentinel in `doHadronicPhotonInteraction()` and *reconstructs* a real hadronic collision from the energy bookkeeping: it synthesizes a projectile carrying the full `E_loss`, samples one target nucleon (proton or neutron, weighted by the medium's Z/A), runs that projectile + nucleon through a hadronic interaction model, and the model's emitted pions/kaons/nucleons are what go on the stack. The projectile type and model depend on the high/low-energy hadronic threshold:
    - above `heThreshold` (default `10^1.9 ≈ 79 GeV`): the photon is treated as a ρ⁰ vector meson (Vector Meson Dominance) and injected as `Code::Rho0` into the HE model (Sibyll-2.3d in `tambo_shower`), which does not accept photon projectiles;
    - at or below `heThreshold`: it is injected as a `Code::Photon` into the LE model (SOPHIA), which is natively a photon–nucleon photoproduction generator.

- For brems/epair (and photon pair-production), `CheckForLPM()` rejection-samples the Landau–Pomeranchuk–Migdal suppression *before* secondaries are emitted; a suppressed interaction is discarded and the muon restored unchanged. This is relevant in dense media, rarely in air.

- The PROPOSAL table settings (`emCut, v_cut`) are set up at CORSIKA instantiation, typically by loading in some pre-saved tables from a stable directory. CORSIKA internally has many many PROPOSAL tables, indexed by (particle species × medium × process); each table can have its own settings. See below for a description of how `tambo_shower` determines the values of the table settings.

<!-- In `tambo_shower` the wiring is `corsika::proposal::Interaction emCascade(env, sophia, sibyll->getHadronInteractionModel(), heThreshold)` and `corsika::proposal::ContinuousProcess<...> emContinuousProposal(env, dEdX)`, placed in the process sequence after the hadron/decay processes. Muon decay (μ→eνν) is handled separately by Pythia8 in `decaySequence`, not by PROPOSAL. -->

Source pointers (under `corsika/` in the CORSIKA 8 source tree; FASRC `/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika/`):

- `corsika/modules/PROPOSAL.hpp` — per-particle cross-section builders, the `v_cut`/`emCut` settings, the ionization `p_cut_no_vcut` exception, propagated-particle list.
- PROPOSAL `PROPOSAL/particle/Particle.h` — the `InteractionType` enum (values `1000000001`–`1000000016`).
- `corsika/modules/proposal/InteractionModel.inl` — `doInteraction()`: the loss-type → stack-particle mapping, the PDG-81 `Hadron` interception, `CheckForLPM()`.
- `corsika/modules/proposal/HadronicPhotonModel.inl` — `doHadronicPhotonInteraction()`: the Rho0/Photon projectile choice and the SOPHIA-vs-HE split at `heThreshold`.
- `corsika/modules/proposal/ContinuousProcess.inl` — sub-threshold continuous dE/dx, multiple scattering, the ≤10%-energy step limiter.
- `corsika/modules/proposal/ProposalProcessBase.inl` — table init, `getOptimizedEmCut()` / production-threshold table selection.
- `tambo_shower.cpp` (local, [src/corsika/tambo_shower/src/](../src/corsika/tambo_shower/src/)) — `set_energy_production_threshold`, `emCascade`/`emContinuousProposal` construction, process-sequence order.

</details>

<details>
<summary><h3>How does `tambo_shower` determine the PROPOSAL table settings (`emCut, v_cut`)?</h3></summary>

`v_cut` is a hardcoded framework constant in `corsika/modules/PROPOSAL.hpp` (0.01, overridden to 1 for ionization via `p_cut_no_vcut`). `emCut` is derived from `tambo_shower`'s five CLI energy cut flags (the `--emcut` … `--taucut` options in [tambo_shower.cpp](../src/corsika/tambo_shower/src/tambo_shower.cpp)):

| Flag | `tambo_shower` Default | Primary meaning |
|---|---|---|
| `--emcut`    | 10 GeV | min. kinetic energy of e± (and γ, unless `--gammacut` is given) |
| `--gammacut` | `--emcut` | min. kinetic energy of γ |
| `--hadcut`   | 1 GeV | min. kinetic energy of hadrons |
| `--mucut`    | 10 GeV | min. kinetic energy of muons |
| `--taucut`   | 10 GeV | min. kinetic energy of tau leptons |

The primary job of these flags is unrelated to PROPOSAL: each is the **cascade kill threshold** for its particle class, wired into CORSIKA's `ParticleCut` (`ParticleCut(emcut, gammacut, hadcut, mucut, taucut, …)`) — a particle is dropped from the shower once its kinetic energy falls below the threshold for its class. From TamboSim, `[corsika]` `em_ecut`, `gamma_ecut` (optional), `hadron_ecut` and `mu_ecut` set them; `--taucut` gets the muon cut.

Their secondary job sets the PROPOSAL `emCut`. `tambo_shower` takes the minimum of all five and applies that one value uniformly as the production threshold for every tracked species, so no particle is cut before it can be produced:

```cpp
auto const prod_threshold = std::min({emcut, gammacut, hadcut, mucut, taucut});
set_energy_production_threshold(Code::Electron, prod_threshold);  // …Positron, Photon,
set_energy_production_threshold(Code::MuMinus,  prod_threshold);  // …MuPlus, TauMinus, TauPlus
```

The framework's `getOptimizedEmCut()` then snaps `prod_threshold` onto the largest value in PROPOSAL's discrete cached-table menu `{1000, 100, 20, 10, 3, 1, 0.4, 0.25, 0.15, 0.05}` MeV that does not exceed it; that becomes the `emCut` every table is built with. 

Source pointers:

- `tambo_shower.cpp` (local, [src/corsika/tambo_shower/src/](../src/corsika/tambo_shower/src/)) — the `--emcut/--gammacut/--hadcut/--mucut/--taucut` declarations; in `main`, the `ParticleCut` construction, the `prod_threshold` min and the seven `set_energy_production_threshold` calls that follow it.
- `corsika/modules/PROPOSAL.hpp` — the hardcoded `v_cut` (0.01) and the ionization `p_cut_no_vcut` (v_cut→1); not driver-configurable.
- `corsika/modules/proposal/ProposalProcessBase.inl` — `getOptimizedEmCut()` and the discrete cached-table menu the production threshold is snapped onto.

</details>
