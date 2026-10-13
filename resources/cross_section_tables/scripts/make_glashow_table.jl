# make_glashow_table.jl
#
# Writes group `GR_nuebar` into resources/cross_section_tables/cross_sections.h5:
# the ratio of the corrected to the tree-level Glashow-resonance cross section
# (ν̄_e e⁻ → W⁻), for the total and for the τ channel, on a log-energy grid.
# `GlashowCrossSection(; corrections=true)` multiplies its tree-level result by these.
#
# Corrections (the treatment cited by Ding & Liu, arXiv:2607.26128):
#   1. Doppler broadening from atomic-electron motion: Loewy, Nussinov & Glashow,
#      arXiv:1407.4415, in the corrected form of Huang, Lindner & Volmer,
#      JHEP 11 (2023) 164, arXiv:2303.13706, Eqs. (2.3), (A.3)-(A.10).
#      Hydrogen-like shell momentum distributions with screened exponents
#      μ_nl = Z_eff/n (Clementi & Raimondi, J. Chem. Phys. 38 (1963) 2686).
#   2. Initial-state radiation off the electron: exponentiated structure function of
#      Garcia, Gauld, Heijboer & Rojo, JCAP 09 (2020) 025, arXiv:2004.04756, Eq. (2.8),
#      with μ_F = M_W. See also Gauld, PRD 100 (2019) 091301, arXiv:1905.03792.
#
# ISR also shifts the τ energy spectrum (the W is produced with a backward boost). That
# shift is not modelled. Only the rate is corrected.
#
# Usage (from the repo root):
#   julia --project=. resources/cross_section_tables/scripts/make_glashow_table.jl [target]
# target = "standard_rock" (default, Z = 11 like PDG standard rock) or "ice" (H₂O,
# the Huang et al. validation case). Re-run if the tree-level constants in
# src/injection/glashow.jl change.

using TamboSim
using HDF5
using QuadGK
using Printf
using Unitful

const T = TamboSim
const α = 1 / 137.035999084
const MW2 = T.GLASHOW_MW^2
const ME  = T.GLASHOW_ME

# --- Atomic shells: (weight per target electron, n, l, μ in 1/a₀) -----------------------
# μ_nl = Z_eff/n from Clementi & Raimondi (1963). O values as quoted by Huang et al.
const SHELLS = Dict(
    # H₂O: (2 F_H + 8 F_O)/10, Huang et al. Eq. (A.11)
    "ice" => [
        (2 / 10, 1, 0, 1.0),      # H 1s
        (2 / 10, 1, 0, 7.6579),   # O 1s
        (2 / 10, 2, 0, 2.2458),   # O 2s
        (4 / 10, 2, 1, 2.2266),   # O 2p
    ],
    # Standard rock, Z = 11 (Na-like): 1s² 2s² 2p⁶ 3s¹.
    # Z_eff: 1s 10.626, 2s 6.571, 2p 6.802, 3s 2.507.
    "standard_rock" => [
        (2 / 11, 1, 0, 10.626),
        (2 / 11, 2, 0, 6.571 / 2),
        (6 / 11, 2, 1, 6.802 / 2),
        (1 / 11, 3, 0, 2.507 / 3),
    ],
)

# Momentum distributions f_nl(k), k in units of 1/a₀, ∫₀^∞ f dk = 1 (Huang Eqs. A.4-A.10).
function f_shell(n, l, μ, k)
    if (n, l) == (1, 0)
        return 32 * μ^5 * k^2 / (π * (μ^2 + k^2)^4)
    elseif (n, l) == (2, 0)
        return 32 * μ^5 * (3μ^2 * k - k^3)^2 / (3π * (μ^2 + k^2)^6)
    elseif (n, l) == (2, 1)
        return 512 * μ^7 * k^4 / (3π * (μ^2 + k^2)^6)
    elseif (n, l) == (3, 0)
        return 1024 * μ^7 * (μ^3 * k - μ * k^3)^2 / (5π * (μ^2 + k^2)^8)
    end
    error("shell ($n, $l) not implemented")
end

# --- Tree level as a function of s (GeV²), in cm² ---------------------------------------
# Same formula as glashow_sigma_lepton_tree, written in s so it can be smeared.
function sigma_tree_s(s, m_lepton)
    r = m_lepton^2 / s
    r >= 1 && return 0.0
    σ = T.GLASHOW_GF^2 * MW2^2 / (3π) * s * (1 - r)^2 * (1 + r / 2) /
        ((s - MW2)^2 + MW2 * T.GLASHOW_GAMMAW^2)
    return σ * T.GLASHOW_HBARC2
end
sigma_tot_s(s) = sigma_tree_s(s, 0.0) / T.GLASHOW_BR_LNU
sigma_tau_s(s) = sigma_tree_s(s, T.GLASHOW_MTAU)

# --- Doppler: σ_D(s0) = Σ w ∫dk f(k) · 1/(2 s0 β) ∫_{s0(1-β)}^{s0(1+β)} σ(s) ds, β = α k --------
function smear_over_s(g, s0, β)
    lo, hi = s0 * (1 - β), s0 * (1 + β)
    pts = lo < MW2 < hi ? (lo, MW2, hi) : (lo, hi)
    return quadgk(g, pts...; rtol=1e-8)[1] / (2 * s0 * β)
end

