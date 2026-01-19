#!/usr/bin/env bash
set -euo pipefail

TCL="${TCL:-test_uwmi_net.tcl}"
OUT="${OUT:-uwmi_results_summary_all.csv}"
# only remove OUT when the script is run as a program, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  rm -f "$OUT"
fi
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

# Matches TCL defaults unless you override
APP_START="${APP_START:-6.0}"
PERIOD="${PERIOD:-1.2}"
PKTS_PER_RUN="${PKTS_PER_RUN:-20}"
FINISH_MARGIN="${FINISH_MARGIN:-8.0}"

APP_STOP="$(python3 - <<PY
import os, math
start  = float(os.environ.get("APP_START","6.0"))
period = float(os.environ.get("PERIOD","1.2"))
pkts   = int(os.environ.get("PKTS_PER_RUN","20"))
# stop right after the Nth packet is *sent*
stop = start + period*(pkts-1) + 1e-6
print(f"{stop:.6f}")
PY
)"

SIM_STOP="$(python3 - <<PY
import os
app_stop = float(os.environ.get("APP_STOP","$APP_STOP"))
margin   = float(os.environ.get("FINISH_MARGIN","8.0"))
print(f"{app_stop + margin:.6f}")
PY
)"

run_ns() {
  local log="$1"; shift
  ns "$TCL" \
    -f_khz "$F_KHZ" -B "$B" -Rb "$RB" -txpwr_dbm "$TXPWR_DBM" -Q "$Q" \
    -Nt "$NT" -Nr "$NR" -at "$AT" -ar "$AR" -Rt "$RT_" -Rr "$RR_" -kappa "$KAPPA" \
    -period "$PERIOD" \
    -app_start "$APP_START" -app_stop "$APP_STOP" -sim_stop "$SIM_STOP" \
    -maxpkts "$PKTS_PER_RUN" \
    "$@" \
    | tee "$log" >/dev/null
}



# --- Distance grid sweep for a given (sigma,uw2aw) ---
sweep_distance_grid() {
  local sigma="$1"; local uw2aw="$2"; shift 2
  local dlist=("$@")
  for d in "${dlist[@]}"; do
    for rep in $(seq 1 "$SEEDS_PER_POINT"); do
      local sigma_int=$(echo "$sigma" | tr -d '.')
      local seed=$(printf "%.0f" "$(echo "$uw2aw*1000000 + $sigma_int*10000 + $d*100 + $rep" | bc -l)")
      local tag="d${d}_s${sigma}_u${uw2aw}_f${F_KHZ}_rb${RB}_seed${seed}"
      local log="${LOGDIR}/${tag}.log"
      echo ">>> grid: sigma=${sigma}  uw2aw=${uw2aw}  d=${d}  seed=${seed}"
      run_ns "$log" -distance "$d" -sigma "$sigma" -uw2aw "$uw2aw" -seed "$seed"
    done
  done
}

# --- UW→AW depth family (vary z2) ---
sweep_uwa_depth_family() {
  local sigma="$1"; shift
  local zlist=("$@")
  # distances: freshwater-like grid (tweak if needed)
  local DLIST=($(seq 0.1 0.4 10))
  for z2 in "${zlist[@]}"; do
    for d in "${DLIST[@]}"; do
      for rep in $(seq 1 "${SEEDS_PER_POINT:-5}"); do
        local seed=$(( RANDOM % 1000000 ))
        local tag="d${d}_s${sigma}_u1_f${F_KHZ}_rb${RB}_z2${z2}_seed${seed}"
        run_ns "${LOGDIR}/${tag}.log" -distance "$d" -sigma "$sigma" -uw2aw 1 -z2 "$z2" -seed "$seed"
      done
    done
  done
}

