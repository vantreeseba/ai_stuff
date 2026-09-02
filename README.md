# ai_stuff

Skills and LSP plugins for [opencode](https://opencode.ai) and
[Claude Code](https://claude.com/claude-code).

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vantreeseba/ai_stuff/main/install.sh)
```

That opens a picker for skills and plugins, and installs into whichever agents
it finds on your `PATH`.

`curl … | bash` also works, but stdin is then the script itself, so the
interactive picker is unavailable and a selection must be passed:

```bash
curl -fsSL https://raw.githubusercontent.com/vantreeseba/ai_stuff/main/install.sh \
  | bash -s -- --skills all --plugins none
```

### Options

```
-l, --list            List available skills and plugins, then exit.
-s, --skills LIST     Comma-separated skill names, or "all" / "none".
-p, --plugins LIST    Comma-separated plugin names, or "all" / "none".
-a, --all             Install everything available for the chosen targets.
-t, --target TARGET   claude | opencode | project (comma-separated).
                      Default: whichever agents are on PATH.
    --link            Symlink skills from a local checkout instead of copying.
    --ref REF         Git ref to install from (default: main).
    --no-npm          Skip the global npm installs the LSP plugins need.
    --sudo            Use sudo for the global npm install.
-y, --yes             Non-interactive: overwrite without asking.
```

Selections accept numbers, ranges, and names: `--skills 1,4-6,haxe`.

### Where things land

| Target | Path |
| --- | --- |
| `claude` | `~/.claude/skills/` |
| `opencode` | `~/.config/opencode/skills/` |
| `project` | `./.claude/skills/` |

The per-tool installers are also usable directly:

```sh
./claude/install-lsps.sh      # npm binaries + `claude plugin install` each plugin
./opencode/install-lsps.sh    # npm binaries + merge into ~/.config/opencode/opencode.json
```

Both take `--sudo` to run `npm install -g` under sudo.

## Skills

Run `./install.sh --list` for the current list with descriptions.

| Skill | For |
| --- | --- |
| `ts-house-style` | Baseline TypeScript conventions — npm workspaces, ESM, Biome, git |
| `ts-backend` | Drizzle → GraphQL backends on Express 5 + Apollo Server |
| `ts-library` | Publishable npm packages, semantic-release, TypeDoc |
| `ts-testing` | Vitest, PGlite-backed fixtures, drift tests |
| `graphql-codegen` | The schema → types codegen pipeline |
| `graphql-frontend` | Apollo Client with component-owned fragments and masking |
| `simple-ts-frontend` | Vite + React + TanStack Router + shadcn/ui |
| `expo-frontend` | Expo Router clients for iOS/Android/web |
| `mcp-server` | MCP servers over streamable HTTP and stdio |
| `haxe` | Haxe language reference and compiler workflow |

## LSP servers

`haxe`, `graphql`, `typescript` (with `@0no-co/graphqlsp`), `css`, `html`,
`json`, `yaml`, `tailwindcss`, `dockerfile`.

Claude Code installs these as plugins through the marketplace in `claude/`;
opencode configures the same servers in its own `opencode.json`. See
[`opencode/README.md`](opencode/README.md) for the opencode side.

## Layout

| Path | What it is |
| --- | --- |
| `install.sh` | The installer — skills and plugins, for either agent. |
| `skills/<name>/` | `SKILL.md` + `references/`. |
| `claude/` | Claude Code plugin marketplace (`vantreeseba-local`) — one LSP plugin per language. |
| `opencode/` | The same LSP servers as opencode config. Generated. |
| `lsp-npm-packages.txt` | Which npm package provides each plugin's LSP binary. Read by all three installers. |
| `sync-opencode-lsp.py` | Regenerates everything under `opencode/` from the Claude plugin manifests. |
| `.github/workflows/check.yml` | CI: fails if the generated configs are stale, or if any JSON/shell is broken. |

## Adding or changing an LSP server

The Claude plugin manifests are the source of truth. Edit
`claude/<lang>-lsp-plugin/<lang>-lsp/.claude-plugin/plugin.json`, then:

```sh
./sync-opencode-lsp.py
```

CI runs `./sync-opencode-lsp.py --check` on every PR, so a manifest edit without
a regenerate fails the build rather than silently drifting.

That regenerates `opencode/opencode.json`, `opencode/lsp/*.json`, and the
per-plugin `opencode.json` files. For a brand-new plugin, also add it to
`claude/.claude-plugin/marketplace.json` and to `lsp-npm-packages.txt`:

```
<plugin-name>  [npm-package ...]
```

That one line is what tells `install.sh` which package to install for the
plugin, and what puts it in the list `claude/install-lsps.sh` walks — neither
script hardcodes a plugin or a package. Leave the packages empty for a plugin
whose binary comes from somewhere else, as `haxe-lsp-plugin` does. CI fails if
the file and the marketplace disagree in either direction.

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

## Development

```bash
./install.sh --link --skills all --target claude
```

Symlinks instead of copies, so edits in the checkout take effect on the next
agent restart.
