#!/usr/bin/env bash
set -euo pipefail

TCL="test_uwmi_net.tcl"
OUT="uwmi_results_summary_all.csv"

# start fresh (write header once)
echo "distance_m,sent,rcv,per,sigma_Sperm,period_s,stop_s,seed" > "$OUT"

# relaxed timing so last packets drain
PERIOD=1.2
STOP=33

run_block () {
  local SIGMA="$1"; shift
  local DLIST=("$@")
  for d in "${DLIST[@]}"; do
    for rep in {1..5}; do
      seed=$((1000*d + rep))
      echo ">>> sigma=${SIGMA}  d=${d} m  seed=${seed}"
      ns "$TCL" -distance "$d" -sigma "$SIGMA" -period "$PERIOD" -stop "$STOP" -seed "$seed"
    done
  done
}

# seawater
run_block 4.0  1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 48 50 52 54 56 58 60
# freshwater
run_block 0.05 1 2 3 4 5 6 8 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 42 44 46 48 50 52 54 56 58 60

echo "done. data in $OUT"