function doppler(g, s0, shells)
    total = 0.0
    for (w, n, l, μ) in shells
        kmax = 0.999 / α
        integrand(k) = (β = α * k; β < 1e-9 ? g(s0) : smear_over_s(g, s0, β)) * f_shell(n, l, μ, k)
        # β = αk < 1 caps k; breakpoints beyond kmax would reverse an interval.
        pts = filter(<(kmax), [μ, 4μ, 30μ])
        total += w * quadgk(integrand, 0.0, pts..., kmax; rtol=1e-7)[1]
    end
    return total
end

# --- ISR: σ(s) = ∫₀¹ dx Γ_ee(x) σ_D(x s), Garcia et al. Eq. (2.8) -------------------------
const β_ISR = α / π * (log(MW2 / ME^2) - 1)
const Γ1β   = quadgk(t -> t^β_ISR * exp(-t), 0, Inf)[1]   # Γ(1 + β)
const C_ISR = exp(-β_ISR * Base.MathConstants.eulergamma + 3β_ISR / 4) / Γ1β

function isr(gD, s)
    # Singular part: C ∫ β(1-x)^(β-1) gD(x s) dx = C ∫₀¹ gD((1 - t^(1/β)) s) dt.
    xres = MW2 / s
    tbreak = 0 < xres < 1 ? ((1 - xres)^β_ISR,) : ()
    sing = quadgk(t -> gD((1 - t^(1 / β_ISR)) * s), 0.0, tbreak..., 1.0; rtol=1e-7)[1]
    xbreak = 0 < xres < 1 ? (xres,) : ()
    hard = quadgk(x -> (1 + x) * gD(x * s), 0.0, xbreak..., 1.0; rtol=1e-7)[1]
    return C_ISR * sing - β_ISR / 2 * hard
end

# σ_D is tabulated on a fine log-s grid and interpolated log-log for the ISR integral.
# Below E = 1e5 GeV the Doppler smearing is irrelevant (far from the peak), so tree level
# is used there. The 0.05% step resolves the ~5% (in s) resonance width.
function doppler_interpolant(g, shells)
    ls = range(log(2ME * 1e5), log(2ME * 3e9), step=5e-4)
    vals = [log(doppler(g, exp(l), shells)) for l in ls]
    function gD(s)
        s <= 0 && return 0.0
        l = log(s)
        (l < first(ls) || l > last(ls)) && return g(s)
        i = clamp(floor(Int, (l - first(ls)) / step(ls)) + 1, 1, length(ls) - 1)
        w = (l - ls[i]) / step(ls)
        return exp((1 - w) * vals[i] + w * vals[i+1])
    end
    return gD
end

function peak_report(name, f, es)
    tree = [sigma_tot_s(2ME * E) for E in es]
    vals = [f(2ME * E) for E in es]
    @printf("  %-18s peak %.4e cm²  (%+.1f%% vs tree)  at E = %.4f PeV\n",
            name, maximum(vals), 100 * (maximum(vals) / maximum(tree) - 1),
            es[argmax(vals)] / 1e6)
end

function main(target)
    shells = SHELLS[target]
    for (w, n, l, μ) in shells
        norm = quadgk(k -> f_shell(n, l, μ, k), 0, Inf; rtol=1e-10)[1]
        abs(norm - 1) < 1e-6 || error("f_$(n)$(l) not normalised: $norm")
    end
    @printf("target = %s, β_ISR = %.5f, C_ISR = %.5f\n", target, β_ISR, C_ISR)

    t0 = time()
    gD_tot = doppler_interpolant(sigma_tot_s, shells)
    gD_tau = doppler_interpolant(sigma_tau_s, shells)
    @printf("Doppler tables: %.1f s\n", time() - t0)

    es_peak = exp10.(range(6.7, 6.9, length=2001))
    println("Peak check:")
    peak_report("tree", sigma_tot_s, es_peak)
    peak_report("Doppler only", gD_tot, es_peak)
    peak_report("ISR only", s -> isr(sigma_tot_s, s), es_peak)
    peak_report("Doppler + ISR", s -> isr(gD_tot, s), es_peak)

    target == "standard_rock" || return println("target = $target is a validation run; nothing written.")

    # Output grid: 0.1% log steps over 1e5 - 1e9 GeV.
    t0 = time()
    es = exp.(range(log(1e5), log(1e9), step=1e-3))
    ratio_total = [isr(gD_tot, 2ME * E) / sigma_tot_s(2ME * E) for E in es]
    ratio_tau   = [isr(gD_tau, 2ME * E) / sigma_tau_s(2ME * E) for E in es]
    @printf("ratio grid (%d points): %.1f s\n", length(es), time() - t0)
    for E in (1e6, 4e6, 6.32e6, 1e7, 1e8)
        i = argmin(abs.(es .- E))
        @printf("  E = %.3g GeV: ratio_total = %.4f, ratio_tau = %.4f\n",
                es[i], ratio_total[i], ratio_tau[i])
    end

    out = joinpath(pkgdir(TamboSim), "resources", "cross_section_tables", "cross_sections.h5")
    h5open(out, "r+") do f
        haskey(f, "GR_nuebar") && delete_object(f, "GR_nuebar")
        g = create_group(f, "GR_nuebar")
        g["energies"]    = collect(es)
        g["ratio_total"] = ratio_total
        g["ratio_tau"]   = ratio_tau
        attributes(g)["target"] = target
        attributes(g)["description"] =
            "Glashow resonance (Doppler + ISR)/tree ratio; see make_glashow_table.jl"
    end
    println("Wrote group GR_nuebar to $out")
end

main(isempty(ARGS) ? "standard_rock" : ARGS[1])
