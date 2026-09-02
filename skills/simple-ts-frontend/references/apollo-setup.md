# Apollo Client setup

## Minimal — query/mutation only

```tsx
import { ApolloClient, ApolloProvider, HttpLink, InMemoryCache } from '@apollo/client';
import { createRouter, RouterProvider } from '@tanstack/react-router';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { routeTree } from './routeTree.gen';
import './index.css';

const client = new ApolloClient({
  cache: new InMemoryCache(),
  dataMasking: true,
  link: new HttpLink({ uri: '/graphql' }),
});

const router = createRouter({ routeTree });

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router;
  }
}

const rootElement = document.getElementById('root');
if (!rootElement) {
  throw new Error('Missing #root element');
}

createRoot(rootElement).render(
  <StrictMode>
    <ApolloProvider client={client}>
      <RouterProvider client={client} router={router} />
    </ApolloProvider>
  </StrictMode>,
);
```

**`uri: '/graphql'` — relative, always.** Vite proxies it in dev; in production
the same Express process serves both the bundle and the API. No
`VITE_API_URL`, no CORS, no token crossing origins.

**`dataMasking: true`.** A component may only read the fields its *own* fragment
declares — reading a field a parent happened to fetch is a type error. This is
what makes fragment colocation actually enforce a boundary rather than being a
convention. It requires `useFragment` in every component that consumes a
fragment; see the data-fetching reference.

**The `declare module` block** registers the router type globally so `Link`,
`useParams`, and `useNavigate` are typed against the real route tree. Without it
every route path is a bare `string`.

## Full — auth, error handling, subscriptions

```typescript
import { ApolloClient, ApolloLink, HttpLink, InMemoryCache } from '@apollo/client';
import { CombinedGraphQLErrors } from '@apollo/client/errors';
import { ErrorLink } from '@apollo/client/link/error';
import { GraphQLWsLink } from '@apollo/client/link/subscriptions';
import { getMainDefinition } from '@apollo/client/utilities';
import { createClient } from 'graphql-ws';
import { storage } from './storage';

const API_URL = import.meta.env.VITE_API_URL ?? '';

function buildWsUrl(): string {
  if (API_URL) {
    return `${API_URL.replace(/^http/, 'ws')}/graphql`;
  }
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${proto}//${window.location.host}/graphql`;
}

const wsLink = new GraphQLWsLink(
  createClient({
    url: buildWsUrl(),
    connectionParams: () => {
      const token = storage.getItem('auth_token');
      return token ? { authorization: `Bearer ${token}` } : {};
    },
  }),
);

const httpLink = new HttpLink({
  uri: `${API_URL}/graphql`,
  fetch: (uri, options) => {
    const token = storage.getItem('auth_token');
    const headers = new Headers(options?.headers as HeadersInit | undefined);
    if (token) headers.set('authorization', `Bearer ${token}`);
    return fetch(uri as RequestInfo, { ...(options as RequestInit), headers });
  },
});

// Route subscription operations to the WebSocket link; everything else to HTTP.
const splitLink = ApolloLink.split(
  ({ query }) => {
    const def = getMainDefinition(query);
    return def.kind === 'OperationDefinition' && def.operation === 'subscription';
  },
  wsLink,
  httpLink,
);

const errorLink = new ErrorLink(({ error }) => {
  if (CombinedGraphQLErrors.is(error)) {
    // Match on extensions.code, not the message. The server used to throw bare
    // Errors, so this had to string-match 'Not authenticated' / 'Forbidden' and
    // any reword on the server silently disabled session expiry.
    const needsLogin = error.errors.some(
      (e) => e.extensions?.code === 'UNAUTHENTICATED' || e.extensions?.code === 'FORBIDDEN',
    );
    if (needsLogin) {
      storage.removeItem('auth_token');
      window.location.replace('/auth/login');
    }
  }
});

export const apolloClient = new ApolloClient({
  link: ApolloLink.from([errorLink, splitLink]),
  cache: new InMemoryCache({
    typePolicies: {
      // Computed views, not entities — see below.
      ScheduledItem: { keyFields: false },
    },
  }),
  defaultOptions: {
    watchQuery: { fetchPolicy: 'cache-and-network' },
  },
});
```

### `buildWsUrl`

The WS URL is derived from the page's own origin when `API_URL` is empty, so a
deployment behind any hostname works with no configuration. Deriving the
protocol from `window.location.protocol` is what keeps it working behind TLS —
hardcoding `ws:` breaks under https with a mixed-content error.

### The auth token on both transports

HTTP puts it in an `authorization` header; WS puts it in `connectionParams`.
**`connectionParams` must be a function**, not an object — an object is
evaluated once at client construction, so the socket keeps using whatever token
existed at page load and every reconnect after a login carries a stale one.

### `ErrorLink` on `extensions.code`

Branch on the code, never the message. The comment in the source is the reason:
before the server had error codes, this string-matched `'Not authenticated'`, and
any rewording on the server silently disabled session expiry — a failure with no
error, no log, and no test that would catch it.

`FORBIDDEN` is treated as needing login alongside `UNAUTHENTICATED` because a
token for a deleted user produces the former.

### `typePolicies` — unnormalizing computed views

```typescript
// `ScheduledItem.id` is the id of the todo or habit the item was computed from,
// not an id of its own — the same todo appears in every week it is scheduled or
// overdue in. Normalizing on it made one week's schedule overwrite another's, so
// paging back and forth between weeks showed the wrong times until a refetch
// landed. Keeping these unnormalized stores each `mySchedule(weekStart:)` result
// whole, which is what it is: a computed view, not an entity.
ScheduledItem: { keyFields: false },
```

**The rule this generalizes to:** any type whose `id` is borrowed from another
entity, or that can appear more than once with different field values, must set
`keyFields: false`. Apollo's default is to normalize anything with an `id`, and
for a computed projection that is silently wrong — one result overwrites another
and the UI shows data from a different query's arguments.

Symptoms: values that are correct on first load, wrong after navigating away and
back, and correct again after a hard refresh.

### `fetchPolicy: 'cache-and-network'`

Render from cache immediately, then update from the network. Combined with the
eviction-based invalidation in `lib/cache.ts`, this is what makes an evicted
field refetch automatically for every mounted consumer.

## Storage

Wrap `localStorage` rather than calling it directly, so there is one place to
change when a token needs to move to a cookie, or when the same code has to run
where `window` does not exist:

```typescript
export const storage = {
  getItem(key: string): string | null {
    return window.localStorage.getItem(key);
  },
  setItem(key: string, value: string): void {
    window.localStorage.setItem(key, value);
  },
  removeItem(key: string): void {
    window.localStorage.removeItem(key);
  },
};
```
