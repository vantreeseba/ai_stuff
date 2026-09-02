# Folder structure

```
client/
├── app/                        expo-router routes — ROUTES ONLY
│   ├── _layout.tsx             providers, auth guard, root ErrorBoundary
│   ├── auth/
│   │   ├── login.tsx
│   │   └── verify.tsx
│   └── (app)/                  route group: the signed-in shell
│       ├── _layout.tsx         nav, onboarding guard, useLiveUpdates()
│       ├── index.tsx
│       ├── today.tsx
│       ├── todo-lists.tsx
│       ├── todo-lists.native.tsx    native variant of the same route
│       ├── habits/
│       │   ├── _layout.tsx
│       │   ├── index.tsx
│       │   └── [habitId].tsx
│       └── settings.tsx
├── src/
│   ├── apollo-client.ts
│   ├── storage.ts              the ONLY module that touches persistence
│   ├── index.css               web design tokens
│   ├── components/
│   │   ├── ui/                 cross-platform primitives + layout/zone components
│   │   ├── native/             native-only composites
│   │   └── domain/<entity>/
│   ├── hooks/
│   ├── lib/                    utils.ts (cn), cache.ts
│   └── __generated__/          gitignored, never edited
├── global.css                  @tailwind directives for nativewind
├── tailwind.config.js
├── babel.config.js
├── metro.config.js
├── app.json
└── package.json                "main": "expo-router/entry"
```

## `app/` versus `src/`

**`app/` holds routes and nothing else.** Every file under it is a URL. A helper
dropped there becomes a route with a broken component export.

**There is no `App.tsx` and no `main.tsx`.** `package.json` says
`"main": "expo-router/entry"`, and `app/_layout.tsx` is the root. Creating an
`App.tsx` out of web habit produces a file nothing imports.

## Route groups

`(app)` is a **route group**: the parentheses keep it out of the URL, so
`app/(app)/today.tsx` is `/today`, not `/app/today`. It exists to give the
signed-in half of the app its own layout — providers, nav chrome, guards — that
`/auth/login` does not get.

`[habitId].tsx` is a dynamic segment, read with `useLocalSearchParams()`.

## Guards live in layouts, never in screens

```tsx
// app/_layout.tsx — authentication
function AuthGuard({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const token = storage.getItem('auth_token');

  if (!token && !pathname.startsWith('/auth')) {
    return <Redirect href="/auth/login" />;
  }

  return <>{children}</>;
}

export default function RootLayout() {
  // Applies the stored theme on the /auth screens, which sit outside (app).
  useDarkMode();

  return (
    <ApolloProvider client={apolloClient}>
      {/* Outside the guard so a toast survives a redirect to /auth/login. */}
      <ToastProvider>
        <AuthGuard>
          <Stack screenOptions={{ headerShown: false }} />
        </AuthGuard>
      </ToastProvider>
    </ApolloProvider>
  );
}
```

```tsx
// app/(app)/_layout.tsx — onboarding
export default function AppLayout() {
  const pathname = usePathname();
  // One subscriber for the whole app; pages read the cache it keeps current.
  useLiveUpdates();
  const onboardingDone = storage.getItem('onboarding_done');

  if (!onboardingDone && !pathname.startsWith('/onboarding')) {
    return <Redirect href="/onboarding" />;
  }

  if (Platform.OS === 'web') return <WebLayout />;
  return <NativeLayout />;
}
```

**A screen never checks auth.** One guard per concern, in the layout that owns
that subtree. Anything else drifts: a screen added later forgets the check.

Note the provider ordering comment — `ToastProvider` sits *outside* `AuthGuard`
so a toast queued before a redirect survives it.

## `ErrorBoundary` per segment

expo-router mounts a **named** `ErrorBoundary` export from a route or layout file
around that segment's tree:

