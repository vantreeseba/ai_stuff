#!/usr/bin/env bash
set -euo pipefail

# Installs the LSP binaries and merges opencode/opencode.json's `lsp` block into
# the user's global OpenCode config (~/.config/opencode/opencode.json).
#
#   ./install-lsps.sh          install npm packages as the current user
#   ./install-lsps.sh --sudo   install npm packages with sudo
#   ./install-lsps.sh --config-only   skip npm, only merge the config

SUDO=""
CONFIG_ONLY=""
for arg in "$@"; do
  case "$arg" in
    --sudo) SUDO="sudo" ;;
    --config-only) CONFIG_ONLY="1" ;;
    *) echo "unknown flag: $arg" >&2; exit 1 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${HERE}/opencode.json"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"

# Column 1 of lsp-npm-packages.txt is the plugin, the rest its npm packages.
# OpenCode installs every server, so take all of them, de-duplicated.
mapfile -t NPM_PACKAGES < <(
  awk '!/^[[:space:]]*#/ && NF {for (i = 2; i <= NF; i++) if (!seen[$i]++) print $i}' \
    "${HERE}/../lsp-npm-packages.txt"
)

if [[ -z "$CONFIG_ONLY" ]]; then
  echo "==> Installing npm LSP packages globally..."
  $SUDO npm install -g "${NPM_PACKAGES[@]}"
  echo ""
fi

echo "==> Merging LSP config into ${DEST}..."
mkdir -p "$(dirname "$DEST")"

if [[ -f "$DEST" ]]; then
  cp "$DEST" "${DEST}.bak"
  echo "    backed up existing config to ${DEST}.bak"
fi

SRC="$SRC" DEST="$DEST" python3 - <<'PY'
import json, os, pathlib

src = pathlib.Path(os.environ["SRC"])
dest = pathlib.Path(os.environ["DEST"])

incoming = json.loads(src.read_text())
existing = {}
if dest.exists() and dest.read_text().strip():
    existing = json.loads(dest.read_text())

existing.setdefault("$schema", incoming["$schema"])

# `lsp: true` means "all built-ins"; replacing it with a dict would silently turn
# the built-ins off, so refuse rather than guess.
current = existing.get("lsp")
if isinstance(current, bool):
    raise SystemExit(
        f"{dest} sets \"lsp\": {json.dumps(current)}. Change it to an object "
        "(or remove it) before merging, so the merge does not clobber it."
    )

lsp = current or {}
for name, entry in incoming["lsp"].items():
    if name in lsp and lsp[name] != entry:
        print(f"    overwriting existing lsp server '{name}'")
    lsp[name] = entry
existing["lsp"] = lsp

dest.write_text(json.dumps(existing, indent=2) + "\n")
print(f"    merged {len(incoming['lsp'])} LSP server(s)")
PY

echo ""
echo "Done. Restart opencode for changes to take effect."
