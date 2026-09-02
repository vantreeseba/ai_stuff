#!/usr/bin/env bash
#
# Install vantreeseba/ai_stuff skills and Claude Code plugins.
#
#   curl -fsSL https://raw.githubusercontent.com/vantreeseba/ai_stuff/main/install.sh | bash
#
# Run with --help for options.

set -euo pipefail

REPO="vantreeseba/ai_stuff"
REF="${AI_STUFF_REF:-main}"
CACHE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/vantreeseba-ai-stuff"

# --- options ---------------------------------------------------------------

OPT_LIST=0
OPT_SKILLS=""
OPT_PLUGINS=""
OPT_TARGET=""
OPT_LINK=0
OPT_NO_NPM=0
OPT_SUDO=""
OPT_YES=0

usage() {
  cat <<'EOF'
Install skills and Claude Code plugins from vantreeseba/ai_stuff.

Usage:
  install.sh [options]

Options:
  -l, --list            List available skills and plugins, then exit.
  -s, --skills LIST     Comma-separated skill names, or "all" / "none".
  -p, --plugins LIST    Comma-separated plugin names, or "all" / "none".
  -a, --all             Install everything available for the chosen targets.
  -t, --target TARGET   Where skills go. One or more of, comma-separated:
                          claude    ~/.claude/skills
                          opencode  ~/.config/opencode/skills
                          project   ./.claude/skills
                        Default: whichever agents are detected on PATH.
      --link            Symlink skills from the local checkout instead of
                        copying, so `git pull` updates them in place.
      --ref REF         Git ref to install from (default: main).
      --no-npm          Skip the global npm installs the LSP plugins need.
      --sudo            Use sudo for the global npm install.
  -y, --yes             Non-interactive: overwrite without asking.
  -h, --help            This message.

Examples:
  install.sh                                  interactive picker
  install.sh --list
  install.sh --skills ts-backend,haxe --target opencode
  install.sh --all --yes
  install.sh --skills all --plugins none --target claude,opencode
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -l|--list)    OPT_LIST=1 ;;
    -s|--skills)  OPT_SKILLS="${2:-}"; shift ;;
    -p|--plugins) OPT_PLUGINS="${2:-}"; shift ;;
    -a|--all)     OPT_SKILLS="all"; OPT_PLUGINS="all"; OPT_YES=1 ;;
    -t|--target)  OPT_TARGET="${2:-}"; shift ;;
    --link)       OPT_LINK=1 ;;
    --ref)        REF="${2:-main}"; shift ;;
    --no-npm)     OPT_NO_NPM=1 ;;
    --sudo)       OPT_SUDO="sudo" ;;
    -y|--yes)     OPT_YES=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; echo "try --help" >&2; exit 2 ;;
  esac
  shift
done

# --- terminal --------------------------------------------------------------

# `curl … | bash` makes stdin the script itself, so reads must come from the
# terminal directly. fd 3 is the user; stdin stays whatever it was.
HAVE_TTY=0
if { exec 3</dev/tty; } 2>/dev/null; then
  HAVE_TTY=1
fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; R=$'\033[0m'
else
  B=""; DIM=""; GRN=""; YEL=""; RED=""; R=""
fi

