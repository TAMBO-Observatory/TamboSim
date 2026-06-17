# CORSIKA 8 Radio API Reference (pinned)

**Source tree:** `/home/claude/corsika_ref` — CORSIKA 8, branch `mesh-bvh-geometry-framework`.
**Canonical example:** `examples/cascade_examples/radio_em_shower.cpp`.
**Purpose:** authoritative, version-matched signatures for wiring radio into
`/workspace/TamboSim/src/corsika/tambo_shower/src/tambo_shower.cpp`. All line
references below are into `/home/claude/corsika_ref`. Downstream tasks MUST
reconcile against this file, not against memory of upstream CORSIKA.

> IMPORTANT NAMING NOTE: in this branch the "antenna" concept is actually named
> **Observer** / **ObserverCollection** / **TimeDomainObserver**. There is no
> `TimeDomainAntenna` or `AntennaCollection` class here. Use the Observer names.

---

## 1. Exact include paths

Copied verbatim from `examples/cascade_examples/radio_em_shower.cpp:46-53`:

```cpp
#include <corsika/modules/radio/RadioProcess.hpp>
#include <corsika/modules/radio/CoREAS.hpp>
#include <corsika/modules/radio/ZHS.hpp>
#include <corsika/modules/radio/observers/Observer.hpp>
#include <corsika/modules/radio/observers/TimeDomainObserver.hpp>
#include <corsika/modules/radio/detectors/ObserverCollection.hpp>
#include <corsika/modules/radio/propagators/NumericalIntegratingPropagator.hpp>
#include <corsika/modules/radio/propagators/DummyTestPropagator.hpp>
```

| Concept | Header (relative to `corsika_ref/`) |
|---|---|
| RadioProcess (base) | `corsika/modules/radio/RadioProcess.hpp` |
| CoREAS algorithm | `corsika/modules/radio/CoREAS.hpp` |
| ZHS algorithm | `corsika/modules/radio/ZHS.hpp` |
| Time-domain "antenna" (observer) | `corsika/modules/radio/observers/TimeDomainObserver.hpp` |
| Observer base CRTP | `corsika/modules/radio/observers/Observer.hpp` |
| Antenna collection / detector | `corsika/modules/radio/detectors/ObserverCollection.hpp` |
| Signal propagator (dummy, straight line, used by the example) | `corsika/modules/radio/propagators/DummyTestPropagator.hpp` |
| Signal propagator (numerical, ZHAireS/CoREAS-equivalent) | `corsika/modules/radio/propagators/NumericalIntegratingPropagator.hpp` |
| Signal propagator (tabulated flat atmosphere) | `corsika/modules/radio/propagators/TabulatedFlatAtmospherePropagator.hpp` |
| Propagator base CRTP | `corsika/modules/radio/propagators/RadioPropagator.hpp` |
| SignalPath (path result type) | `corsika/modules/radio/propagators/SignalPath.hpp` |

Implementations (`.inl`, auto-included at bottom of each header) live under
`corsika/detail/modules/radio/...` with the mirrored layout.

---

## 2. Time-domain observer (antenna) constructor

`corsika/modules/radio/observers/TimeDomainObserver.hpp:52-55`:

```cpp
TimeDomainObserver(std::string const& name, Point const& location,
                   CoordinateSystemPtr coordinateSystem, TimeType const& start_time,
                   TimeType const& duration, InverseTimeType const& sample_rate,
                   TimeType const ground_hit_time);
```

Argument order / types / units:

1. `name`              — `std::string const&` — observer label (free text id).
2. `location`          — `Point const&` — observer position.
3. `coordinateSystem`  — `CoordinateSystemPtr` — CS for the recorded E-field components.
4. `start_time`        — `TimeType const&` — waveform start time (time units, e.g. `_s`).
5. `duration`          — `TimeType const&` — waveform duration (time units).
6. `sample_rate`       — `InverseTimeType const&` — sampling rate (e.g. `_Hz`).
7. `ground_hit_time`   — `TimeType` (by value) — time primary hits ground on a straight vertical line.

Example call (`radio_em_shower.cpp:205-207`):

