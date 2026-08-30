# package.json, exports, and dependencies

## A single ESM package

```jsonc
{
  "name": "@vantreeseba/graphql-casl",
  "version": "1.3.0",
  "description": "GraphQL middleware plugin for defining CASL permission rules on resolvers, with optional argument scoping and an envelop/Yoga integration.",
  "keywords": ["graphql", "graphql-middleware", "casl", "authorization", "permissions", "typescript"],
  "type": "module",
  "engines": { "node": ">=22" },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/cubicecho/graphql-casl.git",
    "directory": "packages/graphql-casl"
  },
  "homepage": "https://github.com/cubicecho/graphql-casl#readme",
  "bugs": { "url": "https://github.com/cubicecho/graphql-casl/issues" },
  "license": "MIT",
  "author": "Benjamin Van Treese <vantreeseba@gmail.com>",
  "exports": {
    ".":          { "types": "./dist/index.d.ts",   "import": "./dist/index.js" },
    "./scoping":  { "types": "./dist/scoping.d.ts", "import": "./dist/scoping.js" },
    "./envelop":  { "types": "./dist/envelop.d.ts", "import": "./dist/envelop.js" },
    "./package.json": "./package.json"
  },
  "files": ["dist"],
  "publishConfig": { "access": "public" },
  "scripts": {
    "build": "tsc",
    "prepack": "npm run build",
    "typecheck": "tsc --noEmit",
    "typecheck:tests": "tsc -p tsconfig.tests.json",
    "test": "vitest run",
    "test:watch": "vitest",
    "coverage": "vitest run --coverage",
    "docs": "typedoc",
    "format": "biome format --write .",
    "lint": "biome lint .",
    "check": "biome check ."
  }
}
```

Non-obvious bits:

- `description` and `keywords` are the npm search surface. Write the description
  as one sentence a stranger could act on, not a slogan.
- `repository.directory` is required in a monorepo — without it, npm links every
  package at the repo root and "view source" lands in the wrong place.
- **`prepack` builds**, so a publish can never ship a stale `dist/`.
- `files: ["dist"]` — never publish `src/` or tests. Everything not listed is
  excluded except the always-included `package.json`, `README`, and `LICENSE`.
- `"./package.json": "./package.json"` — some tooling reads it through the
  export map, and an `exports` field without it makes that fail.
- `publishConfig.access: "public"` — a scoped package defaults to restricted and
  the publish fails without it.
- `types` **first** in every export condition. Node ignores it; TypeScript takes
  the first match, so a later `types` is never reached.

## Dependencies: peer-first

**Anything the consumer already has is a peer dependency with a range**, plus a
devDependency at a concrete version for the tests:

```jsonc
"peerDependencies": {
  "graphql": ">=16 <18",
  "@graphql-codegen/plugin-helpers": ">=5",
  "@casl/ability": ">=6"
},
"devDependencies": {
  "graphql": "^16.14.0",
  "@graphql-codegen/plugin-helpers": "^5.1.1"
}
```

Two copies of `graphql` in one process is a silent failure — instanceof checks
across realms return false, and the error surfaces as "Cannot use GraphQLSchema
from another module or realm". A hard dependency on `graphql` guarantees it.
The same reasoning applies to `@modelcontextprotocol/sdk`, `@casl/ability`, and
`graphql-middleware`.

Aim for **zero runtime dependencies**. Every one is a version the consumer
inherits without asking.

## Optional peers for subpath exports

Where one subpath needs a package the rest do not:

```jsonc
"peerDependencies": { "@envelop/core": ">=5" },
"peerDependenciesMeta": { "@envelop/core": { "optional": true } }
```

npm then installs it only for consumers who actually import that subpath.

> **The main entry point must never import the optional one.** `src/index.ts`
> importing `src/envelop.ts` puts `@envelop/core` into `dist/index.d.ts` for
> every consumer, and the optional peer becomes a required one that npm does not
> install. This is worth a comment at the top of both files and a line in
> `AGENTS.md` — it is invisible in review and only breaks for consumers.

## Subpath layout

One `src/*.ts` per subpath, each a real entry point:

```
src/
├── index.ts      → "."
├── scoping.ts    → "./scoping"
├── envelop.ts    → "./envelop"    (optional peer lives here)
└── internal.ts   → not exported
```

Symbols two entry points both need, where neither may import the other, go in
`internal.ts`. It is not in `exports`, so it is not API.

## Dual ESM/CJS

Only when consumers demand it — a codegen plugin does, because graphql-codegen
loads plugins with `require` when the consuming project is CommonJS.

```jsonc
"main": "./dist/cjs/index.js",
"module": "./dist/esm/index.js",
"types": "./dist/esm/index.d.ts",
"exports": {
  ".": {
    "import":  { "types": "./dist/esm/index.d.ts", "default": "./dist/esm/index.js" },
    "require": { "types": "./dist/cjs/index.d.ts", "default": "./dist/cjs/index.js" }
  },
  "./package.json": "./package.json"
},
"scripts": {
  "clean": "node -e \"require('node:fs').rmSync('dist',{recursive:true,force:true})\"",
  "build": "npm run clean && tsc -p tsconfig.build.json && tsc -p tsconfig.cjs.json && node scripts/postbuild.mjs"
}
```

`tsconfig.build.json`:

```jsonc
{
  "extends": "./tsconfig.json",
  "compilerOptions": { "noEmit": false, "outDir": "./dist/esm", "rootDir": "./src" },
  "include": ["src"],
  "exclude": ["**/*.test.ts"]
}
```

`tsconfig.cjs.json`:

```jsonc
{
  "extends": "./tsconfig.build.json",
  "compilerOptions": {
    "module": "CommonJS",
    "moduleResolution": "Node10",
    "verbatimModuleSyntax": false,
    "outDir": "./dist/cjs"
  }
}
```

`scripts/postbuild.mjs`:

```javascript
// The package is `"type": "module"`, so Node reads every `.js` under it as ESM.
// Dropping a CommonJS package.json into dist/cjs scopes that build back to CJS
// without renaming files to `.cjs`.
import { writeFileSync } from 'node:fs';

writeFileSync('dist/cjs/package.json', `${JSON.stringify({ type: 'commonjs' }, null, 2)}\n`);
writeFileSync('dist/esm/package.json', `${JSON.stringify({ type: 'module' }, null, 2)}\n`);
```

`clean` before the two `tsc` passes is not optional: without it a renamed source
file leaves its old output in `dist/` and it ships.

## Monorepo root

```jsonc
{
  "name": "@vantreeseba/graphql-casl-monorepo",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "workspaces": ["packages/*"],
  "scripts": {
    "build": "npm run build --workspaces --if-present",
    "typecheck": "npm run typecheck --workspaces --if-present",
    "typecheck:tests": "npm run typecheck:tests --workspaces --if-present",
    "test": "npm run test --workspaces --if-present",
    "coverage": "npm run coverage --workspaces --if-present",
    "docs": "npm run docs --workspaces --if-present",
    "check": "biome check ."
  }
}
```

The root is `private: true` and stays at `0.0.0` — only sub-packages publish, and
their versions are managed by semantic-release. All release tooling
(`semantic-release`, its plugins, `typedoc`, `vitest`, `biome`, `typescript`)
lives in the root devDependencies; sub-packages carry only what their own tests
need.
