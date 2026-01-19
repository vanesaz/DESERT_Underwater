# make_core_plots.py
# Core MI figures from DESERT sweeps (distance = actual 3D D).
# Shows depths taken from the plotted slice (fresh per-mode).

import os, re, math, glob
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
plt.rcParams.update({'font.size': 12})


CSV = "uwmi_results_summary_all.csv"
LOGDIR = "logs_sweep"
OUTDIR = "fig_core"
os.makedirs(OUTDIR, exist_ok=True)

# ---------------------------
# Helpers
# ---------------------------
def wilson_ci(k, n, z=1.96):
    if n <= 0: return (0.0, 0.0, 0.0)
    p = k / n
    denom = 1 + z*z/n
    center = (p + z*z/(2*n)) / denom
    half = z*math.sqrt((p*(1-p) + z*z/(4*n))/n) / denom
    lo, hi = max(0.0, center - half), min(1.0, center + half)
    return (p, lo, hi)

def sanitize(title):
    return title.replace("→","to").replace("/", "_").replace(" ", "_")

def most_common_depths(df_mode):
    """
    Pick the most frequent (z1,z2) pair in df_mode.
    Falls back to median if value_counts is empty.
    Back-compatible with older pandas (no names= in reset_index).
    """
    if {"z1_m","z2_m"}.issubset(df_mode.columns) and not df_mode.empty:
        vc = df_mode[["z1_m","z2_m"]].round(3).value_counts()
        pairs = vc.reset_index()
        # value_counts becomes a column named 0 on older pandas
        if 0 in pairs.columns:
            pairs = pairs.rename(columns={0: "count"})
        elif "count" not in pairs.columns:
            pairs["count"] = vc.values
        # The first row is the most frequent pair
        if not pairs.empty:
            z1 = float(pairs.iloc[0]["z1_m"])
            z2 = float(pairs.iloc[0]["z2_m"])
            return z1, z2
        # fallback: median
        med = df_mode[["z1_m","z2_m"]].median().round(3)
        return float(med["z1_m"]), float(med["z2_m"])
    return None, None

uwmi_metric_re = re.compile(
    r"UWMI_METRIC\s+.*?Prx_dBm=([-\d\.eE]+).*?EbN0_dB=([-\d\.eE]+)",
    re.IGNORECASE
)
fname_re = re.compile(
    r"d(?P<d>\d+(?:\.\d+)?)_s(?P<sigma>[\d\.]+)_u(?P<u>[01])_f(?P<f>\d+)_rb(?P<rb>\d+)_seed(?P<seed>\d+)\.log$"
)

# ---------------------------
# Load master CSV
# ---------------------------
df = pd.read_csv(CSV)

need = {"distance_actual_m","dx_m","sent","rcv","per","sigma_Sperm","uw2aw","f_khz","Rb_bps","B_Hz","z1_m","z2_m"}
missing = need - set(df.columns)
if missing:
    raise SystemExit(f"CSV is missing columns: {missing}")

# Aggregate PDR with Wilson CI
grp_cols = ["distance_actual_m","sigma_Sperm","uw2aw","f_khz","Rb_bps","B_Hz"]
agg = df.groupby(grp_cols, as_index=False).agg(
    sent_sum=("sent","sum"),
    rcv_sum=("rcv","sum")
)
rows = []
for _, r in agg.iterrows():
    p, lo, hi = wilson_ci(int(r["rcv_sum"]), int(r["sent_sum"]))
    out = {k: r[k] for k in grp_cols}
    out.update({"PDR": p, "PDR_lo": lo, "PDR_hi": hi})
    rows.append(out)
P = pd.DataFrame(rows)

# Default slice
SL_F, SL_RB, SL_B = 200, 1000, 5000
core = P[(P["f_khz"]==SL_F) & (P["Rb_bps"]==SL_RB) & (P["B_Hz"]==SL_B)]
if core.empty:
    print("WARNING: No rows match the default slice; plotting all instead.")
    core = P.copy()

