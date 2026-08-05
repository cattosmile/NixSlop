#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 || $1 != /* || ! -x $1/bin/cc-switch ]]; then
  echo "usage: $0 /absolute/cc-switch-package" >&2
  exit 2
fi

package_path=$1
smoke_root="$(mktemp -d)"
smoke_log="$smoke_root/cc-switch.log"

cleanup() {
  rm -rf -- "$smoke_root"
}
trap cleanup EXIT

mkdir -p \
  "$smoke_root/home" \
  "$smoke_root/state" \
  "$smoke_root/config" \
  "$smoke_root/data" \
  "$smoke_root/runtime"
chmod 0700 "$smoke_root/runtime"

set +e
HOME="$smoke_root/home" \
  XDG_STATE_HOME="$smoke_root/state" \
  XDG_CONFIG_HOME="$smoke_root/config" \
  XDG_DATA_HOME="$smoke_root/data" \
  XDG_RUNTIME_DIR="$smoke_root/runtime" \
  XDG_CURRENT_DESKTOP= \
  WAYLAND_DISPLAY= \
  GDK_BACKEND=x11 \
  WEBKIT_DISABLE_DMABUF_RENDERER=1 \
  timeout --signal=TERM --kill-after=5s 15s \
  xvfb-run -a dbus-run-session -- \
  "$package_path/bin/cc-switch" >"$smoke_log" 2>&1
status=$?
set -e

if [[ $status == 124 ]]; then
  settings_file="$smoke_root/home/.cc-switch/settings.json"
  python3 - "$settings_file" <<'PY'
import json
import sys
from pathlib import Path

settings = json.loads(Path(sys.argv[1]).read_text())
assert settings["language"] == "en"
assert settings["showProfileSwitcher"] is False
assert settings["preferredTerminal"] == "alacritty"
assert settings["useAppWindowControls"] is True
assert settings["visibleApps"] == {
    "claude": False,
    "claude-desktop": False,
    "codex": True,
    "gemini": False,
    "grokbuild": False,
    "opencode": False,
    "openclaw": False,
    "hermes": False,
}
PY
  echo "cc-switch GUI startup smoke: PASS"
  exit 0
fi

echo "cc-switch exited before the GUI startup smoke window elapsed (status $status)" >&2
sed -n '1,200p' "$smoke_log" >&2
exit 1
