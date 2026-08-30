# Config and auth

## Env-only config

**No config file to keep in sync.** One `loadConfig()` validates the whole
environment up front and reports **every** problem at once. Nothing else in the
codebase reads `process.env`.

```typescript
import { z } from 'zod';

const configSchema = z.object({
  /** Base URL of the upstream server, e.g. `https://budget.example.com`. */
  serverUrl: z.string().url(),
  password: z.string().min(1),
  /**
   * The budget's Sync ID — Settings → Advanced → "Sync ID". This is *not* the
   * budget's display name or its local `budget-<id>` folder name.
   */
  syncId: z.string().min(1),
  encryptionPassword: z.string().min(1).optional(),
  dataDir: z.string().min(1),
  port: z.number().int().positive(),
  /** Bearer token guarding /api and /mcp; null when auth is off. */
  authToken: z.string().min(1).nullable(),
  /**
   * Whether mutating tools are served at all. When false they are omitted from
   * `tools/list` entirely — an agent should never see a tool it cannot call.
   * There is no second "destructive" tier: deletes are ordinary writes.
   */
  enableWrites: z.boolean(),
  /**
   * Ceiling on a single upstream operation. Every call is serialized through
   * one queue, so an unbounded hang does not stall one request — it stalls the
   * whole server, permanently.
   */
  timeoutMs: z.number().int().min(1000),
});

export type Config = z.infer<typeof configSchema>;
```

Note that the field docblocks carry the operator-facing knowledge — where to
find the Sync ID, what the timeout actually protects. That is the only place it
will be read.

### Reading env values

```typescript
/** Read a value, treating an empty/whitespace-only env var as unset. */
function envValue(env: NodeJS.ProcessEnv, key: string): string | undefined {
  const raw = env[key];
  const trimmed = raw?.trim();
  return trimmed ? trimmed : undefined;
}

const TRUTHY = new Set(['1', 'true', 'yes', 'on']);
const FALSY = new Set(['0', 'false', 'no', 'off']);

/**
 * Parse a boolean env var, falling back to `fallback` when unset. An
 * unrecognized value returns `undefined` so schema validation rejects it — a
 * typo like `ACTUAL_ENABLE_WRITES=flase` must not silently mean "enabled".
 */
function envBoolean(env: NodeJS.ProcessEnv, key: string, fallback: boolean): boolean | undefined {
  const raw = envValue(env, key)?.toLowerCase();
  if (raw === undefined) return fallback;
  if (TRUTHY.has(raw)) return true;
  if (FALSY.has(raw)) return false;
  return undefined;   // ← schema rejects it
}
```

The typo case is the whole reason `envBoolean` exists. `Boolean(env.X)` would
turn `flase` into `true`, which is the worst possible answer for a write gate.

### Loading

```typescript
/**
 * Build the config from the environment. Throws with every missing/invalid
 * variable listed at once — a half-configured server can only fail later at the
 * first tool call, where the error is far harder to read.
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = configSchema.safeParse({
    serverUrl: envValue(env, 'ACTUAL_SERVER_URL'),
    password: envValue(env, 'ACTUAL_PASSWORD'),
    dataDir: path.resolve(envValue(env, 'DATA_DIR') ?? './data'),
    port: Number(envValue(env, 'PORT') ?? 3000),
    authToken: envValue(env, 'MCP_ACTUAL_TOKEN') ?? null,
    // Default on: the server is most useful when an agent can act, and the
    // gate exists to be turned *off* deliberately for read-only deployments.
    enableWrites: envBoolean(env, 'ACTUAL_ENABLE_WRITES', true),
    timeoutMs: Number(envValue(env, 'ACTUAL_TIMEOUT_MS') ?? 120_000),
  });
  if (!parsed.success) {
    const issues = parsed.error.issues.map(
      (i) => `  ${ENV_KEYS[String(i.path[0])] ?? String(i.path[0])}: ${i.message}`,
    );
    throw new Error(`Invalid configuration:\n${issues.join('\n')}`);
  }
  assertAuthConfigured(parsed.data, env);
  return parsed.data;
}

/** Config field → the env var that sets it, so validation errors name what the operator actually edits. */
const ENV_KEYS: Record<string, string> = {
  serverUrl: 'ACTUAL_SERVER_URL',
  password: 'ACTUAL_PASSWORD',
  dataDir: 'DATA_DIR',
  port: 'PORT',
  authToken: 'MCP_ACTUAL_TOKEN',
  enableWrites: 'ACTUAL_ENABLE_WRITES',
  timeoutMs: 'ACTUAL_TIMEOUT_MS',
};
```

`safeParse` + collect, never `parse`: the operator gets one list, not one
problem per restart. And the `ENV_KEYS` map is what makes the message name
`ACTUAL_SERVER_URL` rather than `serverUrl`, which is the string they can act
on.

`loadConfig(env = process.env)` taking the environment as a parameter is what
makes `config.test.ts` possible without mutating the process.

### Hand-editable state

Where a server does need it, use flat JSON under `DATA_DIR/config/`, watched
(chokidar) plus an explicit `POST /api/reload`. Writes are **atomic**: temp
file in the same directory, `chmod 0600`, then `rename`. Parse leniently
(`.passthrough()`) so hand-added keys survive a round-trip.

## Auth

A single bearer token from env, guarding `/mcp` and `/api/*`.

```typescript
import { createHash, timingSafeEqual } from 'node:crypto';

/**
 * `SECURE_LOCAL_NET=true` disables bearer auth entirely for both /api and /mcp
 * — an escape hatch for running on a trusted local network without minting or
 * passing tokens.
 */
