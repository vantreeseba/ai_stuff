#!/usr/bin/env python3
"""Generate OpenCode LSP configs from the Claude Code plugin manifests.

The Claude plugins in claude/*/*/.claude-plugin/plugin.json are the source of
truth. This script translates their `lspServers` blocks into OpenCode's `lsp`
config format and writes:

  claude/<plugin>/<name>/opencode.json   a standalone config for that one server
  opencode/lsp/<server>.json             the same fragment, collected in one place
  opencode/opencode.json                 every server merged into one config

Claude Code                     OpenCode
  command + args        ->        command: [cmd, ...args]
  extensionToLanguage   ->        extensions: [...keys]
  initializationOptions ->        initialization
  env                   ->        env
  ${VAR}                ->        {env:VAR}

Usage:
  ./sync-opencode-lsp.py            regenerate the OpenCode configs
  ./sync-opencode-lsp.py --check    fail if they are out of date (for CI)
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent
CLAUDE_DIR = ROOT / "claude"
OPENCODE_DIR = ROOT / "opencode"
SCHEMA = "https://opencode.ai/config.json"

# Claude Code expands ${VAR}; OpenCode expands {env:VAR}. Only plain environment
# variables translate — the Claude-specific ${CLAUDE_*} names have no OpenCode
# equivalent, so flag them rather than emit something that silently expands to "".
CLAUDE_ONLY_VARS = {"CLAUDE_PLUGIN_ROOT", "CLAUDE_PLUGIN_DATA", "CLAUDE_PROJECT_DIR"}
VAR_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


class SyncError(Exception):
    pass


def translate_vars(value, where):
    """Rewrite ${VAR} into OpenCode's {env:VAR} substitution syntax."""
    if not isinstance(value, str):
        return value

    for name in VAR_RE.findall(value):
        if name in CLAUDE_ONLY_VARS:
            raise SyncError(
                f"{where}: ${{{name}}} is Claude-specific and has no OpenCode "
                f"equivalent. Use a plain environment variable instead."
            )
    return VAR_RE.sub(r"{env:\1}", value)


def to_opencode(name, server):
    """Translate one Claude `lspServers` entry into an OpenCode `lsp` entry."""
    where = f"lsp server '{name}'"
    args = [translate_vars(a, where) for a in server.get("args", [])]
    entry = {"command": [translate_vars(server["command"], where), *args]}

    extensions = list(server.get("extensionToLanguage", {}).keys())
    if extensions:
        entry["extensions"] = extensions

    if "env" in server:
        entry["env"] = {k: translate_vars(v, where) for k, v in server["env"].items()}

    # Claude calls them initializationOptions; OpenCode calls them initialization.
    if "initializationOptions" in server:
        entry["initialization"] = server["initializationOptions"]

    return entry


def build():
    """Return {path: json-text} for every file this script owns."""
    manifests = sorted(CLAUDE_DIR.glob("*/*/.claude-plugin/plugin.json"))
    if not manifests:
        raise SyncError(f"no plugin manifests found under {CLAUDE_DIR}")

    files = {}
    combined = {}

    def add(path, data):
        files[path] = json.dumps(data, indent=2) + "\n"

    for manifest_path in manifests:
        manifest = json.loads(manifest_path.read_text())
        servers = manifest.get("lspServers")
        if not servers:
            continue

        plugin_root = manifest_path.parent.parent
        lsp = {name: to_opencode(name, server) for name, server in servers.items()}

        # A standalone, directly usable opencode.json living beside the plugin.
        add(plugin_root / "opencode.json", {"$schema": SCHEMA, "lsp": lsp})

        for name, entry in lsp.items():
            if name in combined and combined[name] != entry:
                raise SyncError(
                    f"two plugins define lsp server '{name}' with different "
                    f"settings; rename one of them"
                )
            combined[name] = entry
            add(OPENCODE_DIR / "lsp" / f"{name}.json", {"$schema": SCHEMA, "lsp": {name: entry}})

    add(OPENCODE_DIR / "opencode.json", {"$schema": SCHEMA, "lsp": dict(sorted(combined.items()))})
    return files, len(combined), len(manifests)


def main(argv):
    check = "--check" in argv[1:]
    unknown = [a for a in argv[1:] if a != "--check"]
    if unknown:
        print(f"unknown argument: {unknown[0]}\n\n{__doc__}", file=sys.stderr)
        return 2

    try:
        files, servers, manifests = build()
    except SyncError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1

    if check:
        stale = [
            path for path, text in files.items()
            if not path.exists() or path.read_text() != text
        ]
        if stale:
            print("OpenCode configs are out of date:", file=sys.stderr)
            for path in sorted(stale):
                print(f"  {path.relative_to(ROOT)}", file=sys.stderr)
            print("\nRun ./sync-opencode-lsp.py and commit the result.", file=sys.stderr)
            return 1
        print(f"up to date: {len(files)} file(s), {servers} LSP server(s).")
        return 0

    for path, text in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(f"  wrote {path.relative_to(ROOT)}")
    print(f"\n{servers} LSP server(s) generated from {manifests} plugin manifest(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
