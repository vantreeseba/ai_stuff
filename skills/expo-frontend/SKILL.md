---
name: expo-frontend
description: >
  Build a cross-platform client the cubicecho way: Expo Router with route
  groups, React Native Web, NativeWind, platform-variant components
  (.native/.web/-base), Apollo with subscriptions, and layout components shared
  across web and device. Use when creating or extending a client that must run
  on iOS/Android as well as the browser.
version: 0.0.1
license: MIT
---

# Expo Frontend

> ## Expo changes fast. Read the versioned docs first.
>
> Before writing any code, read the exact docs for the SDK this project pins:
> **`https://docs.expo.dev/versions/v<SDK>.0.0/`** — get `<SDK>` from the `expo`
> dependency in `client/package.json`. Router APIs, config plugins, and the
> `expo-*` module surface all move between majors, and answers from memory are
> routinely a version or two stale. This is not optional caution; it is the most
> common source of wasted work in this stack.

If a `ts-house-style` skill is available, read it for the shared conventions
(ESM, Biome, workspace layout, git). If not, this skill stands on its own.

For a browser-only client, use the `simple-ts-frontend` skill if it is available
— Vite + TanStack Router is a simpler stack, and mixing the two causes problems.

## Loadout

| Concern | Choice |
| --- | --- |
| Framework | Expo SDK 56/57, `"main": "expo-router/entry"` |
| Routing | Expo Router, file-based, route groups |
| Web | React Native Web |
| Styling | NativeWind 4 (Tailwind) + shadcn-style tokens |
| UI | Radix on web, RN primitives on native, behind platform variants |
| Data | Apollo Client + `graphql-ws` subscriptions |
| Forms | TanStack Form + zod |
| Icons | `lucide-react` (web) / `lucide-react-native` (native) |
| Storage | AsyncStorage behind a synchronous wrapper |

## Structure

```
app/            expo-router routes ONLY — every file is a URL
  _layout.tsx     providers, auth guard, root ErrorBoundary
  auth/           login, verify
  (app)/          route group: the signed-in shell
    _layout.tsx     nav, onboarding guard, useLiveUpdates()
src/            everything else
  components/ui/      cross-platform primitives + layout components
  components/native/  native-only composites
  components/domain/
  hooks/  lib/  __generated__/
```

**There is no `App.tsx` and no `main.tsx`** — `expo-router/entry` is the entry
point and `app/_layout.tsx` is the root. **Guards live in layouts, never in
screens**: one guard per concern, in the layout that owns that subtree.

→ **[`references/folder-structure.md`](references/folder-structure.md)** —
route groups, the guard and `ErrorBoundary` patterns in full, and the three
monorepo patches `metro.config.js` needs.

## Platform variants

```
input-base.ts    the shared contract — types, class strings, context
input.tsx        native
input.web.tsx    web
```

**The `-base` file is not optional.** Metro resolves `./input` to
`input.web.tsx` on web, so the web file importing shared pieces from `./input`
would be importing itself.

**TypeScript only ever resolves the native file.** It never compares the two, so
a drifted web variant type-checks green and breaks at runtime. Keep the contract
in `-base`, keep the pair small, and build web in CI.

**Never touch `window`, `document`, or `localStorage`** outside a
`Platform.OS === 'web'` guard. Persistence goes through the one `storage`
wrapper, whose interface is deliberately synchronous so callers need no `await`.

→ **[`references/platform-variants.md`](references/platform-variants.md)** — the
full triple, the icons worked example (including why a barrel import bloats the
native bundle), route-level variants, and the storage wrapper.

## Layout and zone components

`Page`, `PageHeader`, `CardGrid`, `EmptyState`, `DetailPage`, `DetailHeader`,
`SectionHeading`, `QueryState`, `FormDialog`, `ConfirmDialog` — in
`src/components/ui/`. Reach for one rather than hand-rolling a flex row inline.

The distinction to get right is `Page`'s `fill` prop: default `flex-1` for a page
that scrolls as one document, `fill` (`h-full min-h-0 flex-col`) for a page whose
*child* scrolls. Get it wrong and the page scrolls when only the list should.

Buttons take **`onPress`, not `onClick`** — `onClick` silently does nothing on
native.

→ **[`references/layout-components.md`](references/layout-components.md)** — every
component with its props and rationale, a worked list screen, and the two-channel
error convention for form dialogs.

## Data

Apollo with a split link: subscriptions over `graphql-ws`, everything else HTTP.
Always the generated `graphql()` helper against a literal document, fragments
colocated with the component that reads them.

Cache invalidation evicts root fields by name rather than naming queries. If a
`simple-ts-frontend` skill is available its cache-invalidation reference covers
the same `lib/cache.ts` helpers, which are identical here.

**One live-updates subscriber for the whole app**, mounted in `(app)/_layout.tsx`,
translating server events into that same vocabulary. Per-page subscriptions rot:
the entity list is hand-written per page, `refetch()` only reaches one query, and
N pages open N× the sockets.

→ **[`references/live-updates.md`](references/live-updates.md)** — the hook, the
exhaustive `Record<DataEntity, …>` that makes adding an entity a compile error,
the two server event shapes, and the `connectionParams`-must-be-a-function rule.

## Styling and dark mode

NativeWind preset, `darkMode: ['class']`, shadcn DEFAULT/foreground token pairs
as CSS variables. **Components reference tokens, never literal colours** — a
`bg-white` is a dark-mode bug by construction.

The dark-mode hook's one subtle rule: *reading* the OS preference must not
persist it, or an untouched account stops following the OS.

→ **[`references/nativewind-dark-mode.md`](references/nativewind-dark-mode.md)** —
the full `tailwind.config.js`, the hook, `cn()`, and icon colour on native.

## Onboarding

A local `onboarding_done` flag guards it, but that flag is per-device — so the
first step asks the server with a cheap existence query and self-heals for an
account signing in on a new device. Step number lives in the URL, clamped. Skip
must set the flag or the user is trapped in a loop.

→ **[`references/onboarding.md`](references/onboarding.md)** — the guard, the
self-healing probe with its four load-bearing details, and the step-component
split.

## After changing anything

```bash
npm run codegen && npm run typecheck && npm run lint:fix
```

Codegen must include `client/app/**` in its `documents` glob — operations live in
route files, and leaving `app/` out silently drops every route's query from the
generated types.
