# make_core_plots.py
# Core MI figures from DESERT sweeps (distance = actual 3D D).
# Shows depths taken from the plotted slice (fresh per-mode).

import os, re, math, glob
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

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
    r"d(?P<d>\d+)_s(?P<sigma>[\d\.]+)_u(?P<u>[01])_f(?P<f>\d+)_rb(?P<rb>\d+)_seed(?P<seed>\d+)\.log$"
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
        plt.plot(g["distance_actual_m"], g["PDR"], marker="o", label=f"{sigma} S/m")
        plt.fill_between(g["distance_actual_m"], g["PDR_lo"], g["PDR_hi"], alpha=0.15)
    plt.xlabel("Distance D [m]")
    plt.ylabel("PDR (1 − PER)")
    plt.title(title)
    if subtitle: plt.suptitle(subtitle, y=0.98, fontsize=9)
    plt.grid(True, linestyle="--", alpha=0.4)
    plt.legend(title="Conductivity")
    plt.tight_layout()
    fn = os.path.join(OUTDIR, f"pdr_vs_distance_{sanitize(title)}.png")
    plt.savefig(fn, dpi=180)
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
        d = int(m.group("d"))
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
if M.empty:
    print("No UWMI_METRIC lines found in logs; skipping Eb/N0 and Rx-power plots.")
else:
    # Join with CSV to get true D if needed
    join_keys = ["dx_m","sigma_Sperm","uw2aw","f_khz","Rb_bps"]
    df_keys = df[join_keys + ["distance_actual_m"]].drop_duplicates()
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
            plt.plot(g["distance_actual_m"], g["EbN0_med"], marker="o", label=f"{sigma} S/m")
            plt.fill_between(g["distance_actual_m"], g["EbN0_p25"], g["EbN0_p75"], alpha=0.15)
        plt.axhline(10, linestyle="--", alpha=0.5)
        plt.xlabel("Distance D [m]")
        plt.ylabel("Eb/N0 [dB]")
        plt.title(title)
        if subtitle: plt.suptitle(subtitle, y=0.98, fontsize=9)
        plt.grid(True, linestyle="--", alpha=0.4)
        plt.legend(title="Conductivity")
        plt.tight_layout()
        fn = os.path.join(OUTDIR, f"ebn0_vs_distance_{sanitize(title)}.png")
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
            plt.plot(g["distance_actual_m"], g["Prx_med"], marker="o", label=f"{sigma} S/m")
            plt.fill_between(g["distance_actual_m"], g["Prx_p25"], g["Prx_p75"], alpha=0.15)
            # 1/d^6 reference anchored at first point
            d0 = float(g["distance_actual_m"].iloc[0])
            p0 = float(g["Prx_med"].iloc[0])
            ref = [p0 - 60.0*math.log10(max(1e-9, d/d0)) for d in g["distance_actual_m"]]
            plt.plot(g["distance_actual_m"], ref, linestyle=":", alpha=0.6)
        plt.xlabel("Distance D [m]")
        plt.ylabel("Rx Power [dBm]")
        plt.title(title)
        if subtitle: plt.suptitle(subtitle, y=0.98, fontsize=9)
        plt.grid(True, linestyle="--", alpha=0.4)
        plt.legend(title="Conductivity")
        plt.tight_layout()
        fn = os.path.join(OUTDIR, f"prx_vs_distance_{sanitize(title)}.png")
        plt.savefig(fn, dpi=180)
        # plt.savefig(fn.replace(".png",".pdf"))
        plt.close()
        print("Wrote:", fn)

print("\nDone. Figures are in:", OUTDIR)
