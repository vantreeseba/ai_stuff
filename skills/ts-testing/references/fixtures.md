# Fixtures, mocks, and isolation

## Fixtures come from the schema, not from hand-written objects

Build mocks **once at module load** from the printed `schema.graphql`, with a
fixed seed, and wrap them in per-entity helpers that take overrides.

`server/test/test-mocks.ts`:

```typescript
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { ActivityType, Habit, TimeBlock, Todo, User } from '@myapp/db';
import { buildMocks } from '@vantreeseba/graphql-mocks';

const __dirname = dirname(fileURLToPath(import.meta.url));
const schema = readFileSync(resolve(__dirname, '../src/__generated__/schema.graphql'), 'utf8');

// Build once at module load; seed=42 keeps output deterministic across runs.
// DateTime returns Date objects to match the DB layer's timestamp types.
// nullChance=1 makes all nullable relation fields null by default.
const base = buildMocks(schema, {
  seed: 42,
  scalars: { DateTime: (f) => f.date.recent() },
  nullChance: 1,
});

function first<T>(typeName: string): T {
  const item = (base[typeName] as unknown[])?.[0];
  if (item === undefined) throw new Error(`[test-mocks] no mock for ${typeName}`);
  return item as T;
}

export function makeUser(overrides: Partial<User> = {}): User {
  return {
    ...first<User>('User'),
    id: 'user-1',
    email: 'test@example.com',
    timezone: 'UTC',
    ...overrides,
  };
}

export function makeTodo(overrides: Partial<Todo> = {}): Todo {
  return {
    ...first<Todo>('Todo'),
    listId: 'list-1',
    title: 'Write tests',
    estimatedLength: 60,
    priority: 1,
    manuallyScheduled: false,
    ...overrides,
  };
}
```

Why this and not object literals: **a fixture derived from the schema cannot
drift from it.** Add a required column and every hand-written literal in the
suite is silently missing it; the generated one is not.

Each of the three options is load-bearing:

- **`seed: 42`** — deterministic output, so fixtures are reviewable in a diff
  and a failure reproduces.
- **`scalars: { DateTime: … }`** — the default mock for a custom scalar is a
  string; the DB layer hands back `Date` objects, and the mismatch surfaces as a
  confusing assertion failure far from the cause.
- **`nullChance: 1`** — every nullable relation field is null by default, so a
  test that cares about a relation has to say so. Without it, mocks arrive with
  arbitrary populated relations that quietly satisfy assertions.

The stable fields inside each `make*` (`id: 'user-1'`, a readable email) are the
ones tests *reference*. Everything else is arbitrary-but-stable, which is the
point.

**Set only the fields the test is about** in `overrides`.

## Database tests use their own PGLite

**Never import the `db` singleton in a test.** Each test file builds its own
in-memory instance, migrated from the real migration folder. See
[`test-helpers.ts`](test-helpers.ts) for the full harness.

Back it up by blanking the env in the runner config, so an accidental import
fails loudly instead of connecting to — and migrating — a real database:

```typescript
test: {
  env: { DATABASE_URL: '' },   // @scope/db throws "DATABASE_URL is required"
}
```

That is a backstop, not the mechanism. The mechanism is that tests construct
their own database.

Fresh instances per file, no shared state between files.

## Env isolation

```typescript
afterEach(() => {
  vi.unstubAllEnvs();
});

it('is disabled in production by default', () => {
  vi.stubEnv('NODE_ENV', 'production');
  vi.stubEnv('EXPOSE_MAGIC_LINK', undefined);
  expect(magicLinkExposed()).toBe(false);
});
```

`vi.unstubAllEnvs()` in `afterEach`, always — a stubbed env that leaks makes a
later test fail in a way that depends on file ordering.

**Loop the spellings rather than picking one.** A boolean env parser is exactly
the kind of code where one spelling works and the rest silently do not:

```typescript
it.each(['1', 'true', 'TRUE', 'yes', ' Yes '])('accepts %s as true', (value) => {
  vi.stubEnv('FEATURE_X', value);
  expect(featureX()).toBe(true);
});

it.each(['', '0', 'false', 'no', 'off'])('accepts %s as false', (value) => {
  vi.stubEnv('FEATURE_X', value);
  expect(featureX()).toBe(false);
});
```

Better still, write `loadConfig(env = process.env)` so tests pass a plain object
and never touch the process at all.

## Module mocks

`vi.hoisted` for mocks whose factory has to close over something:

```typescript
const { mockUpdate } = vi.hoisted(() => {
  const mockUpdate = vi.fn().mockReturnValue({
    set: vi.fn().mockReturnValue({ where: vi.fn().mockResolvedValue(undefined) }),
  });
  return { mockUpdate };
});

vi.mock('@myapp/db', () => ({
  db: { query: { users: { findFirst: vi.fn() } }, update: mockUpdate },
}));
```

`vi.mock` is hoisted above the imports, so a plain `const` declared in the file
body is not yet initialized when the factory runs. `vi.hoisted` is the only way
to share a value with it.

Prefer a real PGLite over a mocked `db`. Mock the module only where the test is
about the call itself (that a write happened, with these arguments) rather than
its effect.

## Time

```typescript
vi.useFakeTimers();
vi.setSystemTime(new Date('2026-01-01T00:00:00Z'));
// …
vi.useRealTimers();
```

Restore in the same test (or an `afterEach`). Fake timers that leak turn an
unrelated later test into a hang.

## What is worth testing

**Pin the invariants that live in a bumpable dependency.** Tenant isolation
rides on the generated resolver's filter composition and its AND-ed foreign-key
predicates, both inside `@vantreeseba/drizzle-graphql`. A test that seeds two
users and asserts one cannot read the other's rows turns a dependency upgrade
that changes that behaviour into a red suite instead of a production incident.

**Negative-test the guard itself.** After changing anything in the scoping
layer, break one `TABLE_SCOPE` entry on purpose and confirm the suite fails. A
test that cannot fail is not protecting anything.

**Keep one runnable worked example** in a library's suite (`example.test.ts`).
It doubles as the reference documentation and, unlike a README snippet, cannot
rot.

## Coverage

Coverage is a **gate, not a report** — thresholds fail the build.

```typescript
coverage: {
  provider: 'v8',
  thresholds: { statements: 95, branches: 90, functions: 95, lines: 95 },
}
```

Libraries sit at 90–95; applications lower. `__generated__/` and `test/` are
always excluded — generated code is not hand-written, and counting it makes the
number meaningless. A type-only module (erased at runtime, exercised by the
type-checked tests) is excluded too, with a comment saying why.
