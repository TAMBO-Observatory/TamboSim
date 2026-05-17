
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

`tambo_shower` registers the terrain as a single closed `TriangularMesh` node carrying a `HomogeneousMedium` (standard rock, 2.65 g/cm³). The atmosphere is a *nested single-child chain* of filled balls centred at Earth's centre (universe → outermost layer → … → innermost layer; see the layered-atmosphere Q+A). The terrain mesh **straddles several of these layers** — an Earth-skimming particle can be logically resident in different atmosphere layers at different points along its crossing of the terrain. For the particle to actually lose energy in the rock, *two* independent CORSIKA mechanisms must each resolve to the rock node **from whatever layer the particle currently occupies** — the **point→medium lookup** and the **tracking step-boundary detection**. A *third* requirement is distinct: when the particle *leaves* the rock it must be returned to the medium that geometrically contains it, not left in whatever node the tracker happens to assign. Handling all three correctly is what the `CRITICAL` comment at the rock-volume registration in [tambo_shower.cpp](../src/corsika/tambo_shower/src/tambo_shower.cpp) and the `RockExitRelocator` process together guard.

The first two are addressed by how the rock node is registered: as an **overlap-exclusion** (`excludeOverlapWith`; see the overlap-exclusion Q+A above) on every atmosphere layer the terrain spans — from the innermost layer up to the highest one the terrain reaches (found via `getContainingNode` at the terrain's maximum radius) — and *owned* (via `addChild`) by the topmost of those spanned layers. The third is addressed by a dedicated boundary process. All three then work properly: 

- **1. Point→medium lookup.** `getContainingNode(p)` descends from the universe root: at each level it recurses into the *first child* that `contains(p)`; if no child contains `p` it consults that node's **excluded-overlap nodes** via `excludes(p)`; only if that also fails does it return the layer itself. Because the atmosphere layers are filled balls, the descent always bottoms out at the innermost layer whose sphere contains `p`. With the rock registered as an excluded-overlap on that layer, a sub-surface point inside the mesh resolves to the rock (excludes are consulted *before* the layer's own air, *after* its children), so the medium at a rock point is StandardRock no matter which layer the point falls in. The `ShowerAxis` builds its longitudinal grammage axis with this same full-tree `getContainingNode` walk at construction, so the grammage coordinate correctly accumulates rock density along the axis.

- **2. Tracking step-boundary detection.** Resolving the medium at a point isn't enough — the tracker must also *end the step* at the rock surface so the medium switches mid-flight. For the particle's *current* logical node, `nextIntersect` tests both its **direct children and its excluded-overlap nodes**, one level deep (no tree descent). Because the rock is an excluded-overlap of every layer the terrain spans, whichever layer the particle is logically in as it reaches the terrain has the rock mesh in its candidate set: the step ends at the rock surface, the logical node becomes the rock node, and StandardRock + PROPOSAL losses apply. The rock is owned by (a child of) the topmost spanned layer, so on exit `getParent()` returns a real atmosphere layer — never the universe, which would erase the particle.

