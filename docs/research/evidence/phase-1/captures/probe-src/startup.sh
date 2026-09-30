#!/bin/bash
# Usage: startup.sh <class: first|cold|warm> <n>
# Launch-to-first-frame for the exported Linux client stored on the NVMe (not tmpfs).
#   first: app user dir and shader caches wiped, binary evicted from the page cache
#   cold:  caches kept, binary evicted from the page cache
#   warm:  nothing evicted
# Eviction is per-file posix_fadvise(DONTNEED); system libraries stay cached (no root).
. /tmp/opencode/tortuga-phase-1-probe/env.sh
cd $P && mkdir -p runs
BIN=/var/tmp/tortuga-probe-build/tortuga-probe.x86_64
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
export WAYLAND_DISPLAY=wayland-probe
for i in $(seq 1 $2); do
  if [ "$1" = first ]; then rm -rf $XDG_DATA_HOME/godot/app_userdata $XDG_CACHE_HOME/*; fi
  if [ "$1" != warm ]; then
    python3 -c "import os,sys; fd=os.open(sys.argv[1],os.O_RDONLY); os.fsync(fd); os.posix_fadvise(fd,0,0,os.POSIX_FADV_DONTNEED)" $BIN
  fi
  launch=$(date +%s.%N)
  out=$($BIN --display-driver wayland --rendering-driver opengl3 --fullscreen -- --mode=offline --scene=normal --bot=0.3 --quit_at=2.5 2>&1)
  first=$(echo "$out" | grep -o 'T_FIRST_FRAME unix=[0-9.]*' | cut -d= -f2)
  echo "STARTUP class=$1 i=$i ms=$(echo "($first - $launch) * 1000" | bc -l | cut -d. -f1)" | tee -a runs/startup.log
done
