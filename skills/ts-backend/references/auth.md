# Authentication

One function resolves a raw token into a `Context`, and it is the only place
credentials are interpreted. Both HTTP and WebSocket paths call it.

## The chain

Tried in order; the first match wins, and no match yields an unauthenticated
context (not an error — `requireUser` raises that at the resolver).

| # | Credential | Check |
| --- | --- | --- |
| 1 | Session JWT | `jwtVerify`, take `payload.sub` as the user id |
| 2 | API key (`acal_…`) | SHA-256 the token, look it up by hash, reject revoked/expired |
| 3 | `BYPASS_AUTH_UUID` | exact match against the env var, any environment |
| 4 | Bare UUID | dev only (`NODE_ENV !== 'production'`) |

```typescript
async function buildContext(rawToken?: string, appBaseUrl?: string): Promise<Context> {
  const loaders = createLoaders(db);
  const baseUrl = appBaseUrl ?? process.env.APP_URL ?? 'http://localhost:3000';
  if (!rawToken) {
    return { db, loaders, appBaseUrl: baseUrl };
  }

  const payload = await verifyToken(rawToken);
  if (payload?.sub) {
    return { db, userId: payload.sub, loaders, appBaseUrl: baseUrl };
  }

  if (isApiKey(rawToken)) {
    const hash = hashApiKey(rawToken);
    const now = new Date();
    const key = await db.query.apiKeys.findFirst({
      where: { keyHash: hash, revokedAt: { isNull: true } },
    });
    if (key && (key.expiresAt == null || key.expiresAt > now)) {
      // fire-and-forget; a failed lastUsedAt write must not fail the request
      db.update(apiKeys)
        .set({ lastUsedAt: now })
        .where(eq(apiKeys.id, key.id))
        .catch((err: unknown) => log.error('Failed to update API key lastUsedAt:', err));
      return {
        db,
        userId: key.userId,
        apiKey: { id: key.id, scopes: key.scopes },
        loaders,
        appBaseUrl: baseUrl,
      };
    }
  }

  const bypassUuid = process.env.BYPASS_AUTH_UUID;
  if (bypassUuid && rawToken === bypassUuid) {
    return { db, userId: rawToken, loaders, appBaseUrl: baseUrl };
  }

  if (process.env.NODE_ENV !== 'production' && /^[0-9a-f-]{36}$/i.test(rawToken)) {
    return { db, userId: rawToken, loaders, appBaseUrl: baseUrl };
  }

  return { db, loaders, appBaseUrl: baseUrl };
}
```

`BYPASS_AUTH_UUID` logs a loud warning at boot when set:

```typescript
if (process.env.BYPASS_AUTH_UUID) {
  log.warn('BYPASS_AUTH_UUID is set — magic-link auth bypassed for user', process.env.BYPASS_AUTH_UUID);
}
```

## Normalizing the header

```typescript
/**
 * Normalize an Authorization header / WS connectionParams value to a bare
 * token. Accepts "Bearer <token>" (any case) or a bare token, so JWTs and API
 * keys authenticate identically over HTTP and WebSocket.
 */
function extractToken(authorization?: string | null): string | undefined {
  if (!authorization) return undefined;
  const trimmed = authorization.trim();
  if (!trimmed) return undefined;
  const bearer = /^Bearer\s+(.+)$/i.exec(trimmed);
  return bearer?.[1] ? bearer[1].trim() : trimmed;
}
```

**Both transports must use this.** The WS path once passed the raw
`"Bearer <token>"` string straight through, which made every API-key and JWT
subscription fail auth — clients then reconnected in a tight loop, burning idle
CPU. It is the kind of bug that shows up as a performance complaint, not an auth
error.

## Magic links (JWT)

Two token lifetimes, one secret, `jose`:

```typescript
import { SignJWT, jwtVerify } from 'jose';

const JWT_SECRET = new TextEncoder().encode(
  process.env.JWT_SECRET ?? 'dev-secret-change-in-production',
);

/** Issue a magic link token (short-lived, 15 minutes). */
export async function signMagicToken(email: string): Promise<string> {
  return new SignJWT({ email })
    .setProtectedHeader({ alg: 'HS256' })
    .setExpirationTime('15m')
    .setIssuedAt()
    .sign(JWT_SECRET);
}

/** Issue a session token (long-lived, 30 days). */
export async function signSessionToken(userId: string, email: string): Promise<string> {
  return new SignJWT({ sub: userId, email })
    .setProtectedHeader({ alg: 'HS256' })
    .setExpirationTime('30d')
    .setIssuedAt()
    .sign(JWT_SECRET);
}

/** Verify any token and return payload. */
export async function verifyToken(token: string): Promise<{ sub?: string; email?: string } | null> {
  try {
    const { payload } = await jwtVerify(token, JWT_SECRET);
    return payload as { sub?: string; email?: string };
  } catch {
    return null;
  }
}
```

`verifyToken` returns `null` rather than throwing — the auth chain needs to fall
through to the next method, not abort.

Only the session token carries `sub`. The magic token carries `email` only, so it
cannot be used as a session token even though the same verifier accepts it.

The two mutations that use these are the only entries in `PUBLIC_MUTATIONS`:
`requestMagicLink`, `verifyMagicLink`.

## API keys

```typescript
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

const PREFIX = 'acal_';

/** Generate a new API key token, its SHA-256 hash, and its display prefix. */
export function generateApiKey(): { token: string; hash: string; prefix: string } {
  const raw = randomBytes(32).toString('base64url');
  const token = `${PREFIX}${raw}`;
  const hash = hashApiKey(token);
  const prefix = raw.slice(0, 8);
  return { token, hash, prefix };
}

/** Returns true if the raw token looks like an API key. */
export function isApiKey(raw: string): boolean {
  return raw.startsWith(PREFIX);
}

/** SHA-256 hex hash of a raw API key token. */
export function hashApiKey(raw: string): string {
  return createHash('sha256').update(raw).digest('hex');
}

/** Timing-safe equality check. Returns false if lengths differ. */
export function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a), Buffer.from(b));
}
```

Rules:

- **A recognizable prefix** (`acal_`) so the chain can route without a DB hit,
  and so a leaked key is greppable in logs and scanners.
- **32 random bytes, base64url.** No custom alphabet, no shortening.
- **Only the hash is stored.** The plaintext token is returned exactly once, from
  the create mutation, and never again. The `apiKeys.keyHash` column is excluded
  from the GraphQL surface entirely — see the `exclude.columns` note in the
  schema-pipeline reference.
- **Constant-time comparison** wherever a secret is compared by value.
- **Revocation is a timestamp, not a delete.** `revokedAt` is filtered in
  `TABLE_SCOPE` for `apiKeys`, so a revoked key is invisible to the API as well
  as unusable.

## Wiring

```typescript
// HTTP
app.use('/graphql', express.json(), expressMiddleware(server, {
  context: async ({ req }) =>
    buildContext(extractToken(req.headers.authorization), req.headers.origin),
}));

// WebSocket
useServer(
  {
    schema,
    context: (ctx) =>
      buildContext(extractToken(ctx.connectionParams?.authorization as string | undefined)),
  },
  wsServer,
);
```

Same `buildContext`, same `extractToken`, both transports. Anything that
diverges here is a bug waiting to happen.