- **3. Correct logical-node placement on rock exit.** `nextIntersect` sets a particle's post-exit logical node to `rock.getParent()` (the topmost spanned layer) regardless of where along the mesh the exit point actually is, so that node is not necessarily the layer geometrically containing the exit point. `tambo_shower` registers `RockExitRelocator`, a `BoundaryCrossingProcess` in the process sequence: on every boundary crossing whose `from` node is the rock, it re-resolves the logical node to the atmosphere layer that actually contains the exit point, `setNode`s the particle to it, **and displaces the particle 2 µm along its momentum so it leaves the rock surface for unambiguous air**. `Cascade::step` calls boundary-crossing processes immediately after assigning the tracker's node and before the next step (then returns) — and the next step's `getTrack` reads `getPosition()` fresh, with no pre-computed trajectory — so both the node correction and the position nudge are in force on the very next step. If the particle is still skimming the terrain it re-enters rock normally on a later step via the excluded-overlap candidate set.

  Crucially it resolves among **layers**, not via `getContainingNode` — and it picks the layer *before* applying its own nudge, with the particle still sitting *exactly on the rock surface* (where the tracker hands it off). At that on-surface point `getContainingNode` is the wrong tool: it consults the rock through `excludes()`, and `TriangularMesh::contains()` at an on-surface point is degenerate — it drops the local face via the 1 µm `boundaryPadding` and votes by parity of the *remaining* crossings, which for non-convex terrain can come out "inside" — so it can resolve back to the very rock the particle is leaving and ping-pong the boundary with near-zero progress. The question actually needed is "which atmosphere *layer* contains this point?", a pure `Sphere::contains` (altitude vs the layer boundary): robust exactly on the rock surface and structurally unable to return the rock. Since the atmosphere is a single-child nested-ball chain and the rock mesh is only ever a non-index-0 child of its owning layer, descending the index-0 child chain while each layer's volume contains the point yields the innermost containing layer (inner layer below its boundary, next layer above) without ever reaching the rock. Ownership therefore only governs the `getParent()`-never-universe safety; exit-layer placement is exact and ping-pong-free. Having chosen the layer at that surface point, the relocator then displaces the particle 2 µm (twice the mesh `boundaryPadding`) along its momentum — the particle is leaving the rock, so this carries it deeper into the resolved layer's air — so the next step's intersection test starts from an unambiguously-in-air point rather than the boundary-padding-degenerate surface, and resolves cleanly in the resolved layer.

In summary: the rock is registered as an overlap-exclusion on each atmosphere layer the terrain spans and owned by the topmost of them, so both the point→medium lookup and the tracking step resolve to the rock from whatever layer a particle occupies while crossing the terrain; and `RockExitRelocator` re-resolves the logical node to the correct atmosphere layer on every rock exit — by a robust layer-only sphere descent, deliberately *not* the mesh-inclusive `getContainingNode` — then nudges the particle 2 µm off the surface into that layer's air, so the post-exit step uses the geometrically-correct medium from an unambiguous starting point.

As a defensive backstop, `tambo_shower` also registers `RockInterfaceTripwire`, a passive per-step process asserting the structural invariant *logical node == rock ⇒ the position is geometrically inside the rock*. It mutates nothing; it only counts steps that violate the invariant (logically in rock yet outside it) and, if the violation persists for a sustained run of steps (a particle would otherwise bleed StandardRock dE/dx while in air and silently range out before any readout), aborts the run with diagnostics rather than emit a misleading shower output. It is a no-op when the terrain mesh is disabled.

Source pointers (under `corsika/` in the CORSIKA 8 source tree; FASRC `/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika/`):

- `detail/media/VolumeTreeNode.inl` — `getContainingNode(p)` (lines 36–53) recurses into the first child containing `p`, else consults `excludes(p)` (excluded-overlap nodes) before returning the node itself; `excludes()` (lines 21–29) scans `excludedNodes_`; `excludeOverlapWith` registers a *non-owning* pointer in `excludedNodes_`; `addChild` sets `parentNode_` (ownership).
- `detail/media/LayeredSphericalAtmosphereBuilder.inl` (lines 161–170) — `assemble()` chains the atmosphere layers as a single nested-child path under `Universe` (outermost → innermost).
- `detail/modules/tracking/Intersect.inl` — `nextIntersect` tests the current logical node's direct children (lines 59–81) **and** its excluded-overlap nodes (lines 85–104) for the next entry; one level, no descent. On exit it sets the next node to `volumeNode.getParent()` (line 53).
- `detail/framework/core/Cascade.inl` (lines ~283–295) — on a volume-boundary crossing `Cascade::step` calls `particle.setNode(nextVol)`, then dispatches `doBoundaryCrossing(particle, from, to)` (particle mutable), then returns — the hook `RockExitRelocator` uses. The framework's own post-step check (lines ~303–311) calls `getContainingNode(position)` and merely *logs* a disagreement without acting on it; `RockExitRelocator` deliberately avoids that mesh-inclusive lookup on rock exit (see below).
- `framework/process/BoundaryCrossingProcess.hpp` — the `doBoundaryCrossing(particle, from, to)` interface `RockExitRelocator` implements.
- `detail/framework/geometry/TriangularMesh.inl` — `contains()` (lines 63–95) is a 3-ray parity vote that excludes hits within `boundaryPadding` (1 µm, line 88); this is exactly why a point left *on* the rock surface is degenerate under `getContainingNode`, and why `RockExitRelocator` resolves among layer spheres instead. `node.getVolume().contains(p)` (the layer-sphere test it reuses) is the same primitive `Intersect.inl:29` and `getContainingNode` use.
- `detail/media/ShowerAxis.inl` (lines 37–65) — the grammage axis (`X_[]`) is built at construction by integrating density sampled via `universe->getContainingNode(p)` (full tree descent), so it includes rock density along the axis.
- `tambo_shower.cpp` (local, [src/corsika/tambo_shower/src/](../src/corsika/tambo_shower/src/)) — terrain mesh registered as a StandardRock `HomogeneousMedium`, registered via `excludeOverlapWith` on each spanned atmosphere layer and owned by the topmost spanned layer; `RockExitRelocator` (a `BoundaryCrossingProcess` in the process sequence) re-resolves the logical node by layer-only sphere descent and nudges the particle 2 µm off the surface on every rock exit; `RockInterfaceTripwire` (a passive `ContinuousProcess`) aborts the run if the logical-node-implies-inside invariant is persistently violated.

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

