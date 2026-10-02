#!/usr/bin/env python3
"""Verify the pinned Tortuga native/release toolchain lock and fetch it into a disposable root.

  bootstrap_toolchain.py verify --lock FILE
  bootstrap_toolchain.py fetch --platform KEY --lock FILE --output ROOT [--cache DIR]

Only artifacts named in the lock are downloaded; every byte is digest-checked before any
extraction, cached files are re-verified on every run, and archive members may never land
outside ROOT. Success writes ROOT/toolchain.json (schema in docs/phase-2/release-contracts.md).
Stdlib only; subprocesses always use argv lists (no shell).
"""

import argparse
import hashlib
import io
import json
import os
import platform as host_platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

SCHEMA_VERSION = 1
DIGEST_LENGTHS = {"sha256": 64, "sha512": 128}
FORMATS = ("zip", "tar", "rpm")
DUMPED = ("extension_api", "gdextension_interface", "gdextension_interface_json")
NAME_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9._+-]*$")


class ToolchainError(Exception):
    pass


# ---------------------------------------------------------------- lock


def _need(cond, msg):
    if not cond:
        raise ToolchainError(msg)


def _safe_parts(rel, what):
    """Split a relative POSIX-ish path; reject absolute, drive and '..' components."""
    _need(isinstance(rel, str), f"{what}: path must be a string")
    norm = rel.replace("\\", "/")
    _need(not norm.startswith("/") and not re.match(r"^[A-Za-z]:", norm), f"{what}: absolute path {rel!r}")
    parts = [p for p in norm.split("/") if p not in ("", ".")]
    _need(".." not in parts, f"{what}: '..' in {rel!r}")
    return parts


def _check_digest(digest, algorithm, what):
    _need(algorithm in DIGEST_LENGTHS, f"{what}: unsupported algorithm {algorithm!r}")
    _need(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{%d}" % DIGEST_LENGTHS[algorithm], digest or ""),
          f"{what}: missing or malformed {algorithm} digest")


def validate_lock(lock, allow_file=False):
    """Raise ToolchainError for any malformed lock. allow_file permits file:// URLs (test fixtures only)."""
    try:
        return _validate_lock(lock, allow_file)
    except (TypeError, AttributeError, KeyError, IndexError) as exc:
        raise ToolchainError(f"lock: malformed structure ({type(exc).__name__}: {exc})") from None


def _validate_lock(lock, allow_file):
    _need(isinstance(lock, dict) and lock.get("schema_version") == SCHEMA_VERSION, "lock: schema_version must be 1")
    pins = lock.get("pins")
    _need(isinstance(pins, dict) and all(isinstance(pins.get(k), str) and pins[k] for k in ("engine", "velopack")),
          "lock: pins.engine and pins.velopack are required")
    arts = lock.get("artifacts")
    _need(isinstance(arts, dict) and arts, "lock: artifacts must be a non-empty object")
    for aid, art in arts.items():
        what = f"artifact {aid}"
        _need(NAME_RE.match(aid) is not None, f"{what}: invalid id")
        _need(isinstance(art, dict), f"{what}: must be an object")
        for key in ("url", "file", "format", "algorithm", "digest", "version", "license", "provenance"):
            _need(isinstance(art.get(key), str) and art[key], f"{what}: missing {key}")
        _need(art["url"].startswith("https://") or (allow_file and art["url"].startswith("file://")),
              f"{what}: url must be https://")
        _need(art["format"] in FORMATS, f"{what}: format must be one of {FORMATS}")
        _need(_safe_parts(art["file"], what), f"{what}: empty file")
        _check_digest(art["digest"], art["algorithm"], what)
        _need(isinstance(art.get("size"), int) and art["size"] > 0, f"{what}: size must be a positive integer")
        if "pin" in art:
            _need(art["version"] == pins[art["pin"]], f"{what}: version {art['version']} != pins.{art['pin']}")
    plats = lock.get("platforms")
    _need(isinstance(plats, dict) and plats, "lock: platforms must be a non-empty object")
    for key, plat in plats.items():
        what = f"platform {key}"
        host = plat.get("host", {})
        _need(isinstance(host.get("system"), str) and isinstance(host.get("machine"), list) and host["machine"],
              f"{what}: host.system and host.machine[] required")
        tools = plat.get("tools")
        _need(isinstance(tools, dict) and tools, f"{what}: tools required")
        for name, ref in tools.items():
            _need(NAME_RE.match(name) and name not in DUMPED, f"{what}: invalid tool name {name!r}")
            _need(isinstance(ref, list) and len(ref) == 2 and ref[0] in arts, f"{what}: tool {name} must be [artifact, path]")
            _safe_parts(ref[1], f"{what} tool {name}")
        known = set(tools) | (set(DUMPED) if plat.get("dump_extension_api") else set())
        _need(not plat.get("dump_extension_api") or "engine" in tools, f"{what}: dump_extension_api needs engine")
        for var, tool in plat.get("cmake", {}).items():
            _need(re.fullmatch(r"[A-Z][A-Z0-9_]*", var) and tool in known, f"{what}: cmake {var} -> unknown tool {tool!r}")
        for name, probe in plat.get("probes", {}).items():
            argv = probe.get("argv") if isinstance(probe, dict) else None
            _need(isinstance(argv, list) and argv and all(isinstance(a, str) for a in argv), f"{what}: probe {name} argv")
            for a in argv:
                _need(not a.startswith("$") or a[1:] in tools, f"{what}: probe {name} references unknown tool {a}")
    return lock


