# NativeWind and dark mode

## `tailwind.config.js`

```javascript
/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: ['class'],
  content: ['./app/**/*.{js,ts,jsx,tsx}', './src/**/*.{js,ts,jsx,tsx}'],
  presets: [require('nativewind/preset')],
  theme: {
    extend: {
      borderRadius: {
        lg: 'var(--radius)',
        md: 'calc(var(--radius) - 2px)',
        sm: 'calc(var(--radius) - 4px)',
      },
      colors: {
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: { DEFAULT: 'hsl(var(--primary))', foreground: 'hsl(var(--primary-foreground))' },
        secondary: { DEFAULT: 'hsl(var(--secondary))', foreground: 'hsl(var(--secondary-foreground))' },
        destructive: { DEFAULT: 'hsl(var(--destructive))', foreground: 'hsl(var(--destructive-foreground))' },
        muted: { DEFAULT: 'hsl(var(--muted))', foreground: 'hsl(var(--muted-foreground))' },
        accent: { DEFAULT: 'hsl(var(--accent))', foreground: 'hsl(var(--accent-foreground))' },
        popover: { DEFAULT: 'hsl(var(--popover))', foreground: 'hsl(var(--popover-foreground))' },
        card: { DEFAULT: 'hsl(var(--card))', foreground: 'hsl(var(--card-foreground))' },
      },
    },
  },
  plugins: [require('tailwindcss-animate')],
};
```

- **`presets: [require('nativewind/preset')]`** — without it, `className` on a
  React Native component does nothing.
- **`content` covers both `app/` and `src/`.** A class used only in a route file
  is missing from the bundle otherwise.
- **The DEFAULT/foreground colour pairs** are the shadcn token convention:
  `bg-primary text-primary-foreground` always reads correctly in both themes.

`global.css` is the nativewind input (`withNativeWind(config, { input: './global.css' })`):

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

Web token values live in `src/index.css` under `:root` and `.dark`.

## Tokens, never literal colours

Every component references semantic tokens — `bg-background`, `text-foreground`,
`text-muted-foreground`, `border-border`, `bg-card`. **A literal `bg-white` or
`text-gray-900` is a dark-mode bug by construction**, and it will not show up
until someone toggles the theme.

The exception is user-supplied colour (an activity type's hex), which is passed
as a style value, not a class.

## The dark-mode hook

```typescript
/**
 * Dark mode is a `dark` class on `<html>` plus a `theme` entry in storage.
 *
 * Both layouts need it — the root layout covers the unauthenticated `/auth`
 * screens, the app layout owns the header toggle — and each had grown its own
 * copy of the preference lookup, which is how they ended up disagreeing about
 * whether merely reading the OS preference should persist it.
 *
 * It does not: `theme` is written only by `setDark`, so an untouched account
 * keeps following the OS. The two hook instances never need to agree at
 * runtime, because whichever one is mounted applies the same class.
 */
function getInitialDark(): boolean {
  if (Platform.OS !== 'web') return false;
  const stored = storage.getItem('theme');
  if (stored) return stored === 'dark';
  return window.matchMedia('(prefers-color-scheme: dark)').matches;
}

export function useDarkMode() {
  const [dark, setDarkState] = useState(getInitialDark);

  useEffect(() => {
    if (Platform.OS !== 'web') return;
    document.documentElement.classList.toggle('dark', dark);
  }, [dark]);

  function setDark(next: boolean) {
    storage.setItem('theme', next ? 'dark' : 'light');
    setDarkState(next);
  }

  return [dark, setDark] as const;
}
```

Three things worth keeping:

**Reading the OS preference must not persist it.** `storage.setItem('theme', …)`
happens only in `setDark`. If merely reading wrote the value, an account that
never touched the toggle would be pinned to whatever the OS said the first time
the app loaded and would stop following it afterwards. This is the exact bug the
docblock records — two copies of the lookup disagreeing about it.

**Mount it in both layouts.** The root layout covers the `/auth` screens that sit
outside `(app)`; the app layout owns the toggle. Two instances are fine — they
apply the same class and never need to agree at runtime.

**Every web global is behind `Platform.OS !== 'web'`.** `window.matchMedia` and
`document.documentElement` both crash on device.

On native the hook returns `false` and does nothing. Wire native theming through
`useColorScheme` from `nativewind` when the app actually ships to a device;
keeping the same hook signature means no call site changes.

## `cn()`

```typescript
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

`twMerge` is what makes `className` overridable at the call site: a component
whose base classes include `px-4` accepts `px-8` from a caller and the later one
wins. Plain `clsx` alone emits both and lets CSS-order decide, which is
unpredictable across bundlers.

## Icon colour on native

Native has no `currentColor`, so icons cannot inherit a container's text colour
the way an `<svg>` does. The pattern is a context that containers publish into:

```typescript
export const IconClassContext = createContext<string | undefined>(undefined);
```

A `Button` variant or a destructive row sets it; every icon below merges it in
**before** its own `className`, so an explicit `text-*` at the call site still
wins. The web implementation ignores the context entirely — pinning a colour
there would freeze the icon through the container's `hover:text-*`.

Full detail in the platform-variants reference.