# ---------------------------
# PDR vs Distance (two plots)
# ---------------------------
for mode in sorted(core["uw2aw"].unique()):
    sub = core[core["uw2aw"]==mode].copy()
    if sub.empty: 
        continue

    df_slice = df[(df["uw2aw"]==mode) & (df["f_khz"]==SL_F) & (df["Rb_bps"]==SL_RB) & (df["B_Hz"]==SL_B)]
    z1, z2 = most_common_depths(df_slice)
    subtitle = f"Depths: z1={z1} m, z2={z2} m" if z1 is not None else ""

    title = f"PDR vs Distance ({'UW→AW' if int(mode)==1 else 'UW→UW'})"
    plt.figure()
    for sigma, g in sub.groupby("sigma_Sperm"):
        g = g.sort_values("distance_actual_m")
        plt.plot(g["distance_actual_m"], g["PDR"], marker="o", label=f"{sigma} S/m", linewidth=2)
        plt.fill_between(g["distance_actual_m"], g["PDR_lo"], g["PDR_hi"], alpha=0.2)



    plt.xlabel("Distance D [m]")
    plt.ylabel("PDR (1 − PER)")
    plt.title(title)
    if subtitle: plt.suptitle(subtitle, y=0.98, fontsize=9)
    plt.grid(True, linestyle="--", alpha=0.4)
    plt.legend(title="Conductivity")
    plt.tight_layout()
    fn = os.path.join(OUTDIR, f"pdr_vs_distance_{sanitize(title)}.png")
    plt.savefig(fn, dpi=180)
    plt.savefig(fn.replace(".png", ".pdf"))
    # plt.savefig(fn.replace(".png",".pdf"))
    plt.close()
    print("Wrote:", fn)

# ---------------------------
# Parse metrics from logs (optional)
# ---------------------------
metrics = []
if os.path.isdir(LOGDIR):
    for path in glob.glob(os.path.join(LOGDIR, "*.log")):
        base = os.path.basename(path)
        m = fname_re.search(base)
        if not m: 
            continue
        d = round(float(m.group("d")), 3)
        sigma = float(m.group("sigma"))
        uw = int(m.group("u"))
        fk = int(m.group("f"))
        rb = int(m.group("rb"))
        seed = int(m.group("seed"))
        with open(path, "r", errors="ignore") as fh:
            for line in fh:
                mm = uwmi_metric_re.search(line)
                if not mm: 
                    continue
                prx_dbm = float(mm.group(1))
                ebn0_db = float(mm.group(2))
                metrics.append({
                    "dx_m": d,
                    "sigma_Sperm": sigma,
                    "uw2aw": uw,
                    "f_khz": fk,
                    "Rb_bps": rb,
                    "seed": seed,
                    "Prx_dBm": prx_dbm,
                    "EbN0_dB": ebn0_db
                })

M = pd.DataFrame(metrics)


print("\n=== QUICK DATA CHECKS ===")

# 1) How many unique distances per (sigma, mode)?
try:
    nun = (df.groupby(["sigma_Sperm","uw2aw"])["distance_actual_m"]
             .nunique()
             .rename("n_distances")
             .reset_index())
    print("\nUnique distances per (sigma, uw2aw):")
    print(nun.to_string(index=False))
except Exception as e:
    print("Distance-per-sigma check failed:", e)

# 2) Do seeds look constant?
if "seed" in df.columns:
    vc = df["seed"].value_counts()
    print("\nTop seeds in CSV:")
    print(vc.head(10).to_string())

# 3) Are there rows that won’t merge on the strict key (incl. seed)?
keys = ["distance_actual_m","sigma_Sperm","uw2aw","f_khz","Rb_bps","seed"]
if not M.empty and set(keys).issubset(df.columns) and set(keys).issubset(M.columns):
    left  = df[keys].drop_duplicates()
    right = M[keys].drop_duplicates()
    only_in_M  = right.merge(left, on=keys, how="left", indicator=True)\
                      .query('_merge=="left_only"')
    only_in_df = left.merge(right, on=keys, how="left", indicator=True)\
                     .query('_merge=="left_only"')
    print(f"\nUnmatched-in-df (present in M, missing in df) : {len(only_in_M)}")
    print(f"Unmatched-in-M  (present in df, missing in M) : {len(only_in_df)}")
else:
    print("\nStrict merge check skipped (M empty or seed key not present).")

print("=== END CHECKS ===\n")


if M.empty:
    print("No UWMI_METRIC lines found in logs; skipping Eb/N0 and Rx-power plots.")
