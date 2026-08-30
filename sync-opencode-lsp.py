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
"""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
CLAUDE_DIR = ROOT / "claude"
OPENCODE_DIR = ROOT / "opencode"
SCHEMA = "https://opencode.ai/config.json"


def to_opencode(server):
    """Translate one Claude `lspServers` entry into an OpenCode `lsp` entry."""
    entry = {"command": [server["command"], *server.get("args", [])]}

    extensions = list(server.get("extensionToLanguage", {}).keys())
    if extensions:
        entry["extensions"] = extensions

    if "env" in server:
        entry["env"] = server["env"]

    # Claude calls them initializationOptions; OpenCode calls them initialization.
    if "initializationOptions" in server:
        entry["initialization"] = server["initializationOptions"]

    return entry


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"  wrote {path.relative_to(ROOT)}")


def main():
    manifests = sorted(CLAUDE_DIR.glob("*/*/.claude-plugin/plugin.json"))
    if not manifests:
        print(f"no plugin manifests found under {CLAUDE_DIR}", file=sys.stderr)
        return 1

    combined = {}

    for manifest_path in manifests:
        manifest = json.loads(manifest_path.read_text())
        servers = manifest.get("lspServers")
        if not servers:
            continue

        plugin_root = manifest_path.parent.parent
        lsp = {name: to_opencode(server) for name, server in servers.items()}

        # A standalone, directly usable opencode.json living beside the plugin.
        write_json(plugin_root / "opencode.json", {"$schema": SCHEMA, "lsp": lsp})

        for name, entry in lsp.items():
            if name in combined and combined[name] != entry:
                print(f"  warning: duplicate lsp server '{name}' - last one wins", file=sys.stderr)
            combined[name] = entry
            write_json(OPENCODE_DIR / "lsp" / f"{name}.json", {"$schema": SCHEMA, "lsp": {name: entry}})

    write_json(OPENCODE_DIR / "opencode.json", {"$schema": SCHEMA, "lsp": dict(sorted(combined.items()))})
    print(f"\n{len(combined)} LSP server(s) generated from {len(manifests)} plugin manifest(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