# --- Array sweep (fixed spacing), uw2aw selectable ---
sweep_arrays() {
  local sigma="$1" uw2aw="$2" spacing="${3:-0.04}" autoR="${4:-0}"
  local sizes=( "1" "2" "3" )    # means 1x1, 2x2, 3x3
  local DLIST_FRESH=($(seq 2 1 20))
  local DLIST_SEA=($(seq 1 0.2 8))
  local DLIST=("${DLIST_FRESH[@]}")
  [[ "$sigma" == "4.0" ]] && DLIST=("${DLIST_SEA[@]}")

  for n in "${sizes[@]}"; do
    for d in "${DLIST[@]}"; do
      for rep in $(seq 1 "${SEEDS_PER_POINT:-5}"); do
        local seed=$(( RANDOM % 1000000 ))
        local tag="arr${n}x${n}_d${d}_s${sigma}_u${uw2aw}_f${F_KHZ}_rb${RB}_autoR${autoR}_seed${seed}"
        run_ns "${LOGDIR}/${tag}.log" -distance "$d" -sigma "$sigma" -uw2aw "$uw2aw" -seed "$seed" \
               -Nt_coils "$n" -Nr_coils "$n" -st "$spacing" -sr "$spacing" -auto_scale_R "$autoR"
      done
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
  local SEA=(
  $(seq 1.0 0.2 12.0)
  )
  local FRESH=(
  $(seq 1.0 0.7 30.0)
  )
  #local SEA=(1 2 2.5 3 3.5 4 4.5 5 5.5 6 6.5 7 8 9 10 11 12)
  #local FRESH=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30)
  sweep_distance_grid 4.0 0 "${SEA[@]}"
  sweep_distance_grid 4.0 1 "${SEA[@]}"
  sweep_distance_grid 0.05 0 "${FRESH[@]}"
  sweep_distance_grid 0.05 1 "${FRESH[@]}"
}

run_frequency_ranges() {
  local sigma="$1" uw2aw="$2" target="${3:-0.8}"; shift 3
  local FLIST=("$@")

  # start closer (1 m) and use fine steps so we see short ranges too
  local d0=1
  local dmax=40
  local step=1

  # for very lossy seawater, we don't need to go super far
  if [[ "$sigma" == "4.0" ]]; then
    dmax=15
  fi

  for fk in "${FLIST[@]}"; do
    local r
    r=$(find_range_pdr_ge "$sigma" "$uw2aw" "$target" "$d0" "$dmax" "$fk" "$RB" "$step")
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

# --- Ablation helpers ---
sweep_Q() {
  local sigma="$1" uw2aw="$2"; shift 2
  local QList=(20 30 40 50 70 100 150)
  local DLIST=($(seq 2 1 20))
  for Qv in "${QList[@]}"; do
    for d in "${DLIST[@]}"; do
      for rep in $(seq 1 "${SEEDS_PER_POINT:-5}"); do
        local seed=$(( RANDOM % 1000000 ))
        run_ns "${LOGDIR}/Q${Qv}_d${d}_s${sigma}_u${uw2aw}_seed${seed}.log" \
               -distance "$d" -sigma "$sigma" -uw2aw "$uw2aw" -Q "$Qv" -seed "$seed"
      done
    done
  done
}

sweep_NF() {
  local sigma="$1" uw2aw="$2"; shift 2
  local NFLIST=(10 14 18 22 26)
  local DLIST=($(seq 2 1 16))
  for NF in "${NFLIST[@]}"; do
    for d in "${DLIST[@]}"; do
      for rep in $(seq 1 "${SEEDS_PER_POINT:-5}"); do
        local seed=$(( RANDOM % 1000000 ))
        run_ns "${LOGDIR}/NF${NF}_d${d}_s${sigma}_u${uw2aw}_seed${seed}.log" \
               -distance "$d" -sigma "$sigma" -uw2aw "$uw2aw" -NF_dB "$NF" -seed "$seed"
      done
    done
  done
}

sweep_B_Rb_grid() {
  local sigma="$1" uw2aw="$2"; shift 2
  local BLIST=(2000 5000 8000)
  local RBLIST=(500 1000 2000)
  local DLIST=($(seq 2 1 16))
  for b in "${BLIST[@]}"; do
    for rb in "${RBLIST[@]}"; do
      for d in "${DLIST[@]}"; do
        for rep in $(seq 1 "${SEEDS_PER_POINT:-5}"); do
          local seed=$(( RANDOM % 1000000 ))
          run_ns "${LOGDIR}/B${b}_Rb${rb}_d${d}_s${sigma}_u${uw2aw}_seed${seed}.log" \
                 -distance "$d" -sigma "$sigma" -uw2aw "$uw2aw" -B "$b" -Rb "$rb" -seed "$seed"
        done
      done
    done
  done
}