else:
    # Join with CSV to get true D if needed
    join_keys = ["dx_m","sigma_Sperm","uw2aw","f_khz","Rb_bps"]
    df_keys = df[join_keys + ["distance_actual_m"]].drop_duplicates()
    for c in ["dx_m", "sigma_Sperm", "uw2aw", "f_khz", "Rb_bps"]:
        if c in M.columns:
            M[c] = M[c].astype(float)
        if c in df_keys.columns:
            df_keys[c] = df_keys[c].astype(float)
     # round the distance key to 3 decimals on BOTH sides
    M["dx_m"] = M["dx_m"].round(3)
    df_keys["dx_m"] = df_keys["dx_m"].round(3)

    M = (M.merge(df_keys, on=join_keys, how="left")
           .assign(distance_actual_m=lambda x: x["distance_actual_m"].fillna(x["dx_m"])))
    gcols = ["distance_actual_m","sigma_Sperm","uw2aw","f_khz","Rb_bps"]
    Magg = M.groupby(gcols).agg(
        EbN0_med=("EbN0_dB","median"),
        EbN0_p25=("EbN0_dB", lambda x: np.percentile(x,25)),
        EbN0_p75=("EbN0_dB", lambda x: np.percentile(x,75)),
        Prx_med=("Prx_dBm","median"),
        Prx_p25=("Prx_dBm", lambda x: np.percentile(x,25)),
        Prx_p75=("Prx_dBm", lambda x: np.percentile(x,75)),
        n=("EbN0_dB","count")
    ).reset_index()

    coreM = Magg[(Magg["f_khz"]==SL_F) & (Magg["Rb_bps"]==SL_RB)]
    if coreM.empty:
        print("Metric logs found, but none match the default slice; plotting all instead.")
        coreM = Magg.copy()

    # Eb/N0 vs Distance
    for mode in sorted(coreM["uw2aw"].unique()):
        sub = coreM[coreM["uw2aw"]==mode]
        if sub.empty: continue
        df_slice = df[(df["uw2aw"]==mode) & (df["f_khz"]==SL_F) & (df["Rb_bps"]==SL_RB) & (df["B_Hz"]==SL_B)]
        z1, z2 = most_common_depths(df_slice)
        subtitle = f"Depths: z1={z1} m, z2={z2} m" if z1 is not None else ""
        title = f"Eb/N0 vs Distance ({'UW→AW' if int(mode)==1 else 'UW→UW'})"
        plt.figure()
        for sigma, g in sub.groupby("sigma_Sperm"):
            g = g.sort_values("distance_actual_m")
            plt.plot(g["distance_actual_m"], g["EbN0_med"], marker="o", label=f"{sigma} S/m", linewidth=2)
            plt.fill_between(g["distance_actual_m"], g["EbN0_p25"], g["EbN0_p75"], alpha=0.2)
        thr_label = r"Required $E_b/N_0$ ≈ 10 dB"
        plt.axhline(10, linestyle="--", color="gray", alpha=0.6, linewidth=1.3, label=thr_label)
        plt.xlabel("Distance D [m]")
        plt.ylabel("Eb/N0 [dB]")
        plt.title(title)
        if subtitle: plt.suptitle(subtitle, y=0.98, fontsize=9)
        plt.grid(True, linestyle="--", alpha=0.4)
        plt.legend(title="Conductivity")
        plt.tight_layout()
        fn = os.path.join(OUTDIR, f"ebn0_vs_distance_{sanitize(title)}.png")
        plt.savefig(fn.replace(".png", ".pdf"))
        plt.savefig(fn, dpi=180)
        # plt.savefig(fn.replace(".png",".pdf"))
        plt.close()
        print("Wrote:", fn)

    # Rx Power vs Distance (+ 1/d^6 ref)
    for mode in sorted(coreM["uw2aw"].unique()):
        sub = coreM[coreM["uw2aw"]==mode]
        if sub.empty: continue
        df_slice = df[(df["uw2aw"]==mode) & (df["f_khz"]==SL_F) & (df["Rb_bps"]==SL_RB) & (df["B_Hz"]==SL_B)]
        z1, z2 = most_common_depths(df_slice)
        subtitle = f"Depths: z1={z1} m, z2={z2} m" if z1 is not None else ""
        title = f"Rx Power vs Distance ({'UW→AW' if int(mode)==1 else 'UW→UW'})"
        plt.figure()
        for sigma, g in sub.groupby("sigma_Sperm"):
            g = g.sort_values("distance_actual_m")
            plt.plot(g["distance_actual_m"], g["Prx_med"], marker="o", label=f"{sigma} S/m", linewidth=2)
            plt.fill_between(g["distance_actual_m"], g["Prx_p25"], g["Prx_p75"], alpha=0.2)
            # 1/d^6 reference anchored at first point
            d0 = float(g["distance_actual_m"].iloc[0])
            p0 = float(g["Prx_med"].iloc[0])
            ref = [p0 - 60.0*math.log10(max(1e-9, d/d0)) for d in g["distance_actual_m"]]
            plt.plot(g["distance_actual_m"], ref, linestyle=":", alpha=0.6, linewidth=2)

            x_lab = g["distance_actual_m"].iloc[-1]
            y_lab = ref[-1] + 1.5
            plt.text(x_lab, y_lab, r"$1/d^6$ ref", fontsize=9, ha="center", va="bottom")
             # --- Noise floor line N = k T Beff * F (in dBm), taken from this slice ---
            # Parameters pulled from the actual runs in this slice:
        if not df_slice.empty:
            k = 1.38064852e-23
            T = float(df_slice["Tnoise_K"].median() if "Tnoise_K" in df_slice else 290.0)
            NF_dB = float(df_slice["NF_dB"].median() if "NF_dB" in df_slice else 18.0)
            F_lin = 10.0 ** (NF_dB / 10.0)
            B_Hz  = float(df_slice["B_Hz"].median())
            f0_Hz = float(df_slice["f_khz"].median() * 1000.0)
            Qval  = float(df_slice["Q"].median()) if "Q" in df_slice else 50.0
            Beff  = max(1.0, min(B_Hz, f0_Hz / max(Qval, 1e-6)))
            N_W   = k * T * Beff * F_lin
            N_dBm = 10.0 * np.log10(N_W * 1000.0 + 1e-30)
            plt.axhline(N_dBm, color="gray", linestyle="--", alpha=0.6, label=f"Noise floor ~ {N_dBm:.1f} dBm", linewidth=1.3)
        plt.xlabel("Distance D [m]")
        plt.ylabel("Rx Power [dBm]")
        plt.title(title)
        if subtitle: plt.suptitle(subtitle, y=0.98, fontsize=9)
        plt.grid(True, linestyle="--", alpha=0.4)
        plt.legend(title="Conductivity")
        plt.tight_layout()
        fn = os.path.join(OUTDIR, f"prx_vs_distance_{sanitize(title)}.png")
        plt.savefig(fn, dpi=180)
        plt.savefig(fn.replace(".png", ".pdf"))
        # plt.savefig(fn.replace(".png",".pdf"))
        plt.close()
        print("Wrote:", fn)


