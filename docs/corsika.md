
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
