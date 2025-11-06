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

# --- normalize columns ---
need = {"distance_m","sent","rcv","per","sigma_Sperm","period_s","stop_s","seed","uw2aw"}
for c in need:
    if c not in df.columns:
        if c == "uw2aw":
            df["uw2aw"] = 0  # default: all-UW if column missing
        else:
            df[c] = np.nan
df = df[[c for c in df.columns if c in need]].copy()

for c in ["distance_m","sent","rcv","per","sigma_Sperm","period_s","stop_s","seed","uw2aw"]:
    df[c] = pd.to_numeric(df[c], errors="coerce")

df = df.dropna(subset=["distance_m","sent","rcv","sigma_Sperm"])
df = df[df["sent"] > 0]
df["pdr"] = np.clip(df["rcv"] / df["sent"], 0, 1)

# --- filter by sigma ---
df = df[np.isclose(df["sigma_Sperm"], SIGMA)]
if df.empty:
    raise SystemExit(f"No rows for sigma={SIGMA}")

def prep_curve(sub):
    g = (sub.groupby("distance_m", as_index=False)["pdr"]
           .mean().sort_values("distance_m"))
    d = g["distance_m"].to_numpy()
    p = g["pdr"].to_numpy()
    # 1/d^6 reference, anchored to first nonzero p
    mask_nonzero = p > 0
    if mask_nonzero.any():
        anchor_idx = np.argmax(mask_nonzero)
        ref = 1.0 / np.maximum(d, 1e-9)**6
        ref *= p[anchor_idx] / ref[anchor_idx]
    else:
        ref = np.zeros_like(d)
    # coverage edge (first p<=0.05 after any >0)
    edge_d = None
    if (p > 0).any():
        after = np.where(p <= 0.05)[0]
        if after.size > 0:
            edge_d = d[after[0]]
    return d, p, np.clip(ref, 0, 1), edge_d

# --- choose subsets ---
plot_sets = []
if MODE in ("both", "uw"):
    sub = df[df["uw2aw"] == 0]
    if not sub.empty:
        plot_sets.append(("UW→UW", *prep_curve(sub)))
if MODE in ("both", "uw2aw"):
    sub = df[df["uw2aw"] == 1]
    if not sub.empty:
        plot_sets.append(("UW→AW", *prep_curve(sub)))

if not plot_sets:
    raise SystemExit(f"No rows for sigma={SIGMA} in mode='{MODE}'")

caption = (f"Tx≈0 dBm, B=5 kHz, Rb=1 kbps, f0=200 kHz, σ={SIGMA} S/m, "
           f"NF=8 dB, pkt=128 B")

plt.figure(figsize=(7.2,4.6))
for label, d, p, ref, edge_d in plot_sets:
    plt.plot(d, p, marker="o", linewidth=2, label=f"{label} — PDR (mean)")
    plt.plot(d, ref, linestyle="--", linewidth=2, label=f"{label} — ∝1/d⁶ (scaled)")
    if edge_d is not None:
        plt.axvline(edge_d, linestyle=":", linewidth=1.5)
        plt.text(edge_d, 0.55, f"{label} edge ≈ {edge_d:.0f} m",
                 rotation=90, va="center", ha="left")

plt.ylim(-0.05, 1.05); plt.xlim(left=0.8)
plt.xlabel("Distance (m)"); plt.ylabel("Packet Delivery Ratio (PDR)")
title_mode = {"both":"UW→UW vs UW→AW", "uw":"UW→UW only", "uw2aw":"UW→AW only"}[MODE]
plt.title(f"UwMI PDR vs Distance ({title_mode})")
plt.suptitle(caption, fontsize=9, y=0.95)
plt.grid(True, linestyle="--", alpha=0.5); plt.legend()
plt.tight_layout()
out_base = f"plot_pdr_vs_distance_sigma{SIGMA:g}_{MODE}"
plt.savefig(out_base + ".png", dpi=300)
plt.savefig(out_base + ".pdf")
print(f"Saved: {out_base}.(png|pdf)")
