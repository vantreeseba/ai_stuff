/**
 * codegen.ts — client-side codegen template.
 *
 * Run with `graphql-codegen --config codegen.ts`. Reads the same printed SDL the
 * server config reads, plus every operation document in the client.
 */
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { CodegenConfig } from '@graphql-codegen/cli';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const config: CodegenConfig = {
  schema: path.resolve(__dirname, 'server/src/__generated__/schema.graphql'),

  // Include EVERY tree that holds operations. On Expo that is `client/app/**`
  // as well as `client/src/**` — routes are the easiest to forget, and their
  // operations then silently generate as `unknown`.
  documents: [
    path.resolve(__dirname, 'client/src/**/*.{tsx,ts}'),
    path.resolve(__dirname, 'client/app/**/*.{tsx,ts}'),
    // Always exclude the generated directory, or codegen reads its own output.
    `!${path.resolve(__dirname, 'client/src/__generated__/**')}`,
  ],

  // Don't fail the run before any operation exists (a fresh project, or a
  // package whose documents all live elsewhere).
  ignoreNoDocuments: true,

  generates: {
    // The trailing slash is required: the client preset emits a DIRECTORY
    // (gql.ts, graphql.ts, fragment-masking.ts, index.ts), not a file.
    [`${path.resolve(__dirname, 'client/src/__generated__')}/`]: {
      preset: 'client',
      presetConfig: {
        // The name of the emitted document helper. `graphql` is the default and
        // what every operation in these projects calls.
        gqlTagName: 'graphql',
        // false when components read fragment data directly.
        // Leave masking ON (and use `useFragment`) where Apollo's own
        // `dataMasking: true` is enabled. Pick one per project; do not mix.
        fragmentMasking: false,
      },
      config: {
        scalars: {
          UUID: 'string',
          DateTime: 'Date',
          // input/output split: a Date is sent as an ISO string but read back
          // as a Date, once a scalar type policy parses it.
          Date: { input: 'string', output: 'Date' },
        },
        // `null` for nullable fields instead of optionals, matching the server.
        avoidOptionals: { field: true },
        useTypeImports: true,
        // An unmapped scalar is `unknown`, not `any` — it fails at the call
        // site instead of leaking through.
        defaultScalarType: 'unknown',
        // The cache keys off __typename; always select it.
        nonOptionalTypename: true,
        skipTypeNameForRoot: true,
        // With Apollo dataMasking on, @unmask must be a known directive.
        customDirectives: { apolloUnmask: true },
      },
    },

    // OPTIONAL — Apollo type policies that parse scalars on read, so a
    // DateTime field is a real Date in components instead of a string.
    'client/src/__generated__/type-policies.ts': {
      plugins: ['@homebound/graphql-typescript-scalar-type-policies'],
      config: {
        scalarTypePolicies: {
          DateTime: '@/lib/date-type-policy#dateTimeTypePolicy',
          Date: '@/lib/date-type-policy#dateTypePolicy',
        },
      },
    },
  },
};

export default config;

/**
 * Operations MUST use the generated `graphql()` helper against a string
 * literal:
 *
 *   const GET_TODOS = graphql(`query GetTodos { todos { id title } }`);
 *
 * A raw `gql` template is invisible to codegen and produces an untyped
 * document. It typechecks and fails at runtime. So does an interpolated or
 * variable-built document string — the extractor only sees literals.
 */