```cpp
TimeDomainObserver observer_coreas(name_coreas, point_coreas, rootCS,
                                   triggertime_coreas, duration, sampleRate,
                                   triggertime_coreas);
```

with (`radio_em_shower.cpp:167-168`):
```cpp
TimeType const duration{1e-6_s};
InverseTimeType const sampleRate{1e+9_Hz};
```
The example passes the per-observer `triggertime` for BOTH `start_time` and
`ground_hit_time`. `triggertime` is `(triggerpoint - point).getNorm() / constants::c`
(`radio_em_shower.cpp:202`), i.e. light travel time from the trigger point to the
observer.

---

## 3. Antenna collection ("add antenna" method)

Class: `ObserverCollection<TObserverImpl>` —
`corsika/modules/radio/detectors/ObserverCollection.hpp:16-17`.

The add method is **`addObserver`** (NOT `addAntenna`):

`ObserverCollection.hpp:30`:
```cpp
void addObserver(TObserverImpl const& observer);
```
Implementation `ObserverCollection.inl:13-17` simply `observers_.push_back(observer)`.

Other members (all in `ObserverCollection.hpp`):
- `int size() const;`                         (`:44`)  — returns `observers_.size()`
- `std::vector<TObserverImpl>& getObservers();`(`:51`)
- `std::vector<TObserverImpl> const& getObservers() const;` (`:58`)
- `TObserverImpl& at(std::size_t const i);`   (`:37`)
- `void reset();`                             (`:63`)

Declaration & usage in the example (`radio_em_shower.cpp:171-172, 208`):
```cpp
ObserverCollection<TimeDomainObserver> detectorCoREAS;
ObserverCollection<TimeDomainObserver> detectorZHS;
...
detectorCoREAS.addObserver(observer_coreas);
```
Default-constructed; no constructor arguments.

---

## 4. Radio signal propagator construction

The example uses the **DummyTestPropagator** via its factory
(`radio_em_shower.cpp:260`):
```cpp
auto SP = make_dummy_test_radio_propagator(env);
```

Factory + type (`DummyTestPropagator.hpp:57-62, 27-39`):
```cpp
template <typename TEnvironment>
DummyTestPropagator<TEnvironment> make_dummy_test_radio_propagator(TEnvironment const& env) {
  return DummyTestPropagator<TEnvironment>(env);
}
// ...
DummyTestPropagator(TEnvironment const& env);  // ctor
```
- Only argument is the **environment** (`env`). Note: `SP` is a value, and
  `RadioProcess` takes the propagator by **non-const lvalue reference** (see §5),
  so `SP` must be a named local (it is).
- The refractive index is NOT passed to the propagator directly; it comes from the
  environment. In the example it is set on the atmosphere build
  (`radio_em_shower.cpp:121, 123-125`):
  ```cpp
  double const refractive_index = 1.000327;
  media::create_5layer_atmosphere<EnvironmentInterface, MyExtraEnv>(
      env, media::AtmosphereId::LinsleyUSStd, center, refractive_index,
      media::Medium::AirDry1Atm, bField);
  ```
  The environment interface must include `media::IRefractiveIndexModel` (see
  `radio_em_shower.cpp:90-95`); DummyTestPropagator only works with a uniform
  refractive index, 2-point straight line (`DummyTestPropagator.hpp:18-26`).

Alternative propagators (NOT used by the example, but available):
- `make_numerical_integrating_radio_propagator(env, stepsize)` — extra arg
  `LengthType const stepsize` (`NumericalIntegratingPropagator.hpp:43, 59-64`). This
  is the ZHAireS/CoREAS-in-C7 equivalent and is slower.
- `TabulatedFlatAtmospherePropagator` (header present; see file for signature).

**Canonical choice for TamboSim:** match the example —
`make_dummy_test_radio_propagator(env)` — unless a curved/tabulated atmosphere is
required, in which case switch to the numerical integrating propagator.

---

## 5. RadioProcess template parameters + constructor