The terrain rock Q+A above relies on two mechanisms — the point→medium lookup (`getContainingNode`) and the tracking step-boundary detection (`nextIntersect`) — both resolving to the same `TriangularMesh`. However, they ask geometrically *different* questions about that surface: the medium lookup asks "is this point inside the rock?" (a point-in-mesh test), while the tracker asks "where along this trajectory does it cross the rock surface?" (a ray–surface intersection). 

In principle, if these questions were answered by independent code, they could disagree at the boundary by a numerical hair. Grazing, near-tangent Earth-skimming trajectories against a triangulated surface, such as those simulated in TAMBO, are exactly the regime where such disagreements surface. This failure would be pathological, not cosmetic: the tracker could step the particle "into rock" while the medium lookup at that point still returns air (so rock physics never actually applies), or the particle could thrash on the boundary — entering and immediately re-exiting indefinitely. 

In CORSIKA, however, the two mechanisms above do agree, by construction. The curved leap-frog tracker delegates the mesh intersection to the straight-line tracker, which ray-casts with the *same* BVH `intersectRayAll` and `boundaryPadding` that `TriangularMesh::contains()` uses. So the step-boundary geometry and the point-medium geometry are literally the same computation — they cannot disagree about where the rock surface is.

Source pointers (under `corsika/`; FASRC `/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika/`):

- `detail/modules/tracking/TrackingLeapFrogCurved.inl` (lines 352–356, 358–372) — the curved tracker delegates `TriangularMesh` intersection to the straight tracker and dispatches a mesh-volume node by `dynamic_cast`.
- `detail/modules/tracking/TrackingStraight.inl` (lines 167–238) — mesh intersection via `mesh.intersectRayAll` + `boundaryPadding`, entry/exit decided from `mesh.contains()`, consistent with the point-medium test.
- `detail/framework/geometry/TriangularMesh.inl` (lines 63–95) — `contains()` is a 3-ray majority-vote parity test, robust for closed meshes and independent of triangle winding.

</details>

<details>
<summary><h3>Does the terrain mesh break CORSIKA's convex-volume tracking assumption?</h3></summary>

CORSIKA's tracker documents and relies on a convention that every volume primitive is *convex*. In `nextIntersect`, the point where a particle leaves its current volume is taken as a single exit time from that volume's intersection — the in-source comment states "all Volume primitives must be convex, thus the last entry is always the exit point." Terrain is decidedly non-convex: a near-horizontal, Earth-skimming path can pierce the rock surface several times (into a ridge, out over a valley, into the next ridge), and a naive first-in/last-out pairing would mis-identify which segments are rock and which are air. This is a real assumption the generic primitive path depends on (spheres and planes satisfy it trivially) — not merely a comment.

