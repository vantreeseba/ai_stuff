# The schema pipeline

The GraphQL schema is not written by hand. It is derived from the Drizzle tables,
narrowed, extended, and then finalized — in a fixed order, by one function.

```
Drizzle tables (db/src/schema.ts)
        │  buildSchema(tables, buildSchemaConfig)
        ▼
generated schema: types, filters, order-bys, relation fields, root queries
        │  scopeRootFields()      rename to my*, wrap with auth, delete the rest
        ▼
        │  extendSchema(parse(extensionSDL))   hand-written queries/mutations
        ▼
        │  attach()               typed resolver maps onto Query/Mutation/types
        ▼
        │  finalizeSchema()       assert my*-prefix, strip, prune
        ▼
runtime GraphQLSchema  ──►  printed to schema.graphql  ──►  codegen
```

## `build-config.ts`

Shared by every `buildSchema` call — the runtime schema, the schema-generation
script, and tests — so the generated SDL is byte-identical everywhere. Never
build with an inline config.

```typescript
import * as tables from '@auto-cal/db/schema';
import type { BuildSchemaConfig } from '@vantreeseba/drizzle-graphql';
import { is } from 'drizzle-orm';
import { PgTable } from 'drizzle-orm/pg-core';
import { TABLE_SCOPE, assertEveryTableScoped } from './scope.ts';

// Fails the boot if a Drizzle table has no row scope, so adding one cannot
// quietly produce a table the API serves unscoped.
assertEveryTableScoped(
  Object.entries(tables)
    .filter(([, value]) => is(value, PgTable))
    .map(([key]) => key),
);

export const buildSchemaConfig: BuildSchemaConfig = {
  typeNameMapper: (tableName) => ({
    singular: tableName.replace(/s$/, ''),
    plural: tableName,
  }),

  features: {
    aggregates: false,
    relationAggregates: false,
    insert: false,
    update: false,
    updateMany: false,
    delete: false,
  },

  scope: TABLE_SCOPE,

  exclude: {
    columns: { apiKeys: ['keyHash'] },
  },

  defaults: {
    todoLists: { orderBy: { name: 'asc' } },
    todos: {
      orderBy: {
        priority: { direction: 'desc', priority: 1 },
        createdAt: { direction: 'desc', priority: 0 },
      },
    },
    apiKeys: { orderBy: { createdAt: 'desc' } },
    projectNotes: {
      orderBy: {
        position: { direction: 'asc', priority: 1 },
        createdAt: { direction: 'asc', priority: 0 },
      },
    },
  },
};
```

### `typeNameMapper`

Every table key is a regular plural (`todos`, `apiKeys`), so stripping the
trailing `s` produces type `Todo` and queries `todos`/`todo`. An irregular plural
would need a special case here.

### `features` — everything off

**Aggregates** would be stripped by `finalizeSchema` anyway at the root, and
relation aggregates would expose live resolvers nothing uses.

**Every generated CRUD mutation is disabled.** All writes go through hand-written,
user-scoped `my*` resolvers, so the generated ones were only ever emitted to be
stripped again — 50 dead root fields. With all four off, drizzle-graphql omits
the `Mutation` type entirely, which is why `resolvers/index.ts` must **declare**
`type Mutation` rather than `extend` it, and wire it as the root operation.

Generated *queries* cannot be disabled this way — there is no such flag — so the
unscoped ones are removed after the fact by `scopeRootFields` / `finalizeSchema`.

### `exclude.columns` — the oracle problem

Excluding a column keeps it out of every surface derived from the column list at
once: the `ApiKey` object type, `ApiKeyFilters`, `ApiKeyOrderBy`, and
`ApiKeyDistinctColumn`. The alternative — deleting the output field afterwards —
leaves the input types behind, and **a filter or an ordering on a secret is an
oracle even when the field itself cannot be selected**:
`where: { keyHash: { eq: "..." } }` confirms a guess, and `orderBy` binary
searches it.

All four surfaces are reachable through the live `User.apiKeys` relation, so
there is no path where only stripping the output field would be enough.

The server still reads and writes the column through Drizzle directly. This is a
GraphQL-surface rule only.

Excluding a `NOT NULL` column with no default prints a build-time warning that
generated inserts for the table can never succeed. It does not apply when
`features.insert` is off, and there is no flag to silence it.

### `defaults` — declared ordering

Presentation order lives on the server, declared once, instead of in every
caller. A table's default applies to its own queries **and** to every to-many
relation field targeting it, so a table presents the same way wherever it is
reached from — which is the part a root-field wrapper cannot do.

