# Folder structure and entry points

Single package, no workspaces, unless a web UI ships with it.

```
src/
├── config.ts           # env → validated Config (zod). The ONE place env is read
├── auth.ts             # bearer middleware + the SECURE_LOCAL_NET escape hatch
├── errors.ts           # HttpError, errorMessage, errorChainMessage
├── version.ts          # SERVER_VERSION, read from package.json at build
├── <domain>/
│   ├── client.ts       # the wrapped upstream client singleton
│   ├── index.ts        # createRepos(client) → the repos object
│   ├── types.ts
│   └── <area>.ts       # one repo per area: accounts.ts, budgets.ts, …
├── mcp/
│   ├── tool.ts         # ToolDefinition + defineTool
│   ├── server.ts       # createXServer(): registers tools and prompts
│   ├── routes.ts       # stateless streamable-HTTP transport at /mcp
│   ├── prompts.ts
│   └── tools/<area>.ts # one file per repo area
├── app.ts              # buildApp(deps) — Express app, no listen()
├── index.ts            # HTTP entry point
└── stdio.ts            # stdio entry point
```

Tests sit beside their subject (`config.test.ts` next to `config.ts`).

## The dependency direction

```
index.ts / stdio.ts   →  config, client, mcp/server
mcp/tools/*           →  <domain>/* repos
<domain>/*            →  <domain>/client.ts
<domain>/client.ts    →  the upstream library
```

Nothing outside `src/<domain>/` imports the upstream library. That is the whole
point of the wrapper: a new tool adds a repo method, not a second entry point
into a library backed by global state.

## `buildApp` separate from `listen`

```typescript
export function buildApp(deps: AppDeps): express.Express {
  const { repos, config } = deps;
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '1mb' }));

  const auth = createAuthMiddleware(() => ({
    enabled: config.authToken !== null && !authDisabledByEnv(),
    token: config.authToken,
  }));

  // Unauthenticated liveness probe — reports nothing about the data itself.
  app.get('/api/status', (_req, res) => {
    res.json({ name: 'mcp-actual', version: SERVER_VERSION, serverUrl: config.serverUrl });
  });

  app.use('/mcp', auth, createMcpRouter({ repos, enableWrites: config.enableWrites }));

  app.use((_req, res) => {
    res.status(404).json({ error: 'Not found' });
  });

  app.use(((err, _req, res, _next) => {
    // body-parser rejections (malformed JSON, oversized body) carry their own
    // `status`; without honouring it every one became a 500 with a stack trace,
    // reachable pre-auth by anyone who can POST a broken body.
    const status = err instanceof HttpError ? err.status : statusOf(err);
    if (status >= 500) {
      console.error(err);
    }
    res.status(status).json({ error: errorMessage(err) });
  }) satisfies express.ErrorRequestHandler);

  return app;
}
```

Splitting `buildApp` from `listen` is what lets the tests drive the whole app
with supertest and no port.

## HTTP entry point

```typescript
async function main(): Promise<void> {
  const config = loadConfig();
  const client = new ActualClient(config);

  // Open the budget before listening so misconfiguration (bad URL, wrong
  // password, unknown sync id) is visible at startup rather than at the first
  // tool call. A failure is only a warning: the client retries on the next
  // call, so a briefly-unreachable upstream must not crashloop the container
  // (`restart: unless-stopped`) or take the endpoint down with it.
  await client.init().catch((err: unknown) => {
    console.warn(`Could not open the budget at startup (will retry on first tool call): ${errorChainMessage(err)}`);
  });

  const app = buildApp({ repos: createRepos(client), config });
  const httpServer = app.listen(config.port, () => { /* startup banner */ });

  httpServer.on('error', (err: NodeJS.ErrnoException) => {
    if (err.code === 'EADDRINUSE') {
      console.error(`Port ${config.port} is already in use. Set PORT to a free port and restart.`);
      process.exit(1);
    }
    throw err;
  });

  let shuttingDown = false;
  const shutdown = (signal: NodeJS.Signals) => {
    if (shuttingDown) return;
    shuttingDown = true;
    console.log(`Received ${signal}; shutting down`);
    httpServer.close();
    client.close().finally(() => process.exit(0));
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main().catch((err: unknown) => {
  console.error(`Fatal startup error: ${errorChainMessage(err)}`);
  process.exit(1);
});
```

The **startup banner earns its keep**: it prints the upstream target, whether
auth is on, and whether writes are on. And it warns on the one combination
nobody intends:

```typescript
// Writable *and* unauthenticated means anyone who can reach the port can
// modify the data. Each half is a reasonable choice on its own, so the
// combination is what deserves a warning.
if (config.enableWrites && authOff) {
  console.warn('WARNING: writes are enabled and SECURE_LOCAL_NET has disabled auth — …');
}
```

The `shuttingDown` latch matters: SIGTERM followed by SIGINT (Ctrl-C in a
compose stack) otherwise runs teardown twice.

## Commands

```bash
npm run dev          # HTTP on :3000, watch, reads .env
npm run dev:stdio    # stdio transport, reads .env
npm run check        # biome check + tsc --noEmit
npm test             # vitest run
npm run build        # tsc → dist/
npm run start        # node dist/index.js
npm run build:docker
docker compose up    # ./data mounted at /data
```

Node 22+, `.ts` run directly in dev via `--experimental-strip-types`; `tsc` with
`rewriteRelativeImportExtensions` for the `dist/` build.

## SPECS.md and TODO_IDEAS.md

`SPECS.md` holds the locked design decisions, the config and API contracts, and
the itemized work list. **Read it first.**

`TODO_IDEAS.md` holds ideas that were considered and deliberately *not* built,
each with the reasoning that deferred it. Record a decision against building
something there rather than dropping it — and **check it before proposing a new
tool**, because the idea may already have been rejected for a reason that
still holds.
