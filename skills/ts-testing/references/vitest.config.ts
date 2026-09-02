/**
 * vitest.config.ts — the workspace/application variant.
 *
 * See the bottom of this file for the published-library variant, and for the
 * node:test alternative.
 */
import { resolve } from 'node:path';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: {
    // Ensure only one graphql instance is loaded across all packages.
    // Without this alias vitest's ESM module graph can end up with two copies
    // (e.g. drizzle-graphql + server code), causing instanceof checks to fail.
    alias: {
      graphql: resolve('./node_modules/graphql/index.js'),
    },
  },
  test: {
    globals: true,
    environment: 'node',
    include: [
      '{client,db,server}/test/**/*.test.ts',
      '{client,db,server}/src/**/*.test.ts',
    ],
    // Prevent .env's DATABASE_URL from leaking into tests. Any test that
    // accidentally imports @scope/db without mocking it throws immediately
    // ("DATABASE_URL is required") rather than connecting to — and migrating —
    // a real database. Tests build their own in-memory PGLite instead; see
    // server/test/schema/resolvers/test-helpers.ts.
    env: {
      DATABASE_URL: '',
    },
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov'],
      include: ['{client,db,server}/src/**/*.ts'],
      exclude: [
        '{client,db,server}/test/**',
        '{client,db,server}/src/**/*.test.ts',
        '{client,db,server}/src/__generated__/**',
      ],
    },
  },
});

/* ─────────────────────────────────────────────────────────────────────────────
 * PUBLISHED LIBRARY VARIANT
 *
 * graphql throws "another module or realm" when it is loaded more than once.
 * Under vitest's SSR loader the package can be pulled in as both CJS and ESM,
 * so dedupe it to a single instance and inline it (plus the graphql-tools /
 * middleware / envelop packages that also import it) through vitest's
 * transform: an externalized dependency gets the CJS build while the inlined
 * source gets the ESM one — two realms, one schema.
 *
 * export default defineConfig({
 *   resolve: {
 *     dedupe: ['graphql'],
 *   },
 *   test: {
 *     server: {
 *       deps: {
 *         inline: ['graphql', /@graphql-tools\//, /@envelop\//, 'graphql-middleware'],
 *       },
 *     },
 *     coverage: {
 *       provider: 'v8',
 *       include: ['src/**\/*.ts'],
 *       // schemaTypes.ts is type-only (erased at runtime); it is exercised by
 *       // the type-checked tests, not at runtime, so it has nothing to cover.
 *       exclude: ['src/schemaTypes.ts'],
 *       thresholds: {
 *         statements: 95,
 *         branches: 90,
 *         functions: 95,
 *         lines: 95,
 *       },
 *     },
 *   },
 * });
 *
 * A workspace aliases graphql to one path; a standalone library dedupes and
 * inlines. Do not do both — the alias makes the inlining a no-op and hides
 * which one is actually working.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * MINIMAL VARIANT (an MCP server, a small package with tests beside the source)
 *
 * export default defineConfig({
 *   test: {
 *     environment: 'node',
 *     include: ['src/**\/*.test.ts'],
 *   },
 * });
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * NODE:TEST ALTERNATIVE (zero test dependencies)
 *
 * "test": "node --experimental-strip-types --test \"src/__tests__/**\/*.test.ts\""
 *
 * with coverage as flags:
 *
 *   --experimental-test-coverage
 *   --test-coverage-lines=90
 *   --test-coverage-branches=80
 *   --test-coverage-functions=85
 *   --test-coverage-exclude="**\/*.test.ts"
 *
 * The describe/it shape is the same, so the choice is per-repo and not worth
 * relitigating inside one.
 */