Only a *missing* `orderBy` is replaced; a caller-supplied one wins outright.

**`priority` is a tiebreak rank, and the HIGHEST number sorts first** — not the
position in the object. This is the easiest thing in the file to get backwards:
`{ priority: desc(0), createdAt: desc(1) }` sorts newest-first with the priority
*column* as a tiebreak that only fires on identical timestamps, i.e. never.

## `extensionSDL`

A single template literal in `resolvers/index.ts` holding everything the
generator cannot produce: computed queries, all mutations, subscriptions, custom
object types, and zod-mirroring input types.

Three things in it are load-bearing:

**Root operations must be wired explicitly.**

```graphql
# drizzle-graphql's buildSchema sets the query root operation explicitly, and a
# conventionally-named "type Subscription" / "type Mutation" is NOT
# auto-promoted to a root operation by extendSchema. Both are wired here:
# Subscription because the library never generates one, Mutation because
# build-config turns every generated mutation off, which omits the type.
extend schema {
  mutation: Mutation
  subscription: Subscription
}
```

Without this, graphql-js rejects the operation outright: *"Schema is not
configured to execute mutation/subscription operation"*.

**`Mutation` is declared, `Query` is extended.**

```graphql
type Mutation {        # declared — build-config left no Mutation type to extend
  myCreateTodo(input: CreateTodoArgs!): Todo!
  ...
}

extend type Query {    # extended — the generated queries are already there
  myStats(startDate: String, endDate: String): StatsOverview!
}
```

Only queries that compute something beyond a filter are declared. `myTodos`,
`myProjects` and friends are generated fields renamed by `scopeRootFields`; do
not redeclare them.

**Extend generated types for derived fields only.** Relation fields are already
generated with working resolvers. `extend type Todo { activityType: ActivityType }`
is for hops that aren't a plain Drizzle relation.

## `applyCustomResolvers`

The whole assembly, in the order that matters:

```typescript
export function applyCustomResolvers(schema: GraphQLSchema): GraphQLSchema {
  // Scope first: this renames the generated queries to their `my*` form and
  // wraps each resolver with the auth guard, so the extension below adds only
  // the queries that do real work beyond scoping.
  const extended = extendSchema(scopeRootFields(schema), parse(extensionSDL));

  const queryType = extended.getType('Query') as GraphQLObjectType;
  const mutationType = extended.getType('Mutation') as GraphQLObjectType;
  const subscriptionType = extended.getType('Subscription') as GraphQLObjectType;

  attach(queryType, { ...habitQueries, ...statsQueries, ...scheduleQueries });
  attach(mutationType, { ...todoMutations, ...projectMutations, ...authMutations });
  attach(subscriptionType, subscriptionResolvers);

  // drizzle-graphql attaches resolvers to every Drizzle-relation field (eager
  // when the parent query pre-fetched it, request-batched lazy loads
  // otherwise), so plain DB rows returned by custom resolvers resolve their
  // relation fields without help. The explicit field resolvers below cover only
  // what that machinery can't: custom SDL fields and derived hops.
  attach(extended.getType('Todo') as GraphQLObjectType, todoFields);
  attach(extended.getType('Project') as GraphQLObjectType, projectFields);

  return finalizeSchema(extended);
}
```

**Order is not negotiable.** Scope → extend → attach → finalize. Scoping before
extending means the extension only adds real work. Finalizing last means
`pruneSchema` runs after the extension has had its chance to reference the
generated input types — prune earlier and the SDL loses types the extension
needs.

`attach` walks a typed resolver map onto a type in place:

```typescript
function attach(type: GraphQLObjectType, resolvers: Record<string, unknown>): void {
  const fields = type.getFields();
  for (const [fieldName, resolver] of Object.entries(resolvers)) {
    const field = fields[fieldName];
    if (!field) {
      throw new Error(
        `${type.name}.${fieldName} has a resolver but is not in the schema — regenerate schema.graphql`,
      );
    }
    if (typeof resolver === 'function') {
      field.resolve = resolver as GraphQLFieldResolver<unknown, Context>;
    } else {
      const { subscribe, resolve } = resolver as {
        subscribe: GraphQLFieldResolver<unknown, Context>;
        resolve: GraphQLFieldResolver<unknown, Context>;
      };
      field.subscribe = subscribe;
      field.resolve = resolve;
    }
  }
}
```

A field-name typo is already a compile error (the maps are `Pick`s of the
generated resolver types), so the runtime check only catches what the types
cannot see: an SDL field that exists in `__generated__` but not in the schema
this was called with — i.e. a stale codegen run.