say()  { printf '%s\n' "$*"; }
info() { printf '%s==>%s %s\n' "$B" "$R" "$*"; }
warn() { printf '%swarning:%s %s\n' "$YEL" "$R" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$RED" "$R" "$*" >&2; exit 1; }

ask() {
  # ask <prompt> <default>; echoes the answer
  local prompt="$1" default="$2" reply=""
  if [ "$OPT_YES" = 1 ] || [ "$HAVE_TTY" = 0 ]; then
    printf '%s' "$default"; return
  fi
  printf '%s' "$prompt" >&2
  IFS= read -r reply <&3 || reply=""
  printf '%s' "${reply:-$default}"
}

# --- source tree -----------------------------------------------------------

# A checkout we were run from wins; otherwise keep a cached one so the Claude
# marketplace has a stable path to point at and re-runs are cheap.
SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  maybe="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [ -d "$maybe/skills" ] && SRC="$maybe"
fi

CLEANUP_DIR=""
trap '[ -n "$CLEANUP_DIR" ] && rm -rf "$CLEANUP_DIR"' EXIT

fetch_source() {
  info "Fetching $REPO@$REF"
  local tmp; tmp="$(mktemp -d)"
  CLEANUP_DIR="$tmp"

  if ! curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF" \
      | tar -xzf - -C "$tmp"; then
    die "could not download $REPO@$REF"
  fi

  local unpacked; unpacked="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
  [ -d "$unpacked/skills" ] || die "downloaded archive has no skills/ directory"

  mkdir -p "$(dirname "$CACHE_DIR")"
  rm -rf "$CACHE_DIR"
  mv "$unpacked" "$CACHE_DIR"
  SRC="$CACHE_DIR"
}

if [ -z "$SRC" ]; then
  command -v curl >/dev/null 2>&1 || die "curl is required"
  command -v tar  >/dev/null 2>&1 || die "tar is required"
  fetch_source
fi

if [ "$OPT_LINK" = 1 ] && [ "$SRC" = "$CACHE_DIR" ]; then
  warn "--link points at the cached copy in $CACHE_DIR, not a git checkout"
fi

# --- discovery -------------------------------------------------------------

# Skill metadata comes from the SKILL.md frontmatter, so adding a skill to the
# repo needs no edit here.
skill_desc() {
  awk '
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR > 1 && /^---[[:space:]]*$/        { exit }
    /^description:[[:space:]]*>/         { d = 1; next }
    /^description:[[:space:]]*[^[:space:]]/ {
      sub(/^description:[[:space:]]*/, ""); desc = $0; next
    }
    d && /^[[:space:]]+[^[:space:]]/ {
      sub(/^[[:space:]]+/, ""); desc = desc (desc ? " " : "") $0; next
    }
    d && /^[^[:space:]]/ { d = 0 }
    END {
      sub(/\.[[:space:]].*$/, ".", desc)   # first sentence only
      if (length(desc) > 88) desc = substr(desc, 1, 85) "..."
      print desc
    }
  ' "$1"
}

SKILLS=()
SKILL_DESCS=()
SKILL_LIST=""
for d in "$SRC"/skills/*/; do
  [ -f "$d/SKILL.md" ] || continue
  sk_name="$(basename "$d")"
  sk_desc="$(skill_desc "$d/SKILL.md")"
  SKILLS+=("$sk_name")
  SKILL_DESCS+=("$sk_desc")
  SKILL_LIST="$SKILL_LIST$sk_name	$sk_desc
"
done
[ ${#SKILLS[@]} -gt 0 ] || die "no skills found in $SRC/skills"

MARKETPLACE_DIR="$SRC/claude"
MARKETPLACE=""
if [ -f "$MARKETPLACE_DIR/.claude-plugin/marketplace.json" ]; then
  MARKETPLACE="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$MARKETPLACE_DIR/.claude-plugin/marketplace.json" | head -1)"
fi

PLUGINS=()
PLUGIN_DESCS=()
PLUGIN_LIST=""
if [ -n "$MARKETPLACE" ]; then
  for d in "$MARKETPLACE_DIR"/*/; do
    pl_name="$(basename "$d")"
    manifest="$(find "$d" -maxdepth 3 -name plugin.json -path '*/.claude-plugin/*' 2>/dev/null | head -1)"
    [ -n "$manifest" ] || continue
    pl_desc="$(sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -1)"
    PLUGINS+=("$pl_name")
    PLUGIN_DESCS+=("$pl_desc")
    PLUGIN_LIST="$PLUGIN_LIST$pl_name	$pl_desc
"
  done
fi

# LSP plugins need their language server on PATH. haxe-lsp-plugin ships its own.
npm_packages_for() {
  case "$1" in
    css-lsp-plugin|html-lsp-plugin|json-lsp-plugin) echo "vscode-langservers-extracted" ;;
    typescript-lsp-plugin) echo "typescript-language-server typescript" ;;
    graphql-lsp-plugin)    echo "graphql-language-service-cli" ;;
    yaml-lsp-plugin)       echo "yaml-language-server" ;;
    tailwind-lsp-plugin)   echo "@tailwindcss/language-server" ;;
    dockerfile-lsp-plugin) echo "dockerfile-language-server-nodejs" ;;
    *) echo "" ;;
  esac
}

