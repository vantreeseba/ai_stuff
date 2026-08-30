/**
 * server/test/schema/resolvers/test-helpers.ts
 *
 * Shared test helpers for resolver integration tests.
 * Each test file gets fresh PGLite instances — no shared state between files.
 *
 * NEVER import the `db` singleton in a test. `vitest.config.ts` blanks
 * DATABASE_URL so that an accidental import throws immediately rather than
 * connecting to — and migrating — a real database.
 */
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { relations } from '@myapp/db/relations';
import { activityTypes, habits, timeBlocks, todoLists, todos, users } from '@myapp/db/schema';
import { PGlite } from '@electric-sql/pglite';
import { buildSchema } from '@vantreeseba/drizzle-graphql';
import { drizzle } from 'drizzle-orm/pglite';
import { migrate } from 'drizzle-orm/pglite/migrator';
import { graphql } from 'graphql';
import { createLoaders } from '../../../src/context.ts';
import { buildSchemaConfig } from '../../../src/schema/build-config.ts';
import { applyCustomResolvers } from '../../../src/schema/resolvers/index.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Migrated from the REAL migration folder, not from a hand-maintained DDL
// script. A migration that fails here would have failed in production.
const migrationsFolder = resolve(__dirname, '../../../../db/drizzle');

export async function createTestDb() {
  const client = new PGlite('memory://');
  await client.waitReady;
  const db = drizzle({ client, relations });
  await migrate(db, { migrationsFolder });
  return db;
}

export type TestDb = Awaited<ReturnType<typeof createTestDb>>;

/**
 * Build the REAL schema the server serves, over the test database.
 *
 * A resolver called directly skips schema validation, argument coercion, the
 * scoping wrappers, and the generated relation resolvers — which is most of
 * what is worth testing.
 */
export function buildTestSchema(db: TestDb) {
  const { schema: drizzleSchema } = buildSchema(db, buildSchemaConfig);
  return applyCustomResolvers(drizzleSchema);
}

export type TestSchema = ReturnType<typeof buildTestSchema>;

/** Execute an operation as `userId`, through the full schema. */
export async function gql(
  testSchema: TestSchema,
  db: TestDb,
  userId: string,
  source: string,
  variableValues?: Record<string, unknown>,
) {
  return graphql({
    schema: testSchema,
    source,
    variableValues,
    contextValue: { db, userId, loaders: createLoaders(db) },
  });
}

// ─── Seed helpers ─────────────────────────────────────────────────────────────
//
// One per table, returning the inserted row. Each takes the ids it depends on
// explicitly rather than creating them, so a test's setup reads as the graph it
// actually needs. `overrides` typed as Partial<typeof table.$inferInsert> keeps
// them honest against the schema.

export async function seedUser(db: TestDb, email = 'test@example.com') {
  const [user] = await db.insert(users).values({ email }).returning();
  if (!user) throw new Error('Failed to create user');
  return user;
}

export async function seedActivityType(db: TestDb, userId: string, name = 'Work') {
  const [at] = await db
    .insert(activityTypes)
    .values({ userId, name, color: '#6366f1' })
    .returning();
  if (!at) throw new Error('Failed to create activity type');
  return at;
}

export async function seedTodoList(db: TestDb, userId: string, activityTypeId: string) {
  const [list] = await db
    .insert(todoLists)
    .values({ userId, name: 'Test List', activityTypeId })
    .returning();
  if (!list) throw new Error('Failed to create todo list');
  return list;
}

export async function seedTodo(
  db: TestDb,
  userId: string,
  listId: string,
  overrides: Partial<typeof todos.$inferInsert> = {},
) {
  const [todo] = await db
    .insert(todos)
    .values({
      userId,
      listId,
      title: 'Test todo',
      estimatedLength: 30,
      priority: 1,
      ...overrides,
    })
    .returning();
  if (!todo) throw new Error('Failed to create todo');
  return todo;
}

/**
 * PGLite is a devDependency of `server`, NOT a dependency of `db`.
 *
 * A production install cannot pull it in, and it can never become a runtime
 * backend by accident. If a test needs it, the test's package depends on it.
 */

/**
 * Usage:
 *
 *   let db: TestDb;
 *   let schema: TestSchema;
 *
 *   beforeEach(async () => {
 *     db = await createTestDb();
 *     schema = buildTestSchema(db);
 *   });
 *
 *   it('does not return another user\'s todos', async () => {
 *     const alice = await seedUser(db, 'alice@example.com');
 *     const bob = await seedUser(db, 'bob@example.com');
 *     const list = await seedTodoList(db, alice.id, (await seedActivityType(db, alice.id)).id);
 *     await seedTodo(db, alice.id, list.id, { title: 'private' });
 *
 *     const result = await gql(schema, db, bob.id, '{ myTodos { id title } }');
 *
 *     expect(result.errors).toBeUndefined();
 *     expect(result.data?.myTodos).toEqual([]);
 *   });
 */
