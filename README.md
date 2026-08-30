# ai_stuff

Personal Claude Code / OpenCode configuration: LSP plugins and skills.

## Layout

| Path | What it is |
| --- | --- |
| `claude/` | Claude Code plugin marketplace (`vantreeseba-local`) — one LSP plugin per language. |
| `opencode/` | The same LSP servers as [OpenCode](https://opencode.ai) config. See [`opencode/README.md`](opencode/README.md). |
| `skills/` | Shared skills. |
| `lsp-npm-packages.txt` | The npm packages providing the LSP binaries, read by both installers. |
| `sync-opencode-lsp.py` | Regenerates everything under `opencode/` from the Claude plugin manifests. |
| `.github/workflows/check.yml` | CI: fails if the generated configs are stale, or if any JSON/shell is broken. |

## LSP servers

`haxe`, `graphql`, `typescript` (with `@0no-co/graphqlsp`), `css`, `html`,
`json`, `yaml`, `tailwindcss`, `dockerfile`.

## Install

```sh
./claude/install-lsps.sh      # npm binaries + `claude plugin install` each plugin
./opencode/install-lsps.sh    # npm binaries + merge into ~/.config/opencode/opencode.json
```

Both take `--sudo` to run `npm install -g` under sudo.

## Adding or changing a server

The Claude plugin manifests are the source of truth. Edit
`claude/<lang>-lsp-plugin/<lang>-lsp/.claude-plugin/plugin.json`, then:

```sh
./sync-opencode-lsp.py
```

CI runs `./sync-opencode-lsp.py --check` on every PR, so a manifest edit without
a regenerate fails the build rather than silently drifting.

That regenerates `opencode/opencode.json`, `opencode/lsp/*.json`, and the
per-plugin `opencode.json` files. For a brand-new plugin, also add it to
`claude/.claude-plugin/marketplace.json`, the `PLUGINS` list in
`claude/install-lsps.sh`, and `lsp-npm-packages.txt` if it needs a new binary.

The translation between the two formats:

| Claude Code (`lspServers`) | OpenCode (`lsp`) |
| --- | --- |
| `command` + `args` | `command: [cmd, ...args]` |
| `extensionToLanguage` | `extensions` (the keys; OpenCode infers the language) |
| `initializationOptions` | `initialization` |
| `env` | `env` |
| `${VAR}` | `{env:VAR}` |

`${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}` and `${CLAUDE_PROJECT_DIR}` have
no OpenCode equivalent; the generator errors out instead of emitting a variable
that would expand to an empty string.

## Known limitation

Neither tool can attach a language server to an extensionless `Dockerfile` —
Claude's `extensionToLanguage` keys are extensions only, and OpenCode resolves
`path.parse(file).ext || file`, which yields the full path for such a file. Use
`foo.dockerfile` if you want Dockerfile intelligence.
