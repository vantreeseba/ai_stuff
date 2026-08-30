/**
 * codegen.server.ts — server-side codegen template.
 *
 * Run with `graphql-codegen-esm --config codegen.server.ts` (the `-esm` binary,
 * not the plain one: the ESM variant is what loads a `"type": "module"` config
 * and emits ESM output).
 *
 * Reads the printed SDL at ./server/src/__generated__/schema.graphql. No
 * database, no running server, no env vars.
 */
import type { CodegenConfig } from '@graphql-codegen/cli';

// @vantreeseba/graphql-casl-codegen and graphql-mocks-codegen validate that
// every config value they receive is a string, but graphql-codegen-esm injects
// a boolean `emitLegacyCommonJSImports`. Override it to undefined (both plugins
// skip undefined values) wherever they run. Drop this if you use neither.
const noEmitLegacy = { emitLegacyCommonJSImports: undefined } as const;

const config: CodegenConfig = {
  schema: './server/src/__generated__/schema.graphql',
  generates: {
    // Resolver + entity types. The source of truth the CASL and mock type-map
    // files below reference.
    './server/src/__generated__/resolvers.ts': {
      plugins: ['typescript', 'typescript-resolvers'],
      config: {
        // Map generated scalars to what the code actually holds. UUID columns
        // surface as a `UUID` scalar since drizzle-graphql v4.
        scalars: { UUID: 'string' },

        // An unspecified nullable input arrives as `undefined`, not `null`.
        inputMaybeValue: 'T | undefined',

        // Points at the hand-written context. Relative to the emitted file, and
        // with type stripping the path carries a `.ts` extension.
        contextType: '../context.ts#Context',

        // String unions rather than TS enums, matching the const-tuple enum
        // convention in db/src/models/enums.ts — and TS enums are nominal, so a
        // resolver could not return the plain 'created' string it publishes.
        enumsAsTypes: true,

        // Emit `import type` so nothing here survives into runtime JS.
        useTypeImports: true,

        // Resolvers return plain Drizzle rows and let the generated relation
        // resolvers fill in the rest, so the parent and return type of a
        // table-backed field is the DB ROW, not the fully-resolved GraphQL
        // object. Without these mappers every resolver would have to satisfy
        // `children: ActivityType[]` and friends.
        //
        // Alias every mapper to `*Row`: the bare name collides with the
        // same-named type the `typescript` plugin generates from the SDL.
        //
        // One entry per table-backed type. A missing entry is not an error —
        // it is a resolver that suddenly has to return a fully-resolved object.
        mappers: {
          Habit: '@myapp/db#Habit as HabitRow',
          HabitCompletion: '@myapp/db#HabitCompletion as HabitCompletionRow',
          Project: '@myapp/db#Project as ProjectRow',
          Todo: '@myapp/db#Todo as TodoRow',
          User: '@myapp/db#User as UserRow',
        },

        avoidOptionals: {
          // `null` for nullable fields instead of optionals — a resolver map
          // must be exhaustive to be worth checking.
          field: true,
          // Nullable input fields may still be omitted by callers.
          inputValue: false,
        },
      },
    },

    // OPTIONAL — CASL subject bindings (Subject / typed / ability /
    // AppSubjectMap) derived from the schema. References Resolvers and
    // ResolversTypes via a type-only import so the file stays runtime-loadable
    // under strip-types.
    './server/src/__generated__/permissions.ts': {
      plugins: [
        {
          add: {
            content:
              "import type { Resolvers, ResolversTypes } from './resolvers.ts';",
          },
        },
        { '@vantreeseba/graphql-casl-codegen': noEmitLegacy },
      ],
    },

    // OPTIONAL — SchemaTypeMap for @vantreeseba/graphql-mocks' buildMocks.
    './server/src/__generated__/schema-type-map.ts': {
      plugins: [{ '@vantreeseba/graphql-mocks-codegen': noEmitLegacy }],
      config: { typesImportPath: './resolvers.ts' },
    },
  },
};

export default config;
