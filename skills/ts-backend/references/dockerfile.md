# Dockerfile

Two stages: build the client bundle, then ship a server image that only carries
the server and the built bundle.

```dockerfile
# ── Stage 1: bundle the web client ───────────────────────────────────────────
FROM node:24-alpine AS client-builder

WORKDIR /app

# Copy workspace manifests so npm install can resolve all workspaces
COPY package*.json ./
COPY client/package*.json ./client/
COPY db/package*.json ./db/
COPY server/package*.json ./server/

RUN npm install --legacy-peer-deps

# Copy sources + codegen configs. __generated__/ types are gitignored, so they
# are NOT in the build context — they must be generated here. Codegen builds the
# GraphQL schema from the db + server Drizzle definitions, so all three packages
# and the root codegen configs are required.
COPY db ./db
COPY server ./server
COPY client ./client
COPY codegen.ts codegen.server.ts ./

# Generate schema.graphql + typed client operations, then export the web bundle.
RUN npm run codegen
RUN cd client && npx expo export --platform web

# ── Stage 2: production server ───────────────────────────────────────────────
FROM node:24-alpine

WORKDIR /app

COPY package*.json ./
COPY server/package*.json ./server/
COPY db/package*.json ./db/

RUN npm install --omit=dev

COPY server ./server
COPY db ./db

# Pull the built web bundle from Stage 1
COPY --from=client-builder /app/client/dist ./client/dist

EXPOSE 3001

ENV NODE_ENV=production
ENV PORT=3001
# DATABASE_URL must be supplied at run time — Postgres is the only backend, and
# the server exits immediately without it. There is deliberately no embedded
# fallback: the PGLite one busy-waited on a WASM event loop and burned CPU at
# idle, so a deploy that lost its DATABASE_URL degraded silently instead of
# failing. See docker-compose.yml.

CMD ["node", "--experimental-strip-types", "server/src/index.ts"]
```

## What each rule is doing

**Manifests before sources.** `package*.json` for every workspace is copied
first so the `npm install` layer caches independently of source changes. A
one-line edit to a resolver should not reinstall node_modules.

**Codegen runs *inside* the image.** `__generated__/` is gitignored, so it is
not in the build context. That is deliberate: it forces the image to be built
from the same sources the schema is derived from, so a stale committed artifact
can never ship. It also means **`db`, `server`, and both codegen configs are
required in the client stage** even though only the client is being bundled —
the schema is derived from the Drizzle tables.

**Stage 2 never installs the client.** It copies `client/dist` across from stage
1 and installs with `--omit=dev`. The runtime image has no build toolchain, no
Expo, no codegen.

**No build step for the server.** `node --experimental-strip-types` runs the
`.ts` sources directly, which is why `server` and `db` are copied as source and
why the `db` package's `exports` point at `.ts`.

**No `DATABASE_URL` default, and no fallback backend.** The comment is part of
the file for a reason: a silent fallback turns a broken deploy into a slow one.
Supply it at run time from compose or the platform's secret store.

**`--legacy-peer-deps` in stage 1** only because the Expo/React Native peer graph
demands it. A server-only image does not need it.

## Compose

```yaml
services:
  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: autocal
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U postgres']
      interval: 5s
      retries: 10

  app:
    build: .
    depends_on:
      db:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://postgres:postgres@db:5432/autocal
      JWT_SECRET: ${JWT_SECRET:?JWT_SECRET is required}
      APP_URL: ${APP_URL:-http://localhost:3001}
    ports:
      - '3001:3001'

volumes:
  pgdata:
```

`condition: service_healthy` matters: `db/src/index.ts` runs migrations at import
time, so the server process dies immediately if Postgres is not yet accepting
connections. `depends_on` alone does not wait for readiness.

`${JWT_SECRET:?...}` fails the compose invocation rather than starting with the
dev default. Anything that must not fall back should use the `:?` form.
