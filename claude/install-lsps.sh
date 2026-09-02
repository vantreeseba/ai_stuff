#!/usr/bin/env bash
set -euo pipefail

SUDO=""
if [[ "${1:-}" == "--sudo" ]]; then
  SUDO="sudo"
fi

MARKETPLACE="vantreeseba-local"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PACKAGES_FILE="${HERE}/../lsp-npm-packages.txt"

# Both lists come from lsp-npm-packages.txt, so adding a plugin there is the
# only edit needed. Column 1 is the plugin, the rest are its npm packages.
mapfile -t PLUGINS < <(
  awk '!/^[[:space:]]*#/ && NF {print $1}' "$PACKAGES_FILE"
)
mapfile -t NPM_PACKAGES < <(
  awk '!/^[[:space:]]*#/ && NF {for (i = 2; i <= NF; i++) if (!seen[$i]++) print $i}' "$PACKAGES_FILE"
)

echo "==> Installing npm LSP packages globally..."
$SUDO npm install -g "${NPM_PACKAGES[@]}"

echo ""
echo "==> Installing Claude plugins..."
for plugin in "${PLUGINS[@]}"; do
  claude plugin install "${plugin}@${MARKETPLACE}" || true
done

echo ""
echo "Done. Restart Claude Code for changes to take effect."
