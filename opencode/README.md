# OpenCode LSP config

The same LSP servers as the Claude Code plugins in [`../claude`](../claude), in
[OpenCode's](https://opencode.ai/docs/lsp/) config format.

Everything here is **generated** — edit the Claude plugin manifests
(`claude/*/*/.claude-plugin/plugin.json`) and re-run the generator from the repo
root:

```sh
./sync-opencode-lsp.py
```

## Layout

| Path | What it is |
| --- | --- |
| `opencode.json` | All 9 servers in one config. This is what the installer merges. |
| `lsp/<server>.json` | One server per file, each a valid standalone `opencode.json`. |
| `install-lsps.sh` | Installs the npm LSP binaries and merges `opencode.json` into your global config. |

Each Claude plugin also carries its own `opencode.json` next to its
`.claude-plugin/` directory, so a single plugin folder works with both tools.

## Install

```sh
./install-lsps.sh              # npm install -g the servers, then merge the config
./install-lsps.sh --sudo       # same, but npm install with sudo
./install-lsps.sh --config-only  # skip npm, only merge the config
```

The merge target is `${XDG_CONFIG_HOME:-~/.config}/opencode/opencode.json`. Your
existing config is backed up to `opencode.json.bak` first, non-`lsp` keys are
left alone, and LSP servers you defined yourself are kept unless they collide
with one of these names (collisions are printed).

If your config currently has `"lsp": true` the installer stops rather than
replace it, since swapping that boolean for an object would silently disable
OpenCode's built-in servers.

## Picking servers by hand

To use just one, copy or symlink a fragment into a project:

```sh
cp ~/code/vantreeseba/ai_stuff/opencode/lsp/haxe.json ./opencode.json
```

Or paste the entry into an existing `opencode.json` under `lsp`.

## Notes

- **`typescript` overrides a built-in.** OpenCode ships its own TypeScript
  server; this entry replaces it to add the `@0no-co/graphqlsp` tsserver plugin
  for embedded GraphQL. Drop the `typescript` key if you want the stock one.
- **`dockerfile` only matches `*.dockerfile`.** OpenCode routes by file
  extension, so an extensionless `Dockerfile` won't start the server — the same
  limitation the Claude plugin has.
- **`haxe` points at `~/bin/haxe-lsp.js`**, a local build rather than an npm
  package. Adjust the path in the plugin manifest if yours lives elsewhere.
- **`tailwindcss` deliberately shares extensions** with the `css`, `html`, and
  `typescript` servers; OpenCode runs every server whose extensions match.
