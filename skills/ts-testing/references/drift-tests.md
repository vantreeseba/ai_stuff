# Drift tests

**Write a drift test wherever two things describe the same shape and nothing but
habit keeps them in step.**

The failure mode is always the same: the two descriptions disagree, both halves
still compile, and the symptom is a feature that quietly does nothing. Nobody
reports "the setting had no effect"; they report it a quarter later as a bug
with no reproduction.

Candidates in this stack:

| A | B | What drifts |
| --- | --- | --- |
| SDL mutation inputs | zod validators | a field reaches the DB unvalidated |
| SDL root fields | the client's `RootField` union | an invalidation that evicts nothing |
| server event types | `Record<DataEntity, RootField[]>` | an entity that never refreshes |
| SDL enum | a const-tuple enum in `db` | a value the DB accepts and the API rejects |
| public exports | `typedoc.json` `entryPoints` | an undocumented public API |

## The worked example: SDL ↔ zod validators

```typescript
/**
 * Drift check between the SDL's mutation inputs and the Zod validators.
 *
 * The SDL and `validators.ts` describe the same inputs twice, and nothing but
 * habit keeps them in step. A field added to `CreateHabitArgs` but not to
 * `CreateHabitInput` type-checks, resolves, and reaches the database
 * unvalidated — Zod strips unknown keys silently, so the symptom is a setting
 * that does nothing rather than an error anyone would notice. A field deleted
 * from the SDL but left in Zod is the harmless direction, but it is also how
 * validators accumulate rules for fields that no longer exist.
 *
 * So: every input type reachable from a mutation argument must have a
 * validator, and the two must agree field for field.
 */
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { type GraphQLInputObjectType, buildSchema, isInputObjectType } from 'graphql';
import { describe, expect, it } from 'vitest';
import type { z } from 'zod';
import { CreateHabitInput, CreateTodoInput, UpdateTodoInput /* … */ } from '../../src/schema/validators.ts';

/**
 * SDL input type name → validator. The names differ by convention (the SDL
 * suffixes `Args`, the validators suffix `Input`), so the pairing has to be
 * written out; the tests below then prove it is complete in both directions.
 */
const VALIDATORS: Record<string, z.ZodTypeAny> = {
  CreateHabitArgs: CreateHabitInput,
  CreateTodoArgs: CreateTodoInput,
  UpdateTodoArgs: UpdateTodoInput,
  // …
};

const __dirname = dirname(fileURLToPath(import.meta.url));
const schema = buildSchema(
  readFileSync(resolve(__dirname, '../../src/__generated__/schema.graphql'), 'utf8'),
);

/**
 * Every input object type a mutation can be handed, directly or nested.
 *
 * Reachability from `Mutation` rather than "every input in the SDL" is what
 * keeps drizzle-graphql's generated filter and order-by inputs out: those are
 * query-side, and nothing hand-written validates them.
 */
function reachableMutationInputs(): Map<string, GraphQLInputObjectType> {
  const found = new Map<string, GraphQLInputObjectType>();
  const visit = (type: unknown): void => {
    if (!isInputObjectType(type) || found.has(type.name)) return;
    found.set(type.name, type);
    for (const field of Object.values(type.getFields())) {
      visit(unwrap(field.type));
    }
  };
  for (const field of Object.values(schema.getMutationType()?.getFields() ?? {})) {
    for (const arg of field.args) visit(unwrap(arg.type));
  }
  return found;
}

/** Strip `!` and `[]` down to the named type. */
function unwrap(type: unknown): unknown {
  let t = type as { ofType?: unknown };
  while (t?.ofType) t = t.ofType as { ofType?: unknown };
  return t;
}

/**
 * `.refine()` wraps the object in a `ZodEffects`, which has no `.shape` —
 * `CreateTimeBlockInput` is one, and reading its keys means unwrapping first.
 */
function keysOf(validator: z.ZodTypeAny): string[] {
  let v = validator;
  while ('innerType' in v && typeof v.innerType === 'function') {
    v = (v as unknown as { innerType(): z.ZodTypeAny }).innerType();
  }
  const shape = (v as unknown as { shape?: Record<string, unknown> }).shape;
  if (!shape) throw new Error('not a ZodObject');
  return Object.keys(shape).sort();
}

const reachable = reachableMutationInputs();

describe('mutation inputs', () => {
  it('all have a validator', () => {
    const unvalidated = [...reachable.keys()].filter((name) => !VALIDATORS[name]).sort();
    expect(unvalidated).toEqual([]);
  });

  it('have no validator for an input no mutation takes', () => {
    const orphaned = Object.keys(VALIDATORS).filter((name) => !reachable.has(name)).sort();
    expect(orphaned).toEqual([]);
  });
});

describe.each([...reachable.keys()].sort())('%s', (name) => {
  const validator = VALIDATORS[name];
  // The suite above reports a missing validator once; skip the pair rather
  // than failing again here with a less legible message.
  if (!validator) return;

  it('validates exactly the fields the SDL declares', () => {
    const sdlFields = Object.keys((reachable.get(name) as GraphQLInputObjectType).getFields()).sort();
    expect(keysOf(validator)).toEqual(sdlFields);
  });
});
```

## The shape to copy

1. **Read the generated artifact at runtime**, not a snapshot of it. The whole
   point is that it moves.
2. **Derive the set to check** rather than listing it. `reachableMutationInputs`
   is what makes a *new* mutation automatically covered — a hardcoded list is a
   second thing to keep in step, which is the problem you set out to solve.
3. **Assert in both directions.** "Every SDL input has a validator" and "every
   validator has an SDL input". One direction alone leaves the orphan case,
   which is how dead validation rules accumulate.
4. **`expect(diff).toEqual([])`, not `expect(diff.length).toBe(0)`.** The
   failure message then names exactly what drifted.
5. **`describe.each` over the derived set**, so the failure names the type. One
   assertion looping internally reports the first mismatch and stops.
6. **`if (!validator) return;`** inside the per-pair block. The completeness
   suite already reported the missing one; failing again here just adds a worse
   message.

## Exhaustiveness instead, where a Record will do

Where the two sides are both TypeScript, a drift test is unnecessary — make it a
compile error:

```typescript
const FIELDS_FOR: Record<DataEntity, readonly RootField[]> = {
  todo: ['myTodos', 'mySchedule'],
  habit: ['myHabits'],
  // adding a DataEntity without a line here fails to compile
};
```

Reach for a drift test when one side is *not* TypeScript — SDL, a migration, a
JSON config — or when it is generated by a tool that would happily generate the
mismatch.