def load_lock(path: Path, allow_file: bool = False) -> dict:
    try:
        lock = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ToolchainError(f"cannot read lock {path}: {exc}") from exc
    return validate_lock(lock, allow_file)


# ---------------------------------------------------------------- digests


def verify_artifact(path: Path, digest: str, algorithm: str) -> None:
    _check_digest(digest, algorithm, str(path))
    h = hashlib.new(algorithm)
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    if h.hexdigest() != digest:
        raise ToolchainError(f"digest mismatch for {path}: expected {algorithm}:{digest}, got {h.hexdigest()}")


def _obtain(aid, art, cache):
    """Return a verified cached file. Cached bytes are re-verified; a mismatch fails (no silent re-download)."""
    # ponytail: hash-then-reopen TOCTOU — the archive is reopened for extraction after hashing, so a local
    # actor with write access to the cache could swap bytes in between. Out of scope (same-user cache);
    # extract from the already-open verified handle if the cache ever becomes shared.
    dest = cache.joinpath(*_safe_parts(art["file"], aid))
    if dest.exists():
        try:
            _need(dest.stat().st_size == art["size"], f"size mismatch for {dest}: expected {art['size']}, got {dest.stat().st_size}")
            verify_artifact(dest, art["digest"], art["algorithm"])
        except ToolchainError as exc:
            raise ToolchainError(f"{exc}\ncached artifact {aid} is corrupt; inspect/delete it deliberately, then rerun") from None
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    partial = dest.with_name(dest.name + ".partial")
    print(f"downloading {aid}: {art['url']}", file=sys.stderr)
    try:
        with urllib.request.urlopen(art["url"], timeout=60) as resp, open(partial, "wb") as out:
            shutil.copyfileobj(resp, out, 1 << 20)
        _need(partial.stat().st_size == art["size"], f"size mismatch for {aid}: expected {art['size']}, got {partial.stat().st_size}")
        verify_artifact(partial, art["digest"], art["algorithm"])
    except BaseException:
        partial.unlink(missing_ok=True)
        raise
    os.replace(partial, dest)
    return dest


# ---------------------------------------------------------------- extraction


def _unsafe(name, why):
    return ToolchainError(f"unsafe archive member {name!r}: {why}")


def _member_parts(name):
    try:
        return _safe_parts(name, "member")
    except ToolchainError as exc:
        raise _unsafe(name, str(exc)) from None


def _extract_zip(path, dest):
    # No locked zip/tpz/nupkg (incl. the macOS .app zip) contains a link, so zip links are refused
    # outright; with no links inside dest, no write can be redirected outside it.
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            parts = _member_parts(info.filename)
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode):
                raise _unsafe(info.filename, "symlinks are not allowed in zip artifacts")
            if not parts:
                continue
            target = Path(dest, *parts)
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out, 1 << 20)
            os.chmod(target, (mode & 0o755) or 0o644)


def _extract_tar(tf, dest):
    """Strict name pre-check, then the stdlib 'data' filter (link targets confined to dest)."""
    for m in tf.getmembers():
        _member_parts(m.name)
        if not (m.isfile() or m.isdir() or m.issym() or m.islnk()):
            raise _unsafe(m.name, "device/fifo members are not allowed")
        if m.islnk():
            _member_parts(m.linkname)  # hardlink targets are archive-root relative: never absolute/'..'
    tf.errorlevel = 2  # every extraction error is fatal
    try:
        tf.extractall(dest, filter="data")
    except tarfile.FilterError as exc:
        raise _unsafe(getattr(getattr(exc, "tarinfo", None), "name", "?"), str(exc)) from None
    except KeyError as exc:  # data filter: hardlink target not an in-archive member (e.g. via an escaping link)
        raise _unsafe("?", f"hardlink target unresolved: {exc}") from None