if [ "$OPT_LIST" = 1 ]; then
  say "${B}Skills${R} ${DIM}(--skills)${R}"
  for ((i = 0; i < ${#SKILLS[@]}; i++)); do
    printf '  %-20s %s%s%s\n' "${SKILLS[$i]}" "$DIM" "${SKILL_DESCS[$i]}" "$R"
  done
  if [ ${#PLUGINS[@]} -gt 0 ]; then
    say ""
    say "${B}Claude Code plugins${R} ${DIM}(--plugins)${R}"
    for ((i = 0; i < ${#PLUGINS[@]}; i++)); do
      printf '  %-24s %s%s%s\n' "${PLUGINS[$i]}" "$DIM" "${PLUGIN_DESCS[$i]}" "$R"
    done
  fi
  exit 0
fi

# --- selection -------------------------------------------------------------

# Turns "all" / "none" / "1 3 5" / "2-4" / "name,other" into names, one per line.
resolve_selection() {
  local input="$1"; shift
  local -a pool=("$@")
  local out=() tok

  case "$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')" in
    all|a|"*") printf '%s\n' "${pool[@]}"; return ;;
    none|n|q|"") return ;;
  esac

  for tok in $(printf '%s' "$input" | tr ',' ' '); do
    if [[ "$tok" =~ ^[0-9]+-[0-9]+$ ]]; then
      local lo="${tok%-*}" hi="${tok#*-}" j
      for ((j = lo; j <= hi; j++)); do
        [ "$j" -ge 1 ] && [ "$j" -le "${#pool[@]}" ] && out+=("${pool[$((j - 1))]}")
      done
    elif [[ "$tok" =~ ^[0-9]+$ ]]; then
      [ "$tok" -ge 1 ] && [ "$tok" -le "${#pool[@]}" ] && out+=("${pool[$((tok - 1))]}")
    else
      local found=0 p
      for p in "${pool[@]}"; do [ "$p" = "$tok" ] && { out+=("$p"); found=1; break; }; done
      [ "$found" = 1 ] || warn "no such entry: $tok"
    fi
  done
  [ ${#out[@]} -gt 0 ] && printf '%s\n' "${out[@]}" | awk '!seen[$0]++'
}

pick() {
  # pick <title> <preselected> <name>\t<desc> lines on stdin
  local title="$1" preset="$2"
  local names=() descs=() line

  while IFS=$'\t' read -r n d; do
    [ -n "$n" ] || continue
    names+=("$n"); descs+=("$d")
  done

  [ ${#names[@]} -gt 0 ] || return 0

  if [ -n "$preset" ]; then
    resolve_selection "$preset" "${names[@]}"; return
  fi
  if [ "$HAVE_TTY" = 0 ]; then
    die "no terminal available for the picker — pass --skills/--plugins/--all"
  fi

  say "" >&2
  say "${B}$title${R}" >&2
  local i
  for ((i = 0; i < ${#names[@]}; i++)); do
    printf '  %2d) %-22s %s%s%s\n' "$((i + 1))" "${names[$i]}" "$DIM" "${descs[$i]}" "$R" >&2
  done
  say "" >&2
  local reply
  reply="$(ask "  Select ${DIM}(numbers, ranges, names, ${R}all${DIM}, ${R}none${DIM})${R} [all]: " "all")"
  resolve_selection "$reply" "${names[@]}"
}

# --- targets ---------------------------------------------------------------

target_dir() {
  case "$1" in
    claude)   printf '%s' "$HOME/.claude/skills" ;;
    opencode) printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills" ;;
    project)  printf '%s' "$PWD/.claude/skills" ;;
    *) die "unknown target: $1 (claude, opencode, project)" ;;
  esac
}

HAS_CLAUDE=0;   command -v claude   >/dev/null 2>&1 && HAS_CLAUDE=1
HAS_OPENCODE=0; command -v opencode >/dev/null 2>&1 && HAS_OPENCODE=1

TARGETS=()
if [ -n "$OPT_TARGET" ]; then
  IFS=',' read -r -a TARGETS <<<"$OPT_TARGET"
else
  [ "$HAS_CLAUDE" = 1 ]   && TARGETS+=("claude")
  [ "$HAS_OPENCODE" = 1 ] && TARGETS+=("opencode")
  if [ ${#TARGETS[@]} -eq 0 ]; then
    warn "neither claude nor opencode found on PATH; defaulting to claude"
    TARGETS=("claude")
  fi
fi

# The pickers run inside process substitution, so a `die` in there would only
# kill the subshell. Decide up front whether interaction is possible.
if [ "$HAVE_TTY" = 0 ]; then
  if [ -z "$OPT_SKILLS" ] && [ -z "$OPT_PLUGINS" ]; then
    die "no terminal for the interactive picker.
  Either pass a selection:   install.sh --skills all --plugins none
  or keep stdin free:        bash <(curl -fsSL https://raw.githubusercontent.com/$REPO/$REF/install.sh)"
  fi
  [ -n "$OPT_SKILLS" ]  || OPT_SKILLS="none"
  [ -n "$OPT_PLUGINS" ] || OPT_PLUGINS="none"
fi

# --- install skills --------------------------------------------------------

CHOSEN_SKILLS=()
while IFS= read -r line; do
  [ -n "$line" ] && CHOSEN_SKILLS+=("$line")
done < <(pick "Skills" "$OPT_SKILLS" <<<"$SKILL_LIST")

OVERWRITE_ALL="$OPT_YES"
install_skill() {
  local name="$1"
  local dest="$2"
  local src="$SRC/skills/$name"

  if [ -e "$dest/$name" ] || [ -L "$dest/$name" ]; then
    if [ "$OVERWRITE_ALL" != 1 ]; then
      local reply; reply="$(ask "  $name exists in $dest — overwrite? [y/N/a] " "n")"
      case "$reply" in
        a|A) OVERWRITE_ALL=1 ;;
        y|Y) ;;
        *) say "  ${DIM}skipped $name${R}"; return ;;
      esac
    fi
    rm -rf "$dest/$name"
  fi

  if [ "$OPT_LINK" = 1 ]; then
    ln -sfn "$src" "$dest/$name"
    say "  ${GRN}linked${R} $name"
  else
    cp -R "$src" "$dest/$name"
    say "  ${GRN}installed${R} $name"
  fi
}

INSTALLED=0
if [ ${#CHOSEN_SKILLS[@]} -gt 0 ]; then
  for t in "${TARGETS[@]}"; do
    dest="$(target_dir "$t")"
    mkdir -p "$dest"
    say ""
    info "Installing ${#CHOSEN_SKILLS[@]} skill(s) into $dest"
    for s in "${CHOSEN_SKILLS[@]}"; do install_skill "$s" "$dest"; done
    INSTALLED=$((INSTALLED + ${#CHOSEN_SKILLS[@]}))
  done
else
  say ""
  info "No skills selected."
fi

# --- install plugins -------------------------------------------------------

# Plugins install through the claude CLI against a marketplace, so they are
# Claude-only. opencode configures language servers in its own opencode.json.
CHOSEN_PLUGINS=()
if [ ${#PLUGINS[@]} -gt 0 ] && [ "$HAS_CLAUDE" = 1 ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && CHOSEN_PLUGINS+=("$line")
  done < <(pick "Claude Code plugins (LSP servers)" "$OPT_PLUGINS" <<<"$PLUGIN_LIST")
elif [ -n "$OPT_PLUGINS" ] && [ "$OPT_PLUGINS" != "none" ] && [ "$HAS_CLAUDE" != 1 ]; then
  warn "plugins requested but the claude CLI is not on PATH — skipping"
fi

if [ ${#CHOSEN_PLUGINS[@]} -gt 0 ]; then
  pkgs=()
  for p in "${CHOSEN_PLUGINS[@]}"; do
    for pkg in $(npm_packages_for "$p"); do
      printf '%s\n' "${pkgs[@]:-}" | grep -qxF "$pkg" || pkgs+=("$pkg")
    done
  done

  if [ ${#pkgs[@]} -gt 0 ] && [ "$OPT_NO_NPM" != 1 ]; then
    if command -v npm >/dev/null 2>&1; then
      say ""
      info "Installing language servers: ${pkgs[*]}"
      $OPT_SUDO npm install -g "${pkgs[@]}" \
        || warn "npm install failed — retry with --sudo, or install these yourself"
    else
      warn "npm not found; these language servers must be installed manually: ${pkgs[*]}"
    fi
  fi

  say ""
  info "Registering marketplace $MARKETPLACE"
  claude plugin marketplace add "$MARKETPLACE_DIR" >/dev/null 2>&1 \
    || claude plugin marketplace update "$MARKETPLACE" >/dev/null 2>&1 \
    || warn "could not register the marketplace at $MARKETPLACE_DIR"

  info "Installing ${#CHOSEN_PLUGINS[@]} plugin(s)"
  for p in "${CHOSEN_PLUGINS[@]}"; do
    if claude plugin install "$p@$MARKETPLACE" >/dev/null 2>&1; then
      say "  ${GRN}installed${R} $p"
    else
      say "  ${RED}failed${R} $p ${DIM}(already installed?)${R}"
    fi
  done
fi

# --- done ------------------------------------------------------------------

say ""
say "${GRN}Done.${R}"
[ "$INSTALLED" -gt 0 ] && say "  Skills:  ${CHOSEN_SKILLS[*]}"
[ ${#CHOSEN_PLUGINS[@]} -gt 0 ] && say "  Plugins: ${CHOSEN_PLUGINS[*]}"
say "  Source:  $SRC"
say ""
say "${DIM}Restart your agent for the changes to take effect.${R}"
