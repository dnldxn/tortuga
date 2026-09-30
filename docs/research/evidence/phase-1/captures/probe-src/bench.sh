#!/bin/bash
# Usage: bench.sh <run-id> <scene> [extra game args]
# Runs the exported Linux client on the virtual compositor with Mesa forced,
# logs launch time, renderer, frame stats, and 1 Hz RSS samples to runs/<run-id>.*
. /tmp/opencode/tortuga-phase-1-probe/env.sh
cd $P && mkdir -p runs
id=$1; scene=$2; shift 2
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
export WAYLAND_DISPLAY=wayland-probe
launch=$(date +%s.%N)
./build/linux/tortuga-probe.x86_64 --display-driver wayland --rendering-driver opengl3 --disable-vsync --fullscreen \
  -- --mode=offline --scene=$scene --bot=0.3 --out=$P/runs/$id.csv "$@" > runs/$id.log 2>&1 &
pid=$!
: > runs/$id.rss
while kill -0 $pid 2>/dev/null; do
  awk -v t=$(date +%s.%N) '/VmRSS/{print t, $2}' /proc/$pid/status >> runs/$id.rss 2>/dev/null
  sleep 1
done
first=$(grep -o 'T_FIRST_FRAME unix=[0-9.]*' runs/$id.log | cut -d= -f2)
echo "RUN $id scene=$scene launch_to_first_frame_ms=$(echo "($first - $launch) * 1000" | bc -l | cut -d. -f1)"
grep -E "Using Device|BENCH|T_RELOAD" runs/$id.log
awk '{if($2>m)m=$2; s+=$2; n++} END{printf "RSS_kB samples=%d mean=%d peak=%d\n", n, s/n, m}' runs/$id.rss
