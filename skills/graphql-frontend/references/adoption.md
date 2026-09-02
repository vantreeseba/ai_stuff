# Adoption

## Follow the repo

Before anything: **check what the repo already does.** A codebase with
`fragmentMasking: false` and fragments read as plain generated types is a
coherent, working setup. Changing one component to the masked style makes the
codebase inconsistent, which is worse than either style alone.

```bash
grep -rn "fragmentMasking\|dataMasking\|inlineFragmentTypes" --include='*.ts' .
grep -rln "useFragment\|getFragmentData" src/
```

Migrate deliberately, as its own change, or not at all. The rest of this file is
how to do it deliberately.

## Greenfield

Turn everything on in the first commit, before there is anything to migrate:

1. `preset: 'client'` with `fragmentMasking: { unmaskFunctionName: 'getFragmentData' }`
2. `dataMasking: true` on the client
3. `src/apollo-client.d.ts` with the `TypeOverrides` merge
4. Write the first component with a fragment, so the pattern is established
   before anyone has to argue for it

Cost is zero at this point. Retrofitting later is a week.

## Existing app, masking off

The naive path — flip both flags and fix the type errors — produces hundreds of
errors at once with no ordering, and the branch never lands. Do this instead.

### Step 1 — codegen masking on, everything unmasked

Enable `fragmentMasking` in codegen and add `@unmask` to **every existing
fragment spread**. Types are unchanged; the build stays green. This is a
mechanical edit and can be scripted.

### Step 2 — Apollo `dataMasking` on, in migrate mode

Set `dataMasking: true`, and change the directives to:

```graphql
...Person_Row @unmask(mode: "migrate")
```

In migrate mode the fields are **still present at runtime**, and Apollo logs a
warning the first time a consumer reads a field it did not declare. Nothing
breaks; you now have a work list from the console instead of from the compiler.

### Step 3 — work the list

Per warning: move the field into the reading component's fragment, or create a
fragment for a component that had none. When a spread produces no more warnings,
drop its `@unmask` entirely.

Work outside-in — containers first, then composites, then leaves. A container
that stops reading a field usually eliminates several downstream warnings at
once.

### Step 4 — remove the last `@unmask`

The remaining ones are the legitimate cases from `cache-and-masking.md`
(serialization boundaries, tests). Leave a comment on each saying why, or the
next person deletes it and breaks something.

## Existing app, no codegen at all

`gql` templates and hand-written types. Two changes, in order:

1. **Codegen first, masking off.** Replace `gql` with the generated `graphql()`
   helper, delete the hand-written types. This alone is a large correctness win
   and it is independently valuable, so it can land on its own.
2. **Then the masking migration above.**

Doing both at once means every type error is ambiguous between "codegen
disagrees with the hand-written type" and "this component reads what it did not
declare."

## Anti-patterns

| Anti-pattern | Why it fails |
| --- | --- |
| One `fragments.ts` per entity holding every fragment for it | the requirement stops tracking the component; nothing can be deleted safely |
| A `useQuery` per row instead of a fragment per row | N+1 network requests, and no shared cache benefit |
| `@unmask` added to silence a type error | deletes the boundary at exactly the point it was working |
| `Unmasked<T>` in component props | same, with extra steps |
| Reading fragment fields off a mutation's return value | masked there; returns `undefined` at runtime while type-checking under a missing bridge |
| Interpolating into a `graphql()` template | falls out of the overload set; types silently degrade to `any` |
| Fragments named for the type only (`PersonFields`) | collides as soon as a second consumer wants a different shape |
| Adding fields "we'll need later" | nothing ever removes them; the query grows monotonically |
| Turning `dataMasking` on without codegen masking | runtime holes with no type errors pointing at them |

## Verifying a migration

```bash
npm run codegen && npm run check && npm test
```

Then, in the app: exercise the screens whose components changed and watch for
`complete: false` spinners that do not resolve. Those are mutations with
selection sets narrower than the fragments — the most common thing a masking
migration exposes, because before masking the parent query happened to fetch the
fields and nobody noticed the mutation did not.
