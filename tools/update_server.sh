#!/usr/bin/env bash
# Install or update the Tortuga server and restart it. On the server, as root:
#   /usr/local/sbin/tortuga-update-server        # latest release
#   /usr/local/sbin/tortuga-update-server 0.N    # that release (rollback = an older 0.N)
# A failed download or checksum changes nothing. Runbook: docs/phase-3/server-ops.md
set -euo pipefail

NAME=tortuga-server-linux-arm64.tar.gz
R=https://github.com/dnldxn/tortuga/releases
URL="$R/latest/download/$NAME"
if [ -n "${1:-}" ]; then URL="$R/download/v$1/$NAME"; fi

[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo)" >&2; exit 1; }
TMP="$(mktemp -d /opt/tortuga/.update.XXXXXX)"    # same filesystem as /opt/tortuga/server
trap 'rm -rf -- "$TMP"' EXIT
cd "$TMP"
curl -fsSL --retry 3 -o "$NAME" "$URL"
curl -fsSL --retry 3 -o "$NAME.sha256" "$URL.sha256"
sha256sum -c "$NAME.sha256"                        # a mismatch stops here: nothing installed
tar --no-same-owner -xzf "$NAME"
set -- tortuga-server-0.*/tortuga-server           # the archive's one top dir names the version
test -x "$1" || { echo "unexpected archive layout: nothing installed" >&2; exit 1; }
NEW="${1%/tortuga-server}"
rm -rf /opt/tortuga/server                         # the running server keeps its open files
mv "$NEW" /opt/tortuga/server
if command -v restorecon > /dev/null; then restorecon -R /opt/tortuga/server; fi
systemctl restart tortuga-server                   # graceful: ExecStop touches the stop file
sleep 2
echo "$NEW: $(systemctl is-active tortuga-server)"   # tortuga-server-0.N: active
