---
name: mcp-server
description: >
  Build or modify a cubicecho MCP server — Express 5 + @modelcontextprotocol/sdk
  over streamable HTTP and stdio, env-driven config validated with zod, bearer
  token auth, a single write gate, and tool design rules. Also covers exposing an
  existing GraphQL schema as MCP via @cubicecho/graphql-mcp. Use when adding a
  tool, wiring a transport, or standing up a new MCP server.
version: 0.0.1
license: MIT
---

# MCP Server

The loadout for MCP servers that front a real system. If a `ts-house-style`
skill is available, read it for the shared TypeScript conventions; a
`ts-library` skill covers publishing when the server also ships to npm, and a
`ts-testing` skill covers the suite. None of them are required for this one.

## The loadout

| Concern | Choice |
| --- | --- |
| Transport | Express 5 + `StreamableHTTPServerTransport` at `/mcp`, stateless |
| CLI | `StdioServerTransport` from a separate `src/stdio.ts` entry point |
| SDK | `@modelcontextprotocol/sdk` — high-level `McpServer` + `registerTool`. The low-level `Server` class is deprecated |
| Config | env only, validated with zod in one place |
| Auth | one bearer token, plus a trusted-network escape hatch |
| Runtime | Node 22+, `.ts` directly in dev; `tsc` with `rewriteRelativeImportExtensions` → `dist/` for prod |
| Lint | Biome |

## Structure

Single package, no workspaces, unless a web UI ships with it.

```
src/
├── config.ts        # env → validated Config (zod). The ONE place env is read
├── auth.ts  errors.ts  version.ts
├── <domain>/client.ts  # the wrapped upstream client singleton
├── <domain>/*.ts       # one repo per area
├── mcp/tool.ts  mcp/server.ts  mcp/routes.ts  mcp/tools/*.ts
├── app.ts           # buildApp(deps) — Express app, no listen()
├── index.ts         # HTTP entry point
└── stdio.ts         # stdio entry point
```

**Nothing outside `src/<domain>/` imports the upstream library.** That is what
the wrapper is for; a new tool adds a repo method, not a second entry point.

→ **[`references/folder-structure.md`](references/folder-structure.md)** — the
full tree, `buildApp` vs `listen`, the entry point with its shutdown latch and
startup banner, the command list, and the role of `SPECS.md` / `TODO_IDEAS.md`.

## Transports

Streamable HTTP is **stateless** — `sessionIdGenerator: undefined`, a fresh
`McpServer` and transport per request, torn down on `res.on('close')`. A fresh
server is cheap; the expensive state lives behind the shared client.

stdio has two rules that produce baffling symptoms when broken: **never write to
stdout** (it is the transport — log to stderr), and **do not open the upstream
eagerly** (the client is waiting on the initialize handshake).

Where the upstream library is backed by a global singleton, wrap it once and
serialize every operation through a promise chain, with a per-operation timeout.
With one queue an unbounded hang stalls the whole server, not one request.

→ **[`references/transports.md`](references/transports.md)** — both entry points
in full, the transport options that matter, the serialized client, and the
child-process rules.

## Config and auth

**Env-only. No config file to keep in sync.** `loadConfig()` validates the whole
environment up front and **reports every problem at once**, naming the env var
rather than the field. Nothing else reads `process.env`.

A single bearer token guards `/mcp` and `/api/*`; `/api/status` stays open as a
liveness probe. `SECURE_LOCAL_NET=true` disables auth entirely — the
trusted-network escape hatch, and an explicit opt-in.

The server **refuses to start unauthenticated** unless that flag is set. An
omission and a typo must not be the same thing: leaving the token unset is
indistinguishable from misspelling it, and "warn and start anyway" turns one
typo into a silent, open, writable server.

→ **[`references/config-and-auth.md`](references/config-and-auth.md)** — the zod
schema, the env readers (including why a boolean typo must fail), the
constant-time token comparison, and the refuse-to-start check.

## Tool design

**Every tool is a new blast radius over someone's real data.** Build what is
specified; nothing speculative, and check `TODO_IDEAS.md` first.

- **One write gate.** `<NAME>_ENABLE_WRITES` governs every mutating tool. No
  second destructive tier — deletes are ordinary writes. When it is off,
  mutating tools are **not advertised in `tools/list`**: never show an agent a
  tool it cannot call.
- Tools are declared as data (`defineTool`) and registered in one loop, so the
  gate and the MCP annotations apply uniformly. `destructive` and `idempotent`
  are declared per tool, not derived from each other — clients auto-approve on
  them.
- A failing tool returns `isError: true` with a readable message, never a thrown
  transport exception.
- **Money is integer minor units.** Never float math, and never *accept* a
  decimal.

→ **[`references/tool-design.md`](references/tool-design.md)** — `ToolDefinition`,
the gate, the registration loop, prompts, the data rules, fronting a GraphQL
schema with `@cubicecho/graphql-mcp`, and the `shared/` contract package.
