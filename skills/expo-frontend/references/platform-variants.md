# Platform variants

Metro resolves `./input` to `input.web.tsx` on web and `input.tsx` everywhere
else. That single rule drives the whole pattern — and its one sharp edge.

## The triple

```
input-base.ts     the shared contract: types, constants, context
input.tsx         the native implementation
input.web.tsx     the web implementation
```

**The `-base` file is not optional.** Metro resolves `./input` to
`input.web.tsx` *on web*, so `input.web.tsx` importing shared pieces from
`./input` would be importing itself. Anything both files need — types, class
strings, a context — lives in a third module neither of them shadows.

Callers always `import { Input } from '@/components/ui/input'`. They never name
a platform file.

## What goes in `-base`

```typescript
/**
 * The contract both `input.tsx` (native) and `input.web.tsx` implement.
 *
 * It lives in its own module because Metro resolves `./input` to `input.web.tsx`
 * on web — the web file importing the shared pieces from `./input` would be
 * importing itself.
 */
import type { Ref } from 'react';

/** Everything but `text` and `number` falls back to plain text entry off web. */
export type InputType = 'text' | 'number' | 'time' | 'datetime-local' | 'color';

/**
 * What a caller may do to an input imperatively. `select` is web-only —
 * `TextInput` has no equivalent — so callers must treat it as optional.
 */
export type InputHandle = {
  focus: () => void;
  select?: () => void;
};

export type InputProps = {
  value?: string | undefined;
  onChangeText?: ((text: string) => void) | undefined;
  onBlur?: (() => void) | undefined;
  /** Enter on web, the return key on native. */
  onSubmitEditing?: (() => void) | undefined;
  placeholder?: string | undefined;
  type?: InputType | undefined;
  /** Web only; the native keyboard has no equivalent constraint. */
  min?: number | undefined;
  max?: number | undefined;
  disabled?: boolean | undefined;
  className?: string | undefined;
  /** Web only: ties the control to its `<label>`. */
  id?: string | undefined;
  ref?: Ref<InputHandle> | undefined;
};

export const INPUT_CLASS =
  'border-input bg-background text-foreground flex h-10 w-full rounded-md border px-3 py-2 text-sm';
```

Two habits worth copying:

- **Comment which props are platform-specific**, in the shared file. `select?`
  being optional is the type system carrying that fact to every call site.
- **Share the class string**, not just the types. Otherwise the two
  implementations drift visually and nothing catches it.

## The check TypeScript will not do for you

> **TypeScript only ever resolves the native file.** It type-checks `input.tsx`
> and never compares it against `input.web.tsx`.

So a web variant can drift out of contract — a missing export, a renamed prop —
and `tsc --noEmit` stays green while the web build breaks at runtime. Mitigations,
in order of value:

1. **Keep the contract in `-base` and have both files import it.** A shared
   `Props` type at least makes each side check against the same shape.
2. **Say so in a comment in the web file.** The auto-cal icons file does exactly
   that: *"The exported names must stay in step with `icons.tsx`. Nothing checks
   that automatically: TypeScript only ever resolves the native file."*
3. **Keep the variant pair small.** Two files that differ in ten lines stay in
   step; two that differ in two hundred do not.
4. **Build web in CI** (`expo export --platform web`). It is the only thing that
   actually catches the drift.

## Worked example: icons

The clearest case, because the two platforms genuinely need different mechanics.

`icons-base.ts`:

```typescript
/**
 * What a component that takes an icon *as a prop* should ask for. The two
 * implementations produce structurally different components — a lucide
 * forwardRef on web, a `cssInterop` wrapper on native — and this is the part
 * they have in common.
 */
export type IconComponent = ComponentType<{ className?: string | undefined }>;

/**
 * The text colour class an icon should take from its container.
 *
 * Native-only machinery. On web an `<svg>` picks up `currentColor` from its
 * parent, including hover states, so `icons.web.tsx` ignores this entirely —
 * pinning an explicit colour on the icon there would freeze it through the
 * container's `hover:text-*`. Native has no inheritance at all, so a container
 * that sets its own text colour (a `Button` variant, a destructive row)
 * publishes that class here and every icon below merges it in.
 *
 * Merged *before* the icon's own `className`, so an explicit `text-*` at the
 * call site still wins.
 */
export const IconClassContext = createContext<string | undefined>(undefined);
```

`icons.tsx` (native) wraps each icon in `cssInterop` and resolves colour eagerly.
Two rules from its docblock generalize:

- **Import from the deep path, never the barrel.** `lucide-react-native/icons/archive`,
  not `lucide-react-native`. The barrel re-exports 1600-odd modules and **Metro
  does not tree-shake**, so one barrel import pulls the whole set into the bundle.
- **Re-export through one module** rather than importing lucide at each call site.
  Several lucide names are reachable under deprecated legacy aliases
  (`AlertCircle`, `CheckCircle2`, `Loader2`); centralizing means the next lucide
  bump is one file, not a rename sweep across 37.

`icons.web.tsx` is a plain re-export from the barrel — web bundlers do tree-shake,
and an `<svg>` already takes `className` and inherits `currentColor`.

## Route-level variants

Whole screens can vary the same way: `todo-lists.tsx` and
`todo-lists.native.tsx`. Use it when the *information architecture* differs — a
web table versus a native list-and-detail push — not merely when the styling
does. Styling differences are what responsive classes and `Platform.select` are
for; a second route file is a second thing to keep in step.

Layouts branch inline instead, since the divergence is structural and lives in
one file:

```tsx
export default function AppLayout() {
  if (Platform.OS === 'web') return <WebLayout />;
  return <NativeLayout />;
}
```

## Never touch web globals directly

`window`, `document`, and `localStorage` do not exist on native. Any of them
outside a `Platform.OS === 'web'` guard is a crash on device.

Everything that needs persistence goes through **one** wrapper:

```typescript
import { Platform } from 'react-native';

// Synchronous wrapper on web (localStorage); async storage swap point for native.
export const storage = {
  getItem(key: string): string | null {
    if (Platform.OS === 'web') return window.localStorage.getItem(key);
    return null;
  },
  setItem(key: string, value: string): void {
    if (Platform.OS === 'web') window.localStorage.setItem(key, value);
  },
  removeItem(key: string): void {
    if (Platform.OS === 'web') window.localStorage.removeItem(key);
  },
};
```

The interface is deliberately **synchronous** so callers (the Apollo link, the
route guards) need no `await`. Backing it with `AsyncStorage` on native means
hydrating into an in-memory map at startup and writing through — not changing
the signature, which would ripple through every caller.

For URL and protocol work, derive from `Platform.OS` first and fall back:

```typescript
function buildWsUrl(): string {
  if (API_URL) {
    return `${API_URL.replace(/^http/, 'ws')}/graphql`;
  }
  if (Platform.OS === 'web' && typeof window !== 'undefined') {
    const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${proto}//${window.location.host}/graphql`;
  }
  // Fallback for native dev without explicit API_URL
  return 'ws://localhost:3001/graphql';
}
```

Note the belt-and-braces `typeof window !== 'undefined'` alongside the
`Platform.OS` check — this code also runs during a static web export, where
neither is guaranteed.
