# Transports

Two entry points, one server builder. The SDK's high-level `McpServer` +
`registerTool` is the API to use — the low-level `Server` class is deprecated.

## Streamable HTTP, stateless

```typescript
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { Router } from 'express';

/**
 * Streamable-HTTP MCP endpoint at `/mcp`. Stateless: a fresh server +
 * transport per request, torn down when the response closes. Nothing here is
 * session-scoped — the upstream state lives behind the shared repos' client —
 * so there is no reason to keep sessions around.
 */
export function createMcpRouter(deps: McpRouterDeps): Router {
  const router = Router();

  router.all('/', async (req, res) => {
    const server = createActualServer({ repos: deps.repos, enableWrites: deps.enableWrites });
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,   // ← stateless
      enableJsonResponse: true,
    });
    res.on('close', () => {
      transport.close().catch((err: unknown) => console.warn(`MCP transport close failed: ${errorMessage(err)}`));
      server.close().catch((err: unknown) => console.warn(`MCP server close failed: ${errorMessage(err)}`));
    });
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  });

  return router;
}
```

- **`sessionIdGenerator: undefined` is what makes it stateless.** Give it a
  generator and the SDK starts tracking sessions, which you then have to store,
  expire, and reap. Do that only if the server genuinely holds per-client state.
- **`enableJsonResponse: true`** returns a plain JSON body rather than an SSE
  stream where the response fits in one message — simpler for clients and for
  `curl`.
- **`router.all('/')`, not `.post`.** The transport handles GET (stream open),
  POST (requests), and DELETE (session teardown) itself.
- **`res.on('close')` teardown, both halves.** Without it every request leaks a
  server and a transport.
- `express.json()` must run before the router — `handleRequest` is given
  `req.body`.

A fresh `McpServer` per request is cheap. The expensive state (the open budget,
the authenticated session) lives behind the shared client, which is constructed
once at startup and captured in `deps`.

## stdio

```typescript
#!/usr/bin/env node
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';

/**
 * stdio MCP entry point for local clients (Claude Code, Claude Desktop, …).
 * Configuration comes from the same env vars as the HTTP server; the upstream
 * is opened lazily on the first tool call so a slow or unreachable server never
 * stalls the client's startup handshake.
 */
async function main(): Promise<void> {
  const config = loadConfig();
  const client = new ActualClient(config);

  const server = createActualServer({ repos: createRepos(client), enableWrites: config.enableWrites });
  const transport = new StdioServerTransport();
  await server.connect(transport);

  // Log to stderr — stdout is the MCP transport channel and must stay clean.
  console.error(`mcp-actual stdio ready (writes ${config.enableWrites ? 'enabled' : 'disabled'})`);

  const shutdown = () => {
    client
      .close()
      .catch((err: unknown) => console.error(`Shutdown error: ${errorChainMessage(err)}`))
      .finally(() => process.exit(0));
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main().catch((err: unknown) => {
  console.error(`Fatal stdio startup error: ${errorChainMessage(err)}`);
  process.exit(1);
});
```

Two rules that are easy to get wrong and produce baffling symptoms:

- **Never write to stdout.** It is the transport. A stray `console.log` — in
  your code or in a dependency — corrupts the JSON-RPC stream and the client
  reports a parse error with no useful context. Everything goes to stderr.
- **Do not open the upstream eagerly here.** The HTTP entry point does, because
  it wants misconfiguration visible at startup. stdio does not, because the
  client is waiting on the initialize handshake and a slow upstream reads as a
  hung server. This asymmetry is deliberate.

The `#!/usr/bin/env node` shebang plus a `bin` entry in `package.json` is what
makes `npx <pkg>` work as a stdio server in a client's config.

## The shared client

Where the upstream library is backed by a global singleton — an open SQLite
file, one authenticated session, a process-wide `init()` — **two overlapping
calls race**. Wrap it once and serialize:

```typescript
/**
 * `@actual-app/api` is a process-wide singleton: `init` opens one SQLite budget
 * and every other call reads that global state, so two overlapping calls would
 * race. This client owns that global, opens the budget lazily on first use, and
 * serializes every operation through a promise chain.
 */
export class ActualClient {
  /** Resolves once init + download have succeeded; cleared on failure so the next call retries. */
  private ready: Promise<void> | null = null;
  /** Tail of the serialized operation queue — every `run` links onto it. */
  private queue: Promise<unknown> = Promise.resolve();
  /** True while an operation has passed its deadline but not yet settled. */
  private stalled = false;

  run<T>(fn: () => Promise<T>, options?: { timeoutMs?: number }): Promise<T> { … }
}
```

Two details worth copying:

- **`ready` is cleared on failure**, so a transient upstream outage does not
  poison the process — the next call retries instead of resolving a rejected
  promise forever.
- **The stall check happens before enqueuing, not inside the queued body.**
  While an operation is hung the queue never advances, so a check inside would
  itself wait out the full deadline and report a timeout instead of the real
  reason. Failing immediately turns an invisible wait into a legible error:

  ```
  Actual is not responding: a previous operation passed its deadline and has not
  finished. Every call is serialized behind it, so nothing can run until it does.
  Restart the server if this persists.
  ```

A per-operation `timeoutMs` ceiling is not optional here. With one queue, an
unbounded hang does not stall one request — it stalls the whole server,
permanently.

## Child processes

When the server spawns downstream servers:

- Always `execFile`/`spawn` with an **arg array** — never string interpolation
  into a shell.
- The child's env is an **explicit allowlist** (`PATH`, `HOME`, …) plus the
  configured `env` — never the whole `process.env`.
- Spawn lazily and reap on shutdown.