export function authDisabledByEnv(env: NodeJS.ProcessEnv = process.env): boolean {
  const value = env.SECURE_LOCAL_NET;
  return value !== undefined && TRUTHY_ENV.has(value.trim().toLowerCase());
}

/** Constant-time comparison that does not leak token length (compares sha256 digests). */
export function tokensEqual(a: string, b: string): boolean {
  const digestA = createHash('sha256').update(a).digest();
  const digestB = createHash('sha256').update(b).digest();
  return timingSafeEqual(digestA, digestB);
}

/**
 * Bearer-token middleware for /api and /mcp. Skipped entirely when auth is
 * disabled; otherwise rejects with a 401 JSON envelope.
 */
export function createAuthMiddleware(getAuth: () => AuthConfig): RequestHandler {
  return (req, res, next) => {
    const { enabled, token } = getAuth();
    if (!enabled) return next();
    if (!token) {
      res.status(401).json({ error: 'Auth is enabled but no token is configured' });
      return;
    }
    const header = req.headers.authorization;
    const provided = header?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!provided || !tokensEqual(provided, token)) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }
    next();
  };
}
```

- **Hash before `timingSafeEqual`.** It throws on mismatched lengths, and
  catching that leaks the token's length. Comparing fixed-width digests does
  neither.
- **`getAuth` is a function**, not a value, so a token rotated at runtime takes
  effect without rebuilding the app.
- `/api/status` stays open: it is a liveness probe and reveals nothing.

## Refusing to start unauthenticated

```typescript
/**
 * Refuse to start unauthenticated unless that was asked for explicitly.
 *
 * Serving a budget with no token exposes someone's entire financial history to
 * anyone who can reach the port, and with writes on (the default) it lets them
 * change it. Leaving `MCP_ACTUAL_TOKEN` unset is indistinguishable from
 * misspelling it, so the previous behaviour — start anyway, print a warning —
 * turned one typo into a silent, open, writable server. Running without a token
 * stays possible; it just has to be stated, via `SECURE_LOCAL_NET=true`.
 */
function assertAuthConfigured(config: Config, env: NodeJS.ProcessEnv): void {
  if (config.authToken || authDisabledByEnv(env)) return;
  const writable = config.enableWrites
    ? ' — with writes enabled, meaning they could modify your budget'
    : '';
  throw new Error(
    'Invalid configuration:\n' +
      `  MCP_ACTUAL_TOKEN: not set, so /mcp would be open to anyone who can reach this port${writable}.\n` +
      '  Set MCP_ACTUAL_TOKEN to a secret of your choosing, or set SECURE_LOCAL_NET=true to confirm you ' +
      'intend an unauthenticated server on a trusted network.',
  );
}
```

This is the pattern to copy for any dangerous default: **an omission and a typo
must not be the same thing**. Make the unsafe configuration reachable, but only
by naming it.