Template (`RadioProcess.hpp:25-28`):
```cpp
template <typename TObserverCollection, typename TRadioImpl, typename TPropagator>
class RadioProcess : public ContinuousProcess<
                         RadioProcess<TObserverCollection, TRadioImpl, TPropagator>>,
                     public BaseOutput {
```
Template parameters, in order:
1. `TObserverCollection` — the detector/collection type (`ObserverCollection<TimeDomainObserver>`).
2. `TRadioImpl`          — concrete algorithm (`CoREAS<...>` or `ZHS<...>`).
3. `TPropagator`         — propagator type (`decltype(SP)`).

Constructor (`RadioProcess.hpp:56`, impl `RadioProcess.inl:25-29`):
```cpp
RadioProcess(TObserverCollection& observers, TPropagator& propagator);
```
- `observers` taken by **non-const reference** and stored as `observers_` (ref).
- `propagator` taken by **non-const reference**, stored **by value** as `propagator_`
  (`RadioProcess.hpp:46-47`, `RadioProcess.inl:28-29`).

CoREAS / ZHS are subclasses that forward to this ctor. CoREAS
(`CoREAS.hpp:15-18, 31-33`):
```cpp
template <typename TRadioDetector, typename TPropagator>
class CoREAS final
    : public RadioProcess<TRadioDetector, CoREAS<TRadioDetector, TPropagator>, TPropagator> {
  ...
  template <typename... TArgs>
  CoREAS(TRadioDetector& detector, TArgs&&... args)
      : RadioProcess<TRadioDetector, CoREAS, TPropagator>(detector, args...) {}
```
ZHS is identical in shape (`ZHS.hpp:18-35`). Each exposes
`static constexpr auto algorithm = "CoREAS"` / `"ZHS"`.

Exact instantiation from the example (`radio_em_shower.cpp:263-265`, and ZHS 271-273):
```cpp
auto SP = make_dummy_test_radio_propagator(env);

RadioProcess<decltype(detectorCoREAS), CoREAS<decltype(detectorCoREAS), decltype(SP)>,
             decltype(SP)>
    coreas(detectorCoREAS, SP);

RadioProcess<decltype(detectorZHS), ZHS<decltype(detectorZHS), decltype(SP)>,
             decltype(SP)>
    zhs(detectorZHS, SP);
```
Note: the example declares the variable as the **base** `RadioProcess<Coll, CoREAS<...>, SP>`
type (not as `CoREAS<...>`), but constructs it with `(detectorCoREAS, SP)`. For
TamboSim CoREAS-only, the equivalent is the `coreas` line above.

---

## 6. Registering radio output with OutputManager

OutputManager constructed with the output directory name
(`radio_em_shower.cpp:248`):
```cpp
OutputManager output("radio_em_shower_outputs");
```
Radio processes are registered with a string label
(`radio_em_shower.cpp:268, 276`):
```cpp
output.add("CoREAS", coreas);
output.add("ZHS", zhs);
```
`RadioProcess` derives from `BaseOutput` (`RadioProcess.hpp:28`), which is what makes
it addable to `OutputManager`. The label string becomes the subdirectory name
holding that process's output.

---

## 7. Construction / wiring order (the example walkthrough)

From `radio_em_shower.cpp`:
1. Build `env` with a refractive-index-bearing interface and set
   `refractive_index` on the atmosphere (`:117-125`).
2. Pick waveform params: `duration` and `sampleRate` (`:167-168`).
3. Create the collections: `ObserverCollection<TimeDomainObserver> detectorCoREAS;`
   (`:171-172`).
4. Build each `TimeDomainObserver` and `detector.addObserver(...)` (`:205-208`, 225-227).
5. Construct propagator: `auto SP = make_dummy_test_radio_propagator(env);` (`:260`).
6. Construct the radio process(es): `RadioProcess<...> coreas(detectorCoREAS, SP);`
   (`:263-265`).
7. Register output: `output.add("CoREAS", coreas);` (`:268`).
8. Add the radio process into the cascade process sequence via `make_sequence(...)`
   (`:286-287`): `make_sequence(emCascade, emContinuous, longprof, coreas, zhs, tracks, observationLevel, cut);`
9. `Cascade EAS(env, tracking, sequence, output, stack); EAS.run();` (`:303-308`),
   bracketed by `output.startOfLibrary()` / `output.endOfLibrary()` (`:295, 318`).

