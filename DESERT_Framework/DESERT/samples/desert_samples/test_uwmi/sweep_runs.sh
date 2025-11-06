#!/usr/bin/env bash
set -euo pipefail

TCL="test_uwmi_net.tcl"
OUT="uwmi_results_summary_all.csv"
LOGDIR="logs_sweep"
mkdir -p "$LOGDIR"

# Columns: add uw2aw at the end
echo "distance_m,sent,rcv,per,sigma_Sperm,period_s,stop_s,seed,uw2aw" > "$OUT"

# timing so last packets drain
PERIOD=1.2
STOP=33

# -------- helper: run one sim and append one CSV row --------
run_one() {
  local DIST="$1" SIGMA="$2" SEED="$3" UW2AW="$4"
  local tag="d${DIST}_s${SIGMA}_u${UW2AW}_seed${SEED}"
  local log="${LOGDIR}/${tag}.log"

  echo ">>> sigma=${SIGMA}  uw2aw=${UW2AW}  d=${DIST} m  seed=${SEED}"
  # Run and capture full log
  ns "$TCL" -distance "$DIST" -sigma "$SIGMA" -period "$PERIOD" -stop "$STOP" -seed "$SEED" -uw2aw "$UW2AW" | tee "$log" >/dev/null

  # Parse the last summary block printed by Tcl
  # Expected lines:
  #   Sent packets     : N
  #   Received packets : M
  #   Packet Error Rate: X
  local SENT RCV PER
  SENT=$(awk '/^Sent packets/{x=$NF} END{print x+0}' "$log")
  RCV=$(awk '/^Received packets/{x=$NF} END{print x+0}' "$log")
  # PER can be printed with many decimals; capture last numeric on that line
  PER=$(awk '/^Packet Error Rate/{x=$NF} END{print x+0}' "$log")

  # Fallback sanity (in case parsing fails)
  : "${SENT:=0}"; : "${RCV:=0}"; : "${PER:=1}"

  # Append one CSV row
  echo "${DIST},${SENT},${RCV},${PER},${SIGMA},${PERIOD},${STOP},${SEED},${UW2AW}" >> "$OUT"
}

# -------- block runner: list of distances, repeated seeds --------
run_block () {
  local SIGMA="$1"; local UW2AW="$2"; shift 2
  local DLIST=("$@")
  for d in "${DLIST[@]}"; do
    for rep in {1..5}; do
      local seed=$((1000*d + rep))
      run_one "$d" "$SIGMA" "$seed" "$UW2AW"
    done
  done
}

# -------- distance grids --------
SEA=(1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 48 50 52 54 56 58 60)
FRESH=(1 2 3 4 5 6 8 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 48 50 52 54 56 58 60)

# -------- run sets --------
# Seawater (σ = 4.0 S/m)
run_block 4.0 0 "${SEA[@]}"    # UW→UW
run_block 4.0 1 "${SEA[@]}"    # UW→AW

# Freshwater (σ = 0.05 S/m)
run_block 0.05 0 "${FRESH[@]}" # UW→UW
run_block 0.05 1 "${FRESH[@]}" # UW→AW

echo "done. data in $OUT (logs in $LOGDIR)"
