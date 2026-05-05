#!/usr/bin/env bash
set -euo pipefail

SUDO=""
if [[ "${1:-}" == "--sudo" ]]; then
  SUDO="sudo"
fi

MARKETPLACE="vantreeseba-local"

# haxe-lsp-plugin uses a local binary — no npm package needed
NPM_PACKAGES=(
  vscode-langservers-extracted
  typescript-language-server
  typescript
  graphql-language-service-cli
  yaml-language-server
  @tailwindcss/language-server
  dockerfile-language-server-nodejs
)

PLUGINS=(
  haxe-lsp-plugin
  graphql-lsp-plugin
  typescript-lsp-plugin
  css-lsp-plugin
  html-lsp-plugin
  json-lsp-plugin
  yaml-lsp-plugin
  tailwind-lsp-plugin
  dockerfile-lsp-plugin
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