However, the `TriangularMesh` intersection deliberately does not rely on this assumption. Rather than returning a convex entry/exit pair, `TrackingStraight::intersect(…, TriangularMesh)` collects *all* ray–surface crossings, sorts them, and calls `mesh.contains(position)` to decide whether the *next* crossing is an entry or an exit — returning only that next-boundary pair (the source comment there reads "For non-convex meshes, this determines if next intersection is entry or exit"). Because the tracker re-evaluates at every boundary it stops at, each step is handed a freshly `contains()`-disambiguated crossing, so a multi-crossing non-convex path is resolved correctly, segment by segment. The convex convention therefore governs the generic primitive path but is intentionally bypassed for the mesh — by design, not by accident.

Source pointers (under `corsika/`; FASRC `/n/holylfs05/LABS/arguelles_delgado_lab/Lab/TAMBO/common_software/corsika/corsika/`):

- `detail/modules/tracking/Intersect.inl` (lines ~37–55) — `nextIntersect` takes a single `getExit()` from the current volume's `Intersections` as where the particle leaves it; the in-source comment states the convex convention this relies on.
- `detail/modules/tracking/TrackingStraight.inl` (lines ~211–238) — the `TriangularMesh` intersect sorts all ray–surface crossings and uses `mesh.contains(position)` to classify the next crossing as entry vs exit (explicit non-convex handling), returning only the next-boundary pair.
- `detail/framework/geometry/TriangularMesh.inl` (lines 63–95) — `contains()` is the 3-ray majority-vote parity test used for that entry/exit decision.

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

`v_cut` is a hardcoded framework constant in `corsika/modules/PROPOSAL.hpp` (0.01, overridden to 1 for ionization via `p_cut_no_vcut`). `emCut` is derived from the `tambo_shower`'s four CLI energy cut flags: ([tambo_shower.cpp:279–295](../src/corsika/tambo_shower/src/tambo_shower.cpp#L279-L295)):

| Flag | `tambo_shower` Default | Primary meaning |
|---|---|---|
| `--emcut`  | 10 GeV | min. kinetic energy of γ / e± |
| `--hadcut` | 1 GeV | min. kinetic energy of hadrons |
| `--mucut`  | 10 GeV | min. kinetic energy of muons |
| `--taucut` | 10 GeV | min. kinetic energy of tau leptons |

The primary job of these flags is unrelated to PROPOSAL: each is the **cascade kill threshold** for its particle class, wired into CORSIKA's `ParticleCut` at [line 726](../src/corsika/tambo_shower/src/tambo_shower.cpp#L726) (`ParticleCut(emcut, emcut, hadcut, mucut, taucut, …)`) — a particle is dropped from the shower once its kinetic energy falls below the threshold for its class.

Their secondary job sets the PROPOSAL `emCut`. `tambo_shower` takes the minimum of all four and applies that one value uniformly as the production threshold for every tracked species ([lines 729–736](../src/corsika/tambo_shower/src/tambo_shower.cpp#L729-L736)):

```cpp
auto const prod_threshold = std::min({emcut, hadcut, mucut, taucut});
set_energy_production_threshold(Code::Electron, prod_threshold);  // …Positron, Photon,
set_energy_production_threshold(Code::MuMinus,  prod_threshold);  // …MuPlus, TauMinus, TauPlus
```

The framework's `getOptimizedEmCut()` then snaps `prod_threshold` onto the largest value in PROPOSAL's discrete cached-table menu `{1000, 100, 20, 10, 3, 1, 0.4, 0.25, 0.15, 0.05}` MeV that does not exceed it; that becomes the `emCut` every table is built with. 

Source pointers:

- `tambo_shower.cpp` (local, [src/corsika/tambo_shower/src/](../src/corsika/tambo_shower/src/)) — `--emcut/--hadcut/--mucut/--taucut` declarations (lines 279–295); `ParticleCut` construction (line 726); `prod_threshold` min and the seven `set_energy_production_threshold` calls (lines 729–736).
- `corsika/modules/PROPOSAL.hpp` — the hardcoded `v_cut` (0.01) and the ionization `p_cut_no_vcut` (v_cut→1); not driver-configurable.
- `corsika/modules/proposal/ProposalProcessBase.inl` — `getOptimizedEmCut()` and the discrete cached-table menu the production threshold is snapped onto.

</details>
