#!/bin/bash
# Dedicated-server probe: no display variables, exported server binary, headless clients
# on the same host. Timeline in seconds since server launch is echoed to runs/net-timeline.log;
# the server's own `wall=` is engine ticks, so the two clocks differ by the server's startup time.
. /tmp/opencode/tortuga-phase-1-probe/env.sh
cd $P && mkdir -p runs
unset DISPLAY WAYLAND_DISPLAY
SRV=./build/server/tortuga-probe-server.x86_64
CLI=./build/linux/tortuga-probe.x86_64
t0=$(date +%s.%N)
mark() { echo "$(echo "$(date +%s.%N) - $t0" | bc -l | cut -c1-6) $*" | tee -a runs/net-timeline.log; }
client() { $CLI --headless -- --mode=client --bot=$2 $3 > runs/net-client-$1.log 2>&1 & eval "pid_$1=$!"; mark "start client $1 bot=$2 pid=$!"; }
: > runs/net-timeline.log
$SRV --headless -- --mode=server --quit_at=95 > runs/net-server.log 2>&1 &
srv=$!
mark "server started pid=$srv DISPLAY=${DISPLAY:-unset} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
: > runs/net-server.res
( while kill -0 $srv 2>/dev/null; do
    echo "$(echo "$(date +%s.%N) - $t0" | bc -l | cut -c1-6) $(awk '{print $14+$15}' /proc/$srv/stat) $(awk '/VmRSS/{print $2}' /proc/$srv/status)" >> runs/net-server.res
    sleep 1
  done ) &
sleep 5;  client A -1; client B 1
sleep 10; client C 0 --quit_at=10;  client D 0.5 --quit_at=10; mark "C and D will quit themselves 10 s after launch"
sleep 15; kill $pid_A $pid_B; mark "SIGTERM A B"
sleep 20; client E 1
sleep 10; kill -9 $pid_E; mark "SIGKILL E (connection loss)"
sleep 20; client F -1 --quit_at=5
sleep 10; mark "server quits itself at 95 s of its own clock"
wait $srv 2>/dev/null
grep -E "SRV (listen|join|leave)" runs/net-server.log