# ---------------------------
# F3: BPSK theory PER vs Eb/N0 with simulation points (robust pairing)
# ---------------------------
from math import erfc

# 1) Theory curve using the packet size found in the CSV
pkt_bytes = int(df["pkt_bytes"].mode().iat[0])  # most common payload size
Nbits = pkt_bytes * 8
eps = 1e-8

ebn0_db = np.linspace(-2, 20, 200)
ebn0_lin = 10.0**(ebn0_db/10.0)
ber = 0.5 * np.vectorize(erfc)(np.sqrt(ebn0_lin))  # coherent BPSK in AWGN
per_theory = np.clip(1.0 - (1.0 - ber)**Nbits, eps, 1.0)

plt.figure()
plt.semilogy(ebn0_db, per_theory, label=f"BPSK theory (no FEC), {pkt_bytes} B")

if not M.empty:
    # Preferred “strict” key (includes seed)
    strict_keys = ["distance_actual_m","sigma_Sperm","uw2aw","f_khz","Rb_bps","seed"]
    loose_keys  = ["distance_actual_m","sigma_Sperm","uw2aw","f_khz","Rb_bps"]

    # Build PER per run from CSV
    DF_runs = df[strict_keys + ["per"]].copy() if set(strict_keys).issubset(df.columns) else df[loose_keys + ["per"]].copy()

    # Eb/N0 per run from logs (median within a run)
    M_runs = (M.groupby(strict_keys, as_index=False)["EbN0_dB"].median()
                if set(strict_keys).issubset(M.columns)
                else M.groupby(loose_keys, as_index=False)["EbN0_dB"].median())

    # Pair PER with Eb/N0 for the same run/bin
    paired = DF_runs.merge(M_runs, on=(strict_keys if set(strict_keys).issubset(DF_runs.columns) and set(strict_keys).issubset(M_runs.columns) else loose_keys), how="inner")

    # Plot UW→UW, two conductivities
    for sig, mk in [(0.05, 'o'), (4.0, 's')]:
        PP = paired[(paired["uw2aw"] == 0) &
                    (paired["sigma_Sperm"] == sig) &
                    (paired["f_khz"] == SL_F) &
                    (paired["Rb_bps"] == SL_RB)]
        if PP.empty:
            continue

        # Aggregate across runs/seeds per distance for a clean curve of dots
        JJ = (PP.groupby("distance_actual_m", as_index=False)
                .agg(EbN0_dB=("EbN0_dB","median"),
                     per=("per","median")))
        JJ["per"] = JJ["per"].clip(lower=eps, upper=1.0)

        plt.semilogy(JJ["EbN0_dB"], JJ["per"], mk, label=f"Sim (σ={sig} S/m)")

