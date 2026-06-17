# Pure-math helpers for the radio energy-fluence footprint.
#
# Deliberately free of any plotting / CORSIKA-IO dependencies (stdlib
# `LinearAlgebra` only), so they can be unit-tested locally without installing
# CairoMakie or reading real CORSIKA output. The plotting/IO front-end lives in
# `plot_radio_footprint.jl`, which `include`s this file.

using LinearAlgebra

const EPS0 = 8.8541878128e-12  # vacuum permittivity [F/m]
const C = 2.99792458e8         # speed of light [m/s]
const EV = 1.602176634e-19     # 1 eV in joules [J/eV]
const NS_TO_S = 1e-9           # observer waveform times are stored in ns

"""
    _median(x) -> Float64

Median of a vector, implemented here to avoid a `Statistics` dependency so the
pure functions load with stdlib only.
"""
function _median(x)
    s = sort(collect(float.(x)))
    n = length(s)
    n == 0 && return 0.0
    isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2
end

"""
    energy_fluence(times, ex, ey, ez) -> Float64

Energy fluence of a single antenna waveform, in eV/m². Computes
`ε₀·c·Σ|E|²·Δt` (the time-integrated Poynting flux of a plane wave in vacuum)
in J/m², then converts to eV/m².

`times` are in NANOSECONDS; `ex, ey, ez` are the E-field components in V/m,
aligned with `times`. `Δt` is the median sample spacing (robust to a stray
timestamp; the writer emits a uniform grid).
"""
function energy_fluence(times, ex, ey, ez)
    ts = float.(times) .* NS_TO_S
    dt = length(ts) > 1 ? _median(diff(ts)) : 0.0
    e2 = float.(ex) .^ 2 .+ float.(ey) .^ 2 .+ float.(ez) .^ 2
    fluence_J_m2 = EPS0 * C * sum(e2) * dt
    return fluence_J_m2 / EV
end

"""
    project_to_shower_plane(positions, core, v, B) -> (a, b)

Project antenna positions into the shower plane spanned by the `v × B` and
`v × (v × B)` axes.

`positions` is an `N×3` matrix of ECEF positions (metres); `core`, `v`, `B` are
length-3 vectors (only `B`'s direction matters). Returns vectors `a` and `b`
with `a = (r − core)·ê₁`, `ê₁ = (v×B)/|v×B|`, and `b = (r − core)·ê₂`,
`ê₂ = (v×(v×B))/|v×(v×B)|`.
"""
function project_to_shower_plane(positions, core, v, B)
    vv = float.(vec(collect(v)))
    bb = float.(vec(collect(B)))
    cc = float.(vec(collect(core)))

    vxB = cross(vv, bb)
    e1 = vxB / norm(vxB)
    vxvxB = cross(vv, vxB)
    e2 = vxvxB / norm(vxvxB)

    P = float.(positions)              # N×3
    rel = P .- reshape(cc, 1, 3)       # broadcast core over rows
    a = rel * e1                       # length-N
    b = rel * e2
    return a, b
end
