import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys

CSV = "uwmi_results_summary_all.csv"
SIGMA = float(sys.argv[1]) if len(sys.argv) > 1 else 4.0
MODE  = (sys.argv[2].lower() if len(sys.argv) > 2 else "both")  # both|uw|uw2aw

# --- robust load ---
try:
    df = pd.read_csv(CSV)
except Exception:
    df = pd.read_csv(CSV, header=None,
        names=["distance_m","sent","rcv","per","sigma_Sperm","period_s","stop_s","seed","uw2aw"])

# ensure columns
need = {"distance_m","sent","rcv","per","sigma_Sperm","uw2aw"}
for c in need:
    if c not in df.columns:
        if c == "uw2aw":
            df["uw2aw"] = 0
        else:
            df[c] = np.nan

for c in ["distance_m","sent","rcv","per","sigma_Sperm","uw2aw"]:
    df[c] = pd.to_numeric(df[c], errors="coerce")
df = df.dropna(subset=["distance_m","sent","rcv","sigma_Sperm"])
df = df[df["sent"] > 0]
df["pdr"] = np.clip(df["rcv"] / df["sent"], 0, 1)

df = df[np.isclose(df["sigma_Sperm"], SIGMA)]
if df.empty:
    raise SystemExit(f"No rows for sigma={SIGMA}")

def agg_err(sub):
    g = (sub.groupby("distance_m")["pdr"]
           .agg(["mean","std","count"])
           .reset_index().sort_values("distance_m"))
    return g

plt.figure(figsize=(7.2,4.6))
plotted = False

if MODE in ("both", "uw"):
    sub = df[df["uw2aw"] == 0]
    if not sub.empty:
        g = agg_err(sub)
        plt.errorbar(g["distance_m"], g["mean"], yerr=g["std"],
                     fmt="-o", capsize=4, linewidth=2, label="UW→UW (mean ± 1σ)")
        plotted = True

if MODE in ("both", "uw2aw"):
    sub = df[df["uw2aw"] == 1]
    if not sub.empty:
        g = agg_err(sub)
        plt.errorbar(g["distance_m"], g["mean"], yerr=g["std"],
                     fmt="-s", capsize=4, linewidth=2, label="UW→AW (mean ± 1σ)")
        plotted = True

if not plotted:
    raise SystemExit(f"No rows for sigma={SIGMA} in mode='{MODE}'")

plt.ylim(-0.05, 1.05); plt.xlim(left=0.8)
plt.xlabel("Distance (m)"); plt.ylabel("Packet Delivery Ratio (PDR)")
title_mode = {"both":"UW→UW vs UW→AW", "uw":"UW→UW only", "uw2aw":"UW→AW only"}[MODE]
plt.title(f"UwMI PDR vs Distance (σ={SIGMA} S/m; {title_mode})")
plt.grid(True, linestyle="--", alpha=0.5)
plt.legend()
plt.tight_layout()
out_base = f"plot_pdr_vs_distance_errorbars_sigma{SIGMA:g}_{MODE}"
plt.savefig(out_base + ".png", dpi=300)
plt.savefig(out_base + ".pdf")
print(f"Saved: {out_base}.(png|pdf)")