---

## 8. Process category

`RadioProcess` is a **ContinuousProcess** — `RadioProcess.hpp:26-27`:
```cpp
class RadioProcess : public ContinuousProcess<
                         RadioProcess<TObserverCollection, TRadioImpl, TPropagator>>,
```
(also `public BaseOutput` for output registration).
It implements:
- `doContinuous(Step<Particle> const& step, bool const)` (`RadioProcess.hpp:67-68`).
- `getMaxStepLength(...)` returns `meter * infinity()` — never limits the step
  (`RadioProcess.inl:61-66`).

It is therefore placed in the process sequence as a continuous process (it appears
directly in `make_sequence(...)`).

---

## 9. On-disk output format

Writer: **Parquet**, via `ParquetStreamer output_` (`RadioProcess.hpp:49`).

- File name: **`observers.parquet`**, written into the per-process directory
  (the `output.add("CoREAS", ...)` label dir, under the OutputManager root dir).
  `RadioProcess.inl:72-73`:
  ```cpp
  output_.initStreamer((directory / ("observers.parquet")).string());
  ```
- Compression enabled at default level (`RadioProcess.inl:76`).
- Schema fields added (`RadioProcess.inl:80-90`): `Time`, `Ex`, `Ey`, `Ez`, all
  `parquet::Type::DOUBLE`, REQUIRED. A leading **`showerId_`** (event/shower id,
  `unsigned int`) is written as the first column of every row before Time/Ex/Ey/Ez
  (see the writer rows `RadioProcess.inl:134-136, 140-143`). So the on-disk column
  order per row is effectively: **shower id, Time, Ex, Ey, Ez**.
- One row per time sample, per observer, per shower; rows for all observers in a
  collection go into the same `observers.parquet` (`endOfShower` loops over all
  observers, `RadioProcess.inl:103-148`).

Units (from `getConfig()`, `RadioProcess.inl:169-172`):
```cpp
config["units"]["time"] = "ns";
config["units"]["frequency"] = "GHz";
config["units"]["electric field"] = "V/m";
config["units"]["distance"] = "m";
```
So: **Time in ns, E-field components (Ex,Ey,Ez) in V/m, distances in m.**

Algorithm-specific row generation (`RadioProcess.inl:127-145`):
- **CoREAS**: writes the waveform samples directly: row = `showerId, axis[i], dataX[i], dataY[i], dataZ[i]`.
- **ZHS**: writes the time-derivative of the vector potential (E = -dA/dt),
  using midpoint times and finite differences scaled by `sampleRate`.

A YAML side-config (per observer name, location in metres, plus the units block) is
emitted by `getConfig()` (`RadioProcess.inl:159-189`); OutputManager writes this as
the process config.

---

## 10. Is an EMPTY ObserverCollection a safe no-op? — YES.

Two independent guards make an empty collection a safe no-op:

1. `RadioProcess::doContinuous` returns immediately if there are no observers —
   `corsika/detail/modules/radio/RadioProcess.inl:37-38`:
   ```cpp
   // return immediately if radio process does not have any observers
   if (observers_.size() == 0) return ProcessReturn::Ok;
   ```
2. Even past that, `CoREAS::simulate` only acts inside
   `for (auto& observer : observers_.getObservers())` — an empty vector means the
   loop body never runs — `corsika/detail/modules/radio/CoREAS.inl:57`:
   ```cpp
   for (auto& observer : observers_.getObservers()) {
   ```
   (ZHS is structured the same way.)

`endOfShower`/`endOfLibrary` also loop over `observers_.getObservers()` and just write
nothing for an empty collection (`RadioProcess.inl:103, 174`). The `observers.parquet`
streamer is still initialized in `startOfLibrary` regardless, producing an empty (but
valid, schema-only) parquet file.

**Conclusion:** It is safe to always construct the `RadioProcess` and add it to the
sequence; conditionally enabling radio can be done simply by leaving the
`ObserverCollection` empty when radio is off. (To avoid even an empty parquet file,
gate whether the process is constructed / `output.add`-ed at all.)