def _cpio_newc(data):
    """Parse cpio newc bytes (what rpm2cpio emits) into an in-memory tar so links go through _extract_tar."""
    # ponytail: hardlinked regular files are refused, not reassembled (none in the locked rpm).
    buf, pos = io.BytesIO(), 0
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as out:
        while True:
            hdr = data[pos:pos + 110]
            if hdr[:6] not in (b"070701", b"070702"):
                raise ToolchainError("rpm payload is not cpio newc")
            f = [int(hdr[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
            mode, nlink, size, namesize = f[1], f[4], f[6], f[11]
            name_start = pos + 110
            name = data[name_start:name_start + namesize - 1].decode("utf-8")
            body = (name_start + namesize + 3) & ~3
            content = data[body:body + size]
            pos = (body + size + 3) & ~3
            if name == "TRAILER!!!":
                break
            info = tarfile.TarInfo(name)
            info.mode = stat.S_IMODE(mode)
            if stat.S_ISLNK(mode):
                info.type, info.linkname = tarfile.SYMTYPE, content.decode("utf-8")
                out.addfile(info)
            elif stat.S_ISDIR(mode):
                info.type = tarfile.DIRTYPE
                out.addfile(info)
            elif stat.S_ISREG(mode) and nlink <= 1:
                info.size = len(content)
                out.addfile(info, io.BytesIO(content))
            else:
                raise _unsafe(name, "device/fifo/hardlinked cpio members are not allowed")
    buf.seek(0)
    return tarfile.open(fileobj=buf)


def _within(root, path):
    return os.path.commonpath([root, path]) == root


def _extract_into(path, fmt, dest):
    if fmt == "zip":
        _extract_zip(path, dest)
    elif fmt == "tar":
        with tarfile.open(path) as tf:
            _extract_tar(tf, dest)
    else:  # rpm: payload via rpm2cpio (argv list, no shell)
        data = subprocess.run(["rpm2cpio", str(path)], check=True, capture_output=True, timeout=300).stdout
        with _cpio_newc(data) as tf:
            _extract_tar(tf, dest)


def _extract(aid, archive, fmt, root):
    tmp = Path(tempfile.mkdtemp(prefix=f".tmp-{aid}-", dir=root))
    try:
        _extract_into(archive, fmt, tmp)
        final = root / aid
        if final.is_symlink() or final.is_file():
            final.unlink()
        elif final.exists():
            shutil.rmtree(final)
        os.rename(tmp, final)
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    return final


# ---------------------------------------------------------------- fetch


def host_matches(host):
    return host_platform.system() == host["system"] and host_platform.machine().lower() in host["machine"]


def _run(argv, cwd, env, timeout=600):
    p = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True, errors="replace", timeout=timeout)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def _sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _first_line(text):
    return next((line.strip() for line in text.splitlines() if line.strip()), "")


def fetch_toolchain(platform: str, lock: dict, output: Path, cache: Path = None, allow_file: bool = False) -> dict:
    validate_lock(lock, allow_file)
    plat = lock["platforms"].get(platform)
    _need(plat is not None, f"unknown platform {platform!r}; lock has {sorted(lock['platforms'])}")
    if not host_matches(plat["host"]):
        raise ToolchainError(
            f"host mismatch: {platform} requires {plat['host']['system']}/{plat['host']['machine']}, "
            f"this host is {host_platform.system()}/{host_platform.machine()}; run fetch on a native {platform} host")
    root = Path(output).resolve()
    cache = Path(cache).resolve() if cache else root / "downloads"
    root.mkdir(parents=True, exist_ok=True)
    receipt_path = root / "toolchain.json"
    receipt_path.unlink(missing_ok=True)  # a failed run never leaves a stale receipt behind

    needed = sorted({ref[0] for ref in plat["tools"].values()})
    archives = {aid: _obtain(aid, lock["artifacts"][aid], cache) for aid in needed}  # all verified first
    for aid in needed:
        _extract(aid, archives[aid], lock["artifacts"][aid]["format"], root)

    tools = {}
    for name, (aid, rel) in plat["tools"].items():
        p = root.joinpath(aid, *_safe_parts(rel, name))
        _need(os.path.lexists(p) and _within(str(root), os.path.realpath(p)), f"tool {name}: {p} missing after extraction")
        tools[name] = str(p)

    engine_pin = lock["pins"]["engine"]
    verified = {}
    if "templates" in tools:
        got = Path(tools["templates"], "version.txt").read_text(encoding="utf-8").strip()
        _need(got == engine_pin, f"templates version.txt {got!r} != engine pin {engine_pin!r}")
        verified["templates_version"] = got

    env = dict(os.environ, DOTNET_CLI_TELEMETRY_OPTOUT="1", DOTNET_NOLOGO="1",
               XDG_DATA_HOME=str(root / "xdg" / "data"), XDG_CONFIG_HOME=str(root / "xdg" / "config"),
               XDG_CACHE_HOME=str(root / "xdg" / "cache"))
    extension_api = None
    if "engine" in tools:
        code, out = _run([tools["engine"], "--version"], root, env)
        ver = [line.strip() for line in out.splitlines() if line.strip()][-1:] or [""]
        _need(code == 0 and ver[0].startswith(engine_pin + "."), f"engine --version gave {ver[0]!r} (exit {code})")
        verified["engine_version"] = ver[0]
    if plat.get("dump_extension_api"):
        api_dir = root / "extension_api"
        shutil.rmtree(api_dir, ignore_errors=True)
        api_dir.mkdir()
        code, out = _run([tools["engine"], "--headless", "--dump-extension-api", "--dump-gdextension-interface",
                          "--dump-gdextension-interface-json"], api_dir, env)
        api, iface, iface_json = (api_dir / n for n in ("extension_api.json", "gdextension_interface.h", "gdextension_interface.json"))
        _need(code == 0 and api.is_file() and iface.is_file() and iface_json.is_file(),
              f"extension API dump failed (exit {code}): {out[-500:]}")
        header = json.loads(api.read_text(encoding="utf-8"))["header"]
        dumped = "{version_major}.{version_minor}.{version_patch}.{version_status}".format(**header)
        _need(dumped == engine_pin, f"dumped extension API header {dumped} != engine pin {engine_pin}")
        tools.update(extension_api=str(api), gdextension_interface=str(iface), gdextension_interface_json=str(iface_json))
        extension_api = {"header": header, "extension_api_sha256": _sha256(api), "gdextension_interface_sha256": _sha256(iface),
                         "gdextension_interface_json_sha256": _sha256(iface_json)}

    probes = {}
    for name, probe in plat.get("probes", {}).items():
        locked = probe["argv"][0].startswith("$")
        argv = [tools[a[1:]] if a.startswith("$") else a for a in probe["argv"]]
        exe = argv[0] if locked else shutil.which(argv[0])
        if exe is None:
            probes[name] = {"argv": argv, "path": None, "exit": None, "identity": "not found on PATH"}
            continue
        code, out = _run([exe] + argv[1:], root, env)
        expect = probe.get("expect")
        ident = next((line.strip() for line in out.splitlines() if expect and expect in line), _first_line(out))
        if locked or expect:
            _need(code == 0 and (not expect or expect in out), f"probe {name}: expected {expect!r}, exit {code}: {_first_line(out)!r}")
        probes[name] = {"argv": argv, "path": exe, "exit": code, "identity": ident}

    arts = {aid: {k: lock["artifacts"][aid][k] for k in ("url", "version", "algorithm", "digest", "size", "license")
                  if k in lock["artifacts"][aid]} | {"cache_path": str(archives[aid]), "extracted": str(root / aid)}
            for aid in needed}
    for aid in needed:
        if "commit" in lock["artifacts"][aid]:
            arts[aid]["commit"] = lock["artifacts"][aid]["commit"]
    receipt = {
        "schema_version": SCHEMA_VERSION,
        "platform": platform,
        "root": str(root),
        "lock_sha256": hashlib.sha256(json.dumps(lock, sort_keys=True).encode()).hexdigest(),
        "host": {"system": host_platform.system(), "machine": host_platform.machine(),
                 "release": host_platform.release(), "python": host_platform.python_version()},
        "pins": lock["pins"],
        "tools": tools,
        "artifacts": arts,
        "verified": verified,
        "extension_api": extension_api,
        "compiler": {"lock": plat.get("compiler"), "observed": {k: probes[k] for k in plat.get("compiler_probes", []) if k in probes}},
        "probes": probes,
        "cmake_args": [f"-D{var}={Path(tools[tool]).as_posix()}" for var, tool in plat.get("cmake", {}).items()],
    }
    tmp = receipt_path.with_suffix(".json.partial")
    tmp.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, receipt_path)
    return receipt


# ---------------------------------------------------------------- CLI


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("verify", help="validate lock shape without fetching")
    v.add_argument("--lock", required=True, type=Path)
    f = sub.add_parser("fetch", help="verify/download locked inputs and write ROOT/toolchain.json")
    f.add_argument("--platform", required=True, choices=["windows-x86_64", "macos-universal", "linux-x86_64"])
    f.add_argument("--lock", required=True, type=Path)
    f.add_argument("--output", required=True, type=Path)
    f.add_argument("--cache", type=Path, help="download cache (default ROOT/downloads); cached bytes are re-verified")
    args = ap.parse_args(argv)
    try:
        lock = load_lock(args.lock)
        if args.cmd == "verify":
            print(f"lock OK: {len(lock['artifacts'])} artifacts, platforms {sorted(lock['platforms'])}")
        else:
            receipt = fetch_toolchain(args.platform, lock, args.output, cache=args.cache)
            print(Path(receipt["root"]) / "toolchain.json")
    except (ToolchainError, OSError, subprocess.SubprocessError, ValueError, KeyError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