plt.xlabel(r"$E_b/N_0$ [dB]")
plt.ylabel("PER")
plt.title("PER vs Eb/N0: BPSK theory vs simulation (UW→UW)")
plt.grid(True, which="both", linestyle=":", alpha=0.4)
plt.legend(title="Curves")
plt.tight_layout()
f3 = os.path.join(OUTDIR, "theory_PER_vs_EbN0_with_points.png")
plt.savefig(f3, dpi=180)
plt.close()
print("Wrote:", f3)


# ============ F8: PDR vs D families for UW→AW at varying z2 ============
SL_SIGMA = 4.0
sub = P[(P["uw2aw"]==1) & (P["sigma_Sperm"]==SL_SIGMA) &
        (P["f_khz"]==SL_F) & (P["Rb_bps"]==SL_RB) & (P["B_Hz"]==SL_B)].copy()
if not sub.empty and "z2_m" in df.columns:
    # pull z2 from raw df and merge
    z2map = (df[["distance_actual_m","sigma_Sperm","uw2aw","f_khz","Rb_bps","B_Hz","z2_m"]]
             .drop_duplicates())
    sub = sub.merge(z2map, on=["distance_actual_m","sigma_Sperm","uw2aw","f_khz","Rb_bps","B_Hz"], how="left")
    plt.figure()
    for z2, g in sub.groupby("z2_m"):
        gg = g.sort_values("distance_actual_m")
        if len(gg)<2: continue
        plt.plot(gg["distance_actual_m"], gg["PDR"], marker="o", label=f"z2={z2:.1f} m")
        plt.fill_between(gg["distance_actual_m"], gg["PDR_lo"], gg["PDR_hi"], alpha=0.15)
    plt.xlabel("Distance D [m]"); plt.ylabel("PDR (1 − PER)")
    plt.title("PDR vs Distance (UW→AW), depth family σ=4.0 S/m")
    plt.grid(True, linestyle="--", alpha=0.4); plt.legend(ncol=2)
    plt.tight_layout()
    fn = os.path.join(OUTDIR, "F8_pdr_depth_family_UWtoAW_sigma4.0.png")
    plt.savefig(fn, dpi=180); plt.savefig(fn.replace(".png",".pdf")); plt.close(); print("Wrote:", fn)

# ============ F9: Heatmap PDR(D, z2) for UW→AW, σ=0.05 ============
if not sub.empty:
    H = sub.pivot_table(index="z2_m", columns="distance_actual_m", values="PDR", aggfunc="mean")
    if H.size>0:
        plt.figure()
        im = plt.imshow(H.values, aspect="auto", origin="lower",
                        extent=[min(H.columns), max(H.columns), min(H.index), max(H.index)],
                        vmin=0, vmax=1)
        plt.colorbar(im, label="PDR")
        plt.xlabel("Distance D [m]"); plt.ylabel("z2 [m]")
        plt.title("PDR heatmap (UW→AW, σ=4.0 S/m)")
        plt.tight_layout()
        fn = os.path.join(OUTDIR, "F9_pdr_heatmap_D_vs_z2_UWtoAW_sigma4.0.png")
        plt.savefig(fn, dpi=180); plt.savefig(fn.replace(".png",".pdf")); plt.close(); print("Wrote:", fn)


# ============ F10/F11: Array PDR vs D (1x1/2x2/3x3) ============

