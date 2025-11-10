#!/usr/bin/env bash
set -euo pipefail

TCL="${TCL:-test_uwmi_net.tcl}"
OUT="${OUT:-uwmi_results_summary_all.csv}"
LOGDIR="${LOGDIR:-logs_sweep}"
mkdir -p "$LOGDIR"

# Default radio/hw (override via env before calling, or via CLI to ns)
F_KHZ="${F_KHZ:-200}"
B="${B:-5000}"
RB="${RB:-1000}"
TXPWR_DBM="${TXPWR_DBM:-0}"
Q="${Q:-50}"
NT="${NT:-40}"
NR="${NR:-40}"
AT="${AT:-0.12}"
AR="${AR:-0.12}"
RT_="${RT_:-4.0}"
RR_="${RR_:-4.0}"
KAPPA="${KAPPA:-0.7}"

# Traffic/timing
PERIOD="${PERIOD:-1.2}"
STOP="${STOP:-33}"
SEEDS_PER_POINT="${SEEDS_PER_POINT:-5}"

# Helper to run a single sim with arbitrary args
run_ns() {
  local log="$1"; shift
  ns "$TCL" "$@" \
    -f_khz "$F_KHZ" -B "$B" -Rb "$RB" -txpwr_dbm "$TXPWR_DBM" -Q "$Q" \
    -Nt "$NT" -Nr "$NR" -at "$AT" -ar "$AR" -Rt "$RT_" -Rr "$RR_" -kappa "$KAPPA" \
    -period "$PERIOD" -stop "$STOP" \
    | tee "$log" >/dev/null
}

# --- Distance grid sweep for a given (sigma,uw2aw) ---
sweep_distance_grid() {
  local sigma="$1"; local uw2aw="$2"; shift 2
  local dlist=("$@")
  for d in "${dlist[@]}"; do
    for rep in $(seq 1 "$SEEDS_PER_POINT"); do
      local seed=$(( (uw2aw*1000000) + (${sigma/./}*10000) + (d*100) + rep ))
      local tag="d${d}_s${sigma}_u${uw2aw}_f${F_KHZ}_rb${RB}_seed${seed}"
      local log="${LOGDIR}/${tag}.log"
      echo ">>> grid: sigma=${sigma}  uw2aw=${uw2aw}  d=${d}  seed=${seed}"
      run_ns "$log" -distance "$d" -sigma "$sigma" -uw2aw "$uw2aw" -seed "$seed"
    done
  done
}

# --- Range finder via bracket + binary search using the CSV content ---
find_range_pdr_ge() {
  local sigma="$1" uw2aw="$2" target="$3" d0="$4" dmax="$5"
  local fk="$6" rb="$7"
  local step="${8:-1}"

  # Bracket: grow until mean PDR < target or reach dmax
  local low="$d0" high="$d0"
  local mean
  while :; do
    # ensure we have samples at "high"
    for rep in $(seq 1 "$SEEDS_PER_POINT"); do
      local seed=$(( RANDOM % 1000000 ))
      local tag="d${high}_s${sigma}_u${uw2aw}_f${fk}_rb${rb}_seed${seed}"
      run_ns "${LOGDIR}/${tag}.log" -distance "$high" -sigma "$sigma" -uw2aw "$uw2aw" -seed "$seed" -f_khz "$fk" -Rb "$rb"
    done
    # compute mean PDR at "high"
    mean=$(awk -F, -v d="$high" -v s="$sigma" -v u="$uw2aw" -v fk="$fk" -v rb="$rb" '
      NR==1{next}
      ($28==d && $5==s && $9==u && $10==fk && $11==rb){sum+=($3>0?($3/$2):0); cnt+=1}
      END{if(cnt>0) printf "%.6f", sum/cnt; else print "nan"}
    ' "$OUT")

    if [[ "$mean" == "nan" ]]; then mean=0; fi
    if (( $(echo "$mean < $target" | bc -l) )); then
      break
    fi
    low="$high"
    high=$(( high + step ))
    if (( high >= dmax )); then break; fi
  done

  # Binary search between [low, high]
  local L="$low" R="$high"
  for _ in {1..12}; do
    local mid=$(python3 - <<EOF
import math; print(int((($L)+($R))//2))
EOF
)
    if (( mid==L )); then break; fi
    for rep in $(seq 1 "$SEEDS_PER_POINT"); do
      local seed=$(( RANDOM % 1000000 ))
      local tag="d${mid}_s${sigma}_u${uw2aw}_f${fk}_rb${rb}_seed${seed}"
      run_ns "${LOGDIR}/${tag}.log" -distance "$mid" -sigma "$sigma" -uw2aw "$uw2aw" -seed "$seed" -f_khz "$fk" -Rb "$rb"
    done

    mean=$(awk -F, -v d="$mid" -v s="$sigma" -v u="$uw2aw" -v fk="$fk" -v rb="$rb" '
      NR==1{next}
      ($28==d && $5==s && $9==u && $10==fk && $11==rb){sum+=($3>0?($3/$2):0); cnt+=1}
      END{if(cnt>0) printf "%.6f", sum/cnt; else print "nan"}
    ' "$OUT")

    if [[ "$mean" == "nan" ]]; then mean=0; fi
    if (( $(echo "$mean >= $target" | bc -l) )); then
      L="$mid"
    else
      R="$mid"
    fi
  done
  echo "$L"
}

run_core_grids() {
  local SEA=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 16 18 20 22 24 26 28 30)
  local FRESH=(1 2 3 4 5 6 8 10 11 12 13 14 16 18 20 22 24 26 28 30)
  sweep_distance_grid 4.0 0 "${SEA[@]}"
  sweep_distance_grid 4.0 1 "${SEA[@]}"
  sweep_distance_grid 0.05 0 "${FRESH[@]}"
  sweep_distance_grid 0.05 1 "${FRESH[@]}"
}

run_frequency_ranges() {
  local sigma="$1" uw2aw="$2" target="${3:-0.8}"; shift 3
  local FLIST=("$@")
  for fk in "${FLIST[@]}"; do
    local r=$(find_range_pdr_ge "$sigma" "$uw2aw" "$target" 5 120 "$fk" "$RB" 5)
    echo "freq sweep: sigma=$sigma uw2aw=$uw2aw f=$fk kHz  -> range≈${r} m"
  done
}

echo "Loaded sweep_runs_v2.sh. Example usage:
  # Core grids:
  bash sweep_runs_v2.sh core

  # Frequency sweet spot (seawater, UW→UW):
  F_KHZ=200 RB=1000 bash sweep_runs_v2.sh freq 4.0 0 0.8 20 30 50 80 120 200 300 400 500
"

case "${1:-}" in
core) run_core_grids ;;
  freq) shift; run_frequency_ranges "$@" ;;
  *) echo "Commands: core | freq";;
esac