```tsx
/**
 * expo-router mounts a named `ErrorBoundary` export from a route or layout file
 * around that segment's tree. This one is the outermost: without it a render
 * crash anywhere unmounts the whole app to a blank white page with the error
 * only in the console. `retry` re-renders the segment, which is enough to
 * recover from a transient failure without a full reload.
 */
export function ErrorBoundary({ error, retry }: ErrorBoundaryProps) {
  return <RouteError error={error} reset={retry} />;
}
```

Export one from `app/_layout.tsx` at minimum, and one from `(app)/_layout.tsx`
so a crash in a signed-in screen loses that segment rather than the whole app.
It is a named export, not the default — a default export there is a route.

## `src/components/`

| Directory | Holds |
| --- | --- |
| `ui/` | cross-platform primitives and layout/zone components |
| `native/` | composites that only exist on native (`list-screen`, `form-modal`) |
| `domain/<entity>/` | feature components |

`ui/` is where the platform-variant triples live (`input.tsx` /
`input.web.tsx` / `input-base.ts`). See the platform-variants reference.

## `babel.config.js`

```javascript
module.exports = (api) => {
  api.cache(true);
  return {
    presets: [
      ['babel-preset-expo', { jsxImportSource: 'nativewind', runtime: 'automatic' }],
      'nativewind/babel',
    ],
    plugins: [
      ['module-resolver', { root: ['./'], alias: { '@': './src' } }],
    ],
  };
};
```

`jsxImportSource: 'nativewind'` is what makes `className` work on React Native
components at all. The `@` alias must be declared here **and** in
`tsconfig.json` — babel resolves at build time, TypeScript at check time, and
they do not read each other.

## `metro.config.js` in a monorepo

```javascript
// Patch NODE_PATH before any other requires so that root-hoisted packages
// (nativewind, react-native-css-interop) can find react-native, which npm
// keeps in this workspace's local node_modules rather than hoisting it.
const path = require('node:path');
const Module = require('node:module');
const localModules = path.resolve(__dirname, 'node_modules');
if (!process.env.NODE_PATH?.split(path.delimiter).includes(localModules)) {
  process.env.NODE_PATH = [localModules, process.env.NODE_PATH].filter(Boolean).join(path.delimiter);
  Module._initPaths();
}

const { getDefaultConfig } = require('expo/metro-config');
const { withNativeWind } = require('nativewind/metro');

const config = getDefaultConfig(__dirname);

// Resolve monorepo packages from the workspace root
const workspaceRoot = path.resolve(__dirname, '..');
config.watchFolders = [workspaceRoot];
config.resolver.nodeModulesPaths = [localModules, path.resolve(workspaceRoot, 'node_modules')];

const nativeWindConfig = withNativeWind(config, { input: './global.css' });

// Metro doesn't auto-resolve .js imports to .ts files (TypeScript ESM convention).
// Wrap the resolver: if a .js request fails, retry with .ts before giving up.
const nwResolveRequest = nativeWindConfig.resolver?.resolveRequest ?? null;
nativeWindConfig.resolver.resolveRequest = (context, moduleName, platform) => {
  const resolve = nwResolveRequest ?? context.resolveRequest;
  if (moduleName.endsWith('.js')) {
    const base = moduleName.slice(0, -3);
    for (const ext of ['.ts', '.tsx']) {
      try {
        return resolve(context, `${base}${ext}`, platform);
      } catch {
        // try next
      }
    }
  }
  return resolve(context, moduleName, platform);
};

module.exports = nativeWindConfig;
```

Three monorepo-specific patches, each fixing a real failure:

- **`NODE_PATH`** — root-hoisted `nativewind` cannot find `react-native`, which
  npm keeps in the workspace's local `node_modules`.
- **`watchFolders` + `nodeModulesPaths`** — Metro does not know about workspaces.
- **the `.js` → `.ts` resolver wrapper** — codegen output and TypeScript's ESM
  convention emit `.js` specifiers for `.ts` files, which Metro will not follow.

Copy all three when setting up a new Expo workspace in a monorepo. Skipping them
produces resolution errors that look like missing dependencies.