if "Nt_coils" in df.columns and "Nr_coils" in df.columns and "auto_scale_R" in df.columns:

    # Slice only the array experiments we're interested in:
    # UW→UW, sigma=0.05 S/m, 200 kHz, 1 kbps, 5 kHz
    arr_slice = df[
        (df["f_khz"] == SL_F) &
        (df["Rb_bps"] == SL_RB) &
        (df["B_Hz"] == SL_B) &
        (df["sigma_Sperm"] == 0.05) &
        (df["uw2aw"] == 0)
    ].copy()

    if not arr_slice.empty:
        # Aggregate PDR per (distance, array size, auto_scale_R)
        grp_cols_arr = ["distance_actual_m", "Nt_coils", "auto_scale_R"]
        aggA = arr_slice.groupby(grp_cols_arr, as_index=False).agg(
            sent_sum=("sent", "sum"),
            rcv_sum=("rcv", "sum")
        )

        rows = []
        for _, r in aggA.iterrows():
            p, lo, hi = wilson_ci(int(r["rcv_sum"]), int(r["sent_sum"]))
            rows.append({
                "distance_actual_m": r["distance_actual_m"],
                "Nt_coils": int(r["Nt_coils"]),
                "auto_scale_R": int(r["auto_scale_R"]),
                "PDR": p,
                "PDR_lo": lo,
                "PDR_hi": hi,
            })
        P_arr = pd.DataFrame(rows)

        # --- F10/F11: PDR vs D for each array size, for autoR=0 and autoR=1 ---
        for autoR in (0, 1):
            AA = P_arr[P_arr["auto_scale_R"] == autoR].copy()
            if AA.empty:
                continue

            plt.figure()
            for n, g in AA.groupby("Nt_coils"):
                gg = g.sort_values("distance_actual_m")
                plt.plot(
                    gg["distance_actual_m"], gg["PDR"],
                    marker="o",
                    label=f"{int(n)}×{int(n)}"
                )
                plt.fill_between(
                    gg["distance_actual_m"],
                    gg["PDR_lo"], gg["PDR_hi"],
                    alpha=0.15
                )

            plt.xlabel("Distance D [m]")
            plt.ylabel("PDR (1 − PER)")
            title = "Array gain (UW→UW, σ=0.05 S/m, spacing=0.04 m)"
            if autoR:
                title += " —equal copper mass"
            plt.title(title, fontsize=11)
            plt.grid(True, linestyle="--", alpha=0.4)
            plt.legend()
            plt.tight_layout()

            fn = os.path.join(OUTDIR, f"F10_F11_array_pdr_autoR{autoR}.png")
            plt.savefig(fn, dpi=180)
            plt.savefig(fn.replace(".png", ".pdf"))
            plt.close()
            print("Wrote:", fn)

        # ============ F12: Range@PDR≥0.8 vs array size ============

        def range_at(Pdf, thresh=0.8):
            Pdf = Pdf.sort_values("distance_actual_m")
            hit = Pdf[Pdf["PDR"] >= thresh]
            return float(hit["distance_actual_m"].max()) if not hit.empty else 0.0

        R = []
        for autoR in (0, 1):
            AA = P_arr[P_arr["auto_scale_R"] == autoR]
            for n, g in AA.groupby("Nt_coils"):
                R.append({
                    "Nt_coils": int(n),
                    "autoR": autoR,
                    "range": range_at(g)
                })

        if R:
            RR = pd.DataFrame(R)
            for autoR in (0, 1):
                plt.figure()
                sub = RR[RR["autoR"] == autoR].sort_values("Nt_coils")
                plt.bar(sub["Nt_coils"].astype(str), sub["range"])
                plt.xlabel("Array size (N×N)")
                plt.ylabel("Range @ PDR≥0.8 [m]")
                t = "Equal copper mass" if autoR else "Raw coil count"
                plt.title(f"Range vs array size — {t} (UW→UW, σ=0.05 S/m)", fontsize = 12)
                plt.tight_layout()
                fn = os.path.join(OUTDIR, f"F12_range_vs_array_autoR{autoR}.png")
                plt.savefig(fn, dpi=180)
                plt.savefig(fn.replace(".png", ".pdf"))
                plt.close()
                print("Wrote:", fn)


