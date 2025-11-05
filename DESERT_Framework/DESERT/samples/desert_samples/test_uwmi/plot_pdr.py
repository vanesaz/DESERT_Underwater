import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys

CSV = "uwmi_results_summary_all.csv"
SIGMA = float(sys.argv[1]) if len(sys.argv) > 1 else 4.0  

# --- robust load ---
try:
    df = pd.read_csv(CSV)
except Exception:
    df = pd.read_csv(CSV, header=None,
                     names=["distance_m","sent","rcv","per","sigma_Sperm","period_s","stop_s","seed"])

# --- clean ---
need = {"distance_m","sent","rcv","per","sigma_Sperm","period_s","stop_s","seed"}
df = df[[c for c in df.columns if c in need]].copy()
for c in ["distance_m","sent","rcv","per","sigma_Sperm","period_s","stop_s","seed"]:
    df[c] = pd.to_numeric(df[c], errors="coerce")

df = df.dropna(subset=["distance_m","sent","rcv","sigma_Sperm"])
df = df[df["sent"] > 0]
df["pdr"] = np.clip(df["rcv"] / df["sent"], 0, 1)

# --- filter by sigma ---
df = df[np.isclose(df["sigma_Sperm"], SIGMA)]

# --- mean PDR per distance ---
g = (df.groupby("distance_m", as_index=False)["pdr"]
       .mean().sort_values("distance_m"))
if g.empty:
    raise SystemExit(f"No rows for sigma={SIGMA}")

d = g["distance_m"].to_numpy()
p = g["pdr"].to_numpy()

# --- 1/d^6 reference (normalized to first nonzero p) ---
mask_nonzero = p > 0
anchor_idx = np.argmax(mask_nonzero) if mask_nonzero.any() else 0
ref = 1.0 / np.maximum(d, 1e-9)**6
ref *= p[anchor_idx] / ref[anchor_idx]

# --- coverage edge (first pdr <= 0.05 after any > 0) ---
edge_d = None
if (p > 0).any():
    after = np.where(p <= 0.05)[0]
    if after.size > 0:
        edge_d = d[after[0]]

caption = (f"Tx≈0 dBm, B=5 kHz, Rb=1 kbps, f0=200 kHz, σ={SIGMA} S/m, "
           f"NF=8 dB, pkt=128 B")

plt.figure(figsize=(7.2,4.6))
plt.plot(d, p, marker="o", linewidth=2, label="PDR (mean)")
plt.plot(d, np.clip(ref, 0, 1), linestyle="--", linewidth=2, label="∝ 1/d⁶ (scaled)")

if edge_d is not None:
    plt.axvline(edge_d, linestyle=":", linewidth=1.5)
    plt.text(edge_d, 0.55, f"edge ≈ {edge_d:.0f} m", rotation=90, va="center", ha="left")

plt.ylim(-0.05, 1.05); plt.xlim(left=0.8)
plt.xlabel("Distance (m)"); plt.ylabel("Packet Delivery Ratio (PDR)")
plt.title("UwMI PDR vs Distance")
plt.suptitle(caption, fontsize=9, y=0.95)
plt.grid(True, linestyle="--", alpha=0.5); plt.legend()
plt.tight_layout()
out_base = f"plot_pdr_vs_distance_sigma{SIGMA:g}"
plt.savefig(out_base + ".png", dpi=300)
plt.savefig(out_base + ".pdf")
print(f"Saved: {out_base}.(png|pdf)")
