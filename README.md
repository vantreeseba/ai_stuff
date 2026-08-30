# ai_stuff

Skills and Claude Code plugins for [opencode](https://opencode.ai) and
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

Plugins install through the `claude` CLI against the marketplace in `claude/`,
so they are Claude Code only — opencode configures language servers in its own
`opencode.json`.

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

## Plugins

LSP servers wired into Claude Code: Haxe, TypeScript, GraphQL, CSS, HTML, JSON,
YAML, Tailwind, and Dockerfile. `claude/install-lsps.sh` installs all of them at
once; `install.sh --plugins` picks a subset.

## Layout

```
install.sh              the installer
skills/<name>/          SKILL.md + references/
claude/                 Claude Code plugin marketplace
  .claude-plugin/marketplace.json
  <name>-lsp-plugin/
```

## Development

```bash
./install.sh --link --skills all --target claude
```

Symlinks instead of copies, so edits in the checkout take effect on the next
agent restart.
