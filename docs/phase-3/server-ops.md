# Tortuga server on OCI (Oracle Linux 9, arm64): runbook

The server is the stock Godot `linux_release.arm64` template plus the release's game pack, run by
systemd as user `tortuga`. Each release publishes it as `tortuga-server-linux-arm64.tar.gz` (+ `.sha256`).
Players' game version must equal the server's (`0.N`), so update both before a session.

| Path | What |
|---|---|
| `/opt/tortuga/server/` | installed release: `tortuga-server`, `tortuga-server.pck`, `override.cfg` |
| `/etc/tortuga/server.env` | port and password (root, 0600) |
| `/etc/systemd/system/tortuga-server.service` | the service (`tools/tortuga-server.service`) |
| `/usr/local/sbin/tortuga-update-server` | install/update script (`tools/update_server.sh`) |
| `/var/lib/tortuga` | home of user `tortuga` (Godot `user://` data) |
| `/run/tortuga-server/stop` | stop file systemd touches for a graceful stop |

Default port UDP 24680. Commands run on the server as `opc` unless marked "on the Mac".
`systemctl stop`/`restart`, updates and reboots are graceful (players see "Server stopped");
`kill`, a crash or a power loss is abrupt ("Connection lost"). Battles are discarded either way.

## 1. Check the box
```bash
cat /etc/oracle-release; uname -m     # Oracle Linux Server release 9.x, aarch64
ldd --version | head -1               # ldd (GNU libc) 2.34 on OL9
getenforce                            # Enforcing (keep it)
systemctl is-active firewalld         # active
```

## 2. Open UDP 24680
OCI console: Compute → Instances → your instance → Networking → primary VNIC → its subnet's
security list (or the VNIC's NSG) → **Add Ingress Rules**: stateless off, source `0.0.0.0/0` (or
one `<friend-ip>/32` each), IP protocol **UDP**, destination port **24680**. Then the host firewall:
```bash
sudo firewall-cmd --permanent --add-port=24680/udp && sudo firewall-cmd --reload
sudo firewall-cmd --list-ports        # includes 24680/udp
```

## 3. Install (once)
On the Mac: `scp tools/update_server.sh tools/tortuga-server.service tools/server.env.example opc@<server-ip>:`
On the server (`install` copies, so SELinux labels are right; don't `mv` from your home):
```bash
sudo useradd --system --home-dir /var/lib/tortuga --create-home --shell /sbin/nologin tortuga
sudo install -d -m 755 /opt/tortuga /etc/tortuga
sudo install -m 600 server.env.example /etc/tortuga/server.env
sudo sed -i "s/^TORTUGA_SERVER_PASSWORD=.*/TORTUGA_SERVER_PASSWORD=$(openssl rand -hex 8)/" /etc/tortuga/server.env
sudo grep PASSWORD /etc/tortuga/server.env      # give this to your friends
sudo install -m 644 tortuga-server.service /etc/systemd/system/
sudo install -m 755 update_server.sh /usr/local/sbin/tortuga-update-server
sudo systemctl daemon-reload && sudo systemctl enable tortuga-server
sudo /usr/local/sbin/tortuga-update-server      # tortuga-server-0.N: active
sudo journalctl -u tortuga-server -n 5          # banner, SRV listening port=24680 version=0.N …
```

## 4. Before a session: update
```bash
sudo /usr/local/sbin/tortuga-update-server        # latest release
sudo /usr/local/sbin/tortuga-update-server 0.M    # a specific release (rollback)
```
The stop is graceful; the script exits 1 if the new release isn't `active` (see §6). Players then
click **Check for updates** so their version matches; after a rollback they need the 0.M download
(the updater only moves forward). If `tools/update_server.sh` itself changed, `install` it again (§3).

## 5. Operate
```bash
sudo systemctl status tortuga-server
sudo systemctl restart tortuga-server     # graceful stop + start (also stop / start)
sudo journalctl -u tortuga-server -f      # follow the log
```
Port or password: edit `/etc/tortuga/server.env`, restart (a new port also needs §2). Don't `kill` it.
Uninstall:
```bash
sudo systemctl disable --now tortuga-server && sudo userdel -r tortuga
sudo rm -rf /opt/tortuga /etc/tortuga /etc/systemd/system/tortuga-server.service /usr/local/sbin/tortuga-update-server
```
then remove the §2 rules.

## 6. Troubleshooting
| Symptom | Check |
|---|---|
| Client times out | `systemctl is-active tortuga-server`; `sudo ss -ulpn \| grep 24680`; `sudo firewall-cmd --list-ports`; the OCI rule is UDP, destination 24680, on the instance's subnet or NSG; the client uses the public IP |
| "Version mismatch" | update the side the message names: server (§4) or client (Check for updates) |
| "Wrong password" | `sudo grep PASSWORD /etc/tortuga/server.env` |
| `status=203/EXEC` or "Permission denied" | SELinux labels: `sudo restorecon -Rv /opt/tortuga && sudo systemctl restart tortuga-server`; `sudo ausearch -m AVC -ts recent` shows remaining denials. Keep SELinux enforcing |
| Restarts in a loop | `sudo journalctl -u tortuga-server -n 50`: status 2 = bad option (password/port missing in `server.env`); status 1 = can't listen (port in use); `GLIBC_2.xx not found` = OS too old, use OL9 |
| `stop`/`restart` takes ~10 s, players see "Connection lost" | `ExecStop` timed out, SIGTERM followed (no `SRV stopping reason=stop-file` in the journal): check the unit has `RuntimeDirectory=tortuga-server` and `--stop-file /run/tortuga-server/stop`, and `ausearch -m AVC` shows no `touch` denial |

## 7. Docker dry run (on the Mac, no OCI)
A native linux/arm64 Oracle Linux 9 container, to try an archive before deploying or to host bots
locally. `DL` is an absolute path holding an extracted archive (`$DL/tortuga-server-0.N/`):
```bash
docker build --platform linux/arm64 -t tortuga-ol9 - <<'EOF'
FROM oraclelinux:9
RUN dnf -y install procps-ng && dnf clean all
EOF
docker run -d --name tortuga-srv --init --platform linux/arm64 --user 1000:1000 -e HOME=/tmp \
  -e TORTUGA_SERVER_PASSWORD=dockertest -p 24680:24680/udp -v "$DL:/srv:ro" tortuga-ol9 \
  /srv/tortuga-server-0.N/tortuga-server --headless -- --server --port 24680 --stop-file /tmp/stop
docker logs tortuga-srv                                      # SRV listening port=24680 version=0.N …
docker exec tortuga-srv ps -o rss=,pcpu= -C tortuga-server   # RSS (KiB), CPU %
docker exec tortuga-srv touch /tmp/stop                      # graceful: "Server stopped", exit 0
docker rm -f tortuga-srv                                     # (docker stop = SIGTERM = abrupt)
```
Clients use `127.0.0.1:24680`, password `dockertest`, and the same `0.N` build (e.g. the matching
`Tortuga-0.N-macos.zip`'s `Tortuga.app/Contents/MacOS/Tortuga --headless -- --bot …`).
