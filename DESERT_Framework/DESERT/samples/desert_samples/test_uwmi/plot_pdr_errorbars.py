import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys

CSV = "uwmi_results_summary_all.csv"
SIGMA = float(sys.argv[1]) if len(sys.argv) > 1 else 4.0

try:
    df = pd.read_csv(CSV)
except Exception:
    df = pd.read_csv(CSV, header=None,
                     names=["distance_m","sent","rcv","per","sigma_Sperm","period_s","stop_s","seed"])

for c in ["distance_m","sent","rcv","per","sigma_Sperm"]:
    df[c] = pd.to_numeric(df[c], errors="coerce")
df = df.dropna(subset=["distance_m","sent","rcv","sigma_Sperm"])
df = df[df["sent"] > 0]
df["pdr"] = np.clip(df["rcv"] / df["sent"], 0, 1)

df = df[np.isclose(df["sigma_Sperm"], SIGMA)]
g = (df.groupby("distance_m")["pdr"]
       .agg(["mean","std","count"])
       .reset_index().sort_values("distance_m"))
if g.empty:
    raise SystemExit(f"No rows for sigma={SIGMA}")

plt.figure(figsize=(7.2,4.6))
plt.errorbar(g["distance_m"], g["mean"], yerr=g["std"],
             fmt="-o", capsize=4, linewidth=2, label="PDR (mean ± 1σ)")
plt.ylim(-0.05, 1.05); plt.xlim(left=0.8)
plt.xlabel("Distance (m)"); plt.ylabel("Packet Delivery Ratio (PDR)")
plt.title(f"UwMI PDR vs Distance (σ={SIGMA} S/m)")
plt.grid(True, linestyle="--", alpha=0.5)
plt.tight_layout()
out_base = f"plot_pdr_vs_distance_errorbars_sigma{SIGMA:g}"
plt.savefig(out_base + ".png", dpi=300)
plt.savefig(out_base + ".pdf")
print(f"Saved: {out_base}.(png|pdf)")