# ============ F13: Range@0.8 vs frequency (derive from P) ============
def range_from_P(Pdf, target=0.8):
    Pdf = Pdf.sort_values("distance_actual_m")
    x = Pdf["distance_actual_m"].values
    y = Pdf["PDR"].values

    # If never above target, range is 0
    if not (y >= target).any():
        return 0.0

    # index of last point with PDR >= target
    idx = np.where(y >= target)[0][-1]

    # if even the farthest point is above target, just return it
    if idx == len(x) - 1:
        return float(x[idx])

    # interpolate between idx (>=target) and idx+1 (<target)
    x1, y1 = x[idx], y[idx]
    x2, y2 = x[idx+1], y[idx+1]

    if y2 == y1:   # degenerate, avoid division by zero
        return float(x1)

    alpha = (target - y1) / (y2 - y1)
    return float(x1 + alpha * (x2 - x1))


freqs = sorted(P["f_khz"].unique())
rows=[]
for uw in (0,1):
    for sig in (0.05, 4.0):
        for fk in freqs:
            SL = P[(P["uw2aw"]==uw)&(P["sigma_Sperm"]==sig)&(P["f_khz"]==fk)&(P["Rb_bps"]==SL_RB)]
            if SL.empty: continue
            rng = range_from_P(SL, 0.8)
            rows.append({"uw2aw":uw,"sigma":sig,"f_khz":fk,"range":rng})
Rfreq = pd.DataFrame(rows)

if not Rfreq.empty:
    for uw in (0,1):
        plt.figure()
        for sig, g in Rfreq[Rfreq["uw2aw"]==uw].groupby("sigma"):
            gg=g.sort_values("f_khz")
            plt.plot(gg["f_khz"], gg["range"], marker="o", label=f"σ={sig} S/m")

        plt.xlabel("Frequency f0 [kHz]")
        plt.ylabel("Range @ PDR≥0.8 [m]")
        plt.title(f"Range vs frequency ({'UW→AW' if uw==1 else 'UW→UW'})")
        plt.grid(True, linestyle="--", alpha=0.4)
        plt.legend()

        # >>> make y-axis identical in both figures <<<
        # Option A: strict 0–14 (will clip the few points >14 m)
        # plt.ylim(0, 14)

        # Option B (recommended): 0–16, keeps everything visible
        plt.ylim(0, 16)

        plt.tight_layout()
        fn = os.path.join(OUTDIR, f"F13_range_vs_freq_uw{uw}.png")
        plt.savefig(fn, dpi=180); plt.savefig(fn.replace(".png",".pdf")); plt.close(); print("Wrote:", fn)


# ============ F14: Contour of range vs (f0, Rb) at fixed Q ============

pairs = P[["f_khz", "Rb_bps"]].drop_duplicates().values.tolist()
CR = pd.DataFrame()  # default empty

if len(pairs) > 4:
    rows_CR = []
    for uw in (0, 1):
        for sig in (0.05,):
            for fk in sorted(P["f_khz"].unique()):
                for rb in sorted(P["Rb_bps"].unique()):
                    SL = P[
                        (P["uw2aw"] == uw)
                        & (P["sigma_Sperm"] == sig)
                        & (P["f_khz"] == fk)
                        & (P["Rb_bps"] == rb)
                    ]
                    if SL.empty:
                        continue
                    rows_CR.append({
                        "uw2aw": uw,
                        "sigma": sig,
                        "f_khz": fk,
                        "Rb_bps": rb,
                        "range": range_from_P(SL),
                    })
    CR = pd.DataFrame(rows_CR)

if not CR.empty:
    for uw in (0, 1):
        Z = CR[CR["uw2aw"] == uw].pivot_table(
            index="Rb_bps", columns="f_khz", values="range", aggfunc="max"
        )
        if Z.shape[0] < 2 or Z.shape[1] < 2:
            print(f"Skipping F14 contour for uw2aw={uw}: not enough (f0,Rb) points")
            continue

        plt.figure()
        cs = plt.contourf(Z.columns, Z.index, Z.values, levels=12)
        plt.colorbar(cs, label="Range @ PDR≥0.8 [m]")
        plt.xlabel("f0 [kHz]")
        plt.ylabel("Rb [bps]")
        plt.title(f"Range contour (σ=0.05 S/m, {'UW→AW' if uw==1 else 'UW→UW'})")
        plt.tight_layout()
        fn = os.path.join(OUTDIR, f"F14_range_contour_uw{uw}.png")
        plt.savefig(fn, dpi=180)
        plt.savefig(fn.replace(".png", ".pdf"))
        plt.close()
        print("Wrote:", fn)


