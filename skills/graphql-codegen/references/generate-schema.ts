/**
 * server/generate_schema.ts — step 1 of the pipeline.
 *
 * Generates src/__generated__/schema.graphql from the Drizzle schema.
 *
 * NO DATABASE IS CONTACTED. buildSchema only reads `db._.relations` — a static
 * JS object set at drizzle() construction time — and postgres.js connects
 * lazily on first query, so a placeholder DSN is enough. That is what lets
 * codegen run in a Docker build stage and in CI with no Postgres, and it is
 * why this script constructs its own `db` rather than importing the runtime
 * singleton (which throws at import without DATABASE_URL).
 *
 * Run: `node --experimental-strip-types server/generate_schema.ts`
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { relations } from '@myapp/db/relations';
import { buildSchema } from '@vantreeseba/drizzle-graphql';
import { drizzle } from 'drizzle-orm/postgres-js';
import { printSchema } from 'graphql';
import postgres from 'postgres';
import { buildSchemaConfig } from './src/schema/build-config.ts';
import { applyCustomResolvers } from './src/schema/resolvers/index.ts';

// Never connected: no query is issued, so the DSN is never resolved.
const client = postgres('postgresql://unused/unused');

const db = drizzle({ client, relations });

const { schema: drizzleSchema } = buildSchema(db, buildSchemaConfig);

// Apply the SAME transformation the server applies, so the printed SDL is
// exactly the surface the server serves — not a superset of it.
const fullSchema = applyCustomResolvers(drizzleSchema);

const __dirname = dirname(fileURLToPath(import.meta.url));
const generatedDir = join(__dirname, 'src/__generated__');
mkdirSync(generatedDir, { recursive: true });
writeFileSync(join(generatedDir, 'schema.graphql'), printSchema(fullSchema));
console.log('Generated src/__generated__/schema.graphql');

/**
 * BOOTSTRAP CYCLE
 *
 * Where the schema is assembled in layers, generate from a BASE builder that
 * does not import the files codegen is about to write:
 *
 *   import { buildBaseSchema } from './src/schema/base.ts';
 *   writeFileSync(out, printSchema(buildBaseSchema(db)));
 *
 * `buildBaseSchema` applies the SDL extensions and custom resolvers but binds
 * no permissions middleware, because the full builder imports
 * `__generated__/permissions.ts` — which does not exist yet on a clean
 * checkout. The printed SDL is identical either way: permissions wrap
 * resolvers, they do not change the type surface.
 */
