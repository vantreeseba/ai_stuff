# Biome config notes

`biome.json` in this directory is the canonical v2 config. Copy it to the repo
root — **one config for the whole repo**, never one per workspace.

## Why each escalation exists

| Rule | Level | Why |
| --- | --- | --- |
| `correctness/noUnusedImports` | error | A dead import is usually a half-finished refactor. Biome autofixes it. |
| `correctness/noUnusedVariables` | error | Same, and it catches a destructured field that was renamed on the server. |
| `correctness/useHookAtTopLevel` | error | A conditional hook is a runtime crash that types cannot catch. |
| `correctness/useExhaustiveDependencies` | warn | Real often enough to surface, wrong often enough not to block a commit. |
| `style/useImportType` | error | With `--experimental-strip-types` a value import of a type-only module is a **runtime** resolution error, not a type error. This rule is load-bearing, not cosmetic. |
| `style/noNonNullAssertion` | off | Turned off deliberately — the codegen resolver-map types made `!` unnecessary in the places that mattered, and the remaining ones are in test setup. |
| `suspicious/noExplicitAny` | warn | `unknown` is the house preference, but a warn keeps a dependency's bad type from blocking a build. |

## The exclusion list is not optional

`__generated__/`, `dist/`, `drizzle/`, `*.gen.ts` are excluded from **both**
linting and formatting. Generated code is never hand-edited and never reviewed;
formatting it produces diffs that hide real changes, and linting it produces
errors nobody can fix without editing a file that is about to be overwritten.

Some repos also exclude `pgdata/`, `coverage/`, and `routeTree.gen.ts`
explicitly. Add whatever the project generates.

## v1 vs v2

Older repos (auto-cal, notes) are on Biome 1.9 and the schema differs:

| v2 | v1 |
| --- | --- |
| `files.includes` with `!` negations | `files.include` + separate `overrides` with `include` |
| `assist.actions.source.organizeImports` | top-level `organizeImports: { enabled: true }` |
| `includes` in an override | `include` in an override |

Do not migrate a repo's config as a side effect of another change. Match what
the repo already has, and let `biome migrate` do it when the version is bumped
deliberately.

## Line width

120 in newer repos, 80 in philotes. **Follow the repo's `biome.json` and never
argue with it** — a width change reformats every file and buries the real diff.