# ============ F15: CSV table for τ∈{0.9,0.8} ============
Trows=[]
for tau in (0.9,0.8):
    for uw in (0,1):
        for sig in (0.05,4.0):
            SL = P[(P["uw2aw"]==uw)&(P["sigma_Sperm"]==sig)&(P["f_khz"]==SL_F)&(P["Rb_bps"]==SL_RB)]
            Trows.append({"tau":tau,"mode":"UW→AW" if uw==1 else "UW→UW","sigma":sig,
                          "range":range_from_P(SL, tau)})
Ttab = pd.DataFrame(Trows)
Ttab.to_csv(os.path.join(OUTDIR,"F15_range_table_tau.csv"), index=False)
print("Wrote:", os.path.join(OUTDIR,"F15_range_table_tau.csv"))


# ============ F16: Range@0.8 vs Q (TABLE) ============
if "Q" in df.columns:
    QQ = P[
        (P["uw2aw"] == 0) &
        (P["sigma_Sperm"] == 0.05) &
        (P["f_khz"] == SL_F) &
        (P["Rb_bps"] == SL_RB)
    ]
    if not QQ.empty:
        qmap = df[[
            "distance_actual_m", "Q", "uw2aw",
            "sigma_Sperm", "f_khz", "Rb_bps", "B_Hz"
        ]].drop_duplicates()

        QQ = QQ.merge(
            qmap,
            on=["distance_actual_m", "uw2aw", "sigma_Sperm",
                "f_khz", "Rb_bps", "B_Hz"],
            how="left"
        )

        rows = []
        for q, g in QQ.groupby("Q"):
            rows.append({
                "Q": float(q),
                "range_m": range_from_P(g, 0.8)
            })

        Qtab = pd.DataFrame(rows).sort_values("Q")
        if not Qtab.empty:
            # Round nicely for the thesis
            Qtab["Q"] = Qtab["Q"].astype(int)
            Qtab["range_m"] = Qtab["range_m"].round(2)

            # Save as CSV
            csv_path = os.path.join(OUTDIR, "F16_range_vs_Q_table.csv")
            Qtab.to_csv(csv_path, index=False)
            print("Wrote table CSV:", csv_path)

# ============ F17: Range@0.8 vs NF (TABLE) ============
if "NF_dB" in df.columns:
    NN = P[
        (P["uw2aw"] == 0) &
        (P["sigma_Sperm"] == 0.05) &
        (P["f_khz"] == SL_F) &
        (P["Rb_bps"] == SL_RB)
    ]
    if not NN.empty:
        nmap = df[[
            "distance_actual_m", "NF_dB", "uw2aw",
            "sigma_Sperm", "f_khz", "Rb_bps", "B_Hz"
        ]].drop_duplicates()

        NN = NN.merge(
            nmap,
            on=["distance_actual_m", "uw2aw", "sigma_Sperm",
                "f_khz", "Rb_bps", "B_Hz"],
            how="left"
        )

        rows = []
        for nf, g in NN.groupby("NF_dB"):
            rows.append({
                "NF_dB": float(nf),
                "range_m": range_from_P(g, 0.8)
            })

        Ntab = pd.DataFrame(rows).sort_values("NF_dB")
        if not Ntab.empty:
            Ntab["NF_dB"] = Ntab["NF_dB"].astype(int)
            Ntab["range_m"] = Ntab["range_m"].round(2)

            csv_path = os.path.join(OUTDIR, "F17_range_vs_NF_table.csv")
            Ntab.to_csv(csv_path, index=False)
            print("Wrote table CSV:", csv_path)

            

# ============ F18: Rate–range frontier over (B, Rb) (TABLE) ============

BB = P[
    (P["uw2aw"] == 0) &
    (P["sigma_Sperm"] == 0.05) &
    (P["Rb_bps"].isin([1000, 2000]))
]

if not BB.empty:
    rows = []
    for (b, rb), g in BB.groupby(["B_Hz", "Rb_bps"]):
        rows.append({
            "B_kHz": b / 1000.0,
            "Rb_bps": int(rb),
            "range_m": range_from_P(g, 0.8)
        })
    FT = pd.DataFrame(rows).sort_values(["B_kHz", "Rb_bps"])

    if not FT.empty:
        FT["B_kHz"] = FT["B_kHz"].astype(int)   # 2, 5, 8
        FT["range_m"] = FT["range_m"].round(2)

        csv_path = os.path.join(OUTDIR, "F18_rate_range_frontier_table.csv")
        FT.to_csv(csv_path, index=False)
        print("Wrote table CSV:", csv_path)

    
