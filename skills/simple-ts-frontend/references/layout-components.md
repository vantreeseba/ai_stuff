# Layout and zone components

Structural wrappers that own spacing, alignment, and scroll behaviour so pages
own only content. They live in `components/layouts/`.

**Prefer a layout component whenever it makes sense.** If a component renders a
header/body structure — a title with an action button above a list of items —
reach for `ListLayout` instead of hand-rolling `<div className="space-y-2">` and
`<div className="flex items-center justify-between">` inline. Consistent use
keeps every list page visually and structurally uniform, and makes a spacing
change a single-point edit rather than a sweep.

## The set

| Component | Shape | Use for |
| --- | --- | --- |
| `ListLayout` | `header` / scrolling `body` / optional `footer` | any page or panel that scrolls a list under a fixed heading |
| `FormListLayout` | conditional `form` above `list` | CRUD pages where "Add" reveals an inline form |
| `Header` / `BottomNav` | app chrome | the root shell |
| `SectionCard` | card with a title row and an action slot | a list section inside a detail page |

## `ListLayout`

```tsx
import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';

interface ListLayoutProps {
  header: ReactNode;
  body: ReactNode;
  footer?: ReactNode;
  className?: string;
  spacing?: boolean;
}

export function ListLayout({ header, body, footer, className, spacing = true }: ListLayoutProps) {
  return (
    <div className={cn('flex flex-col h-full pr-2', className)}>
      <div className="shrink-0 pb-3">{header}</div>
      <div className={cn('flex-1 overflow-y-auto min-h-0', spacing && 'space-y-2')}>{body}</div>
      {footer && <div className="shrink-0 pt-3 border-t">{footer}</div>}
    </div>
  );
}
```

**`min-h-0` on the scrolling child is not optional.** A flex child defaults to
`min-height: auto`, which means it refuses to shrink below its content — so the
`overflow-y-auto` never engages and the whole page scrolls instead of the list.
This is the single most common layout bug in this shape.

`shrink-0` on header and footer for the same reason in the other direction: they
must not be squeezed when the body is long.

`spacing` is a prop rather than a hardcoded class because a body of cards wants
`space-y-2` and a body of table rows wants none.

## `FormListLayout`

```tsx
interface FormListLayoutProps {
  form: ReactNode;
  list: ReactNode;
  showForm: boolean;
}

export function FormListLayout({ form, list, showForm }: FormListLayoutProps) {
  return (
    <div className="space-y-6">
      {showForm && form}
      {list}
    </div>
  );
}
```

Every CRUD page uses this: clicking "Add" sets `showForm = true`; submitting or
cancelling sets it back. The state lives in the **route component**, not in the
list.

## Add-button placement

Every list section on a detail page — Tags, Important Dates, Notes,
Relationships — follows one pattern:

```tsx
<Card>
  <CardContent className="p-4 space-y-3">
    <div className="flex items-center justify-between">
      <h2 className="font-semibold text-base">Section Title</h2>
      <Button size="sm" variant="outline" onClick={() => setDialogOpen(true)}>
        <SomeIcon className="mr-1.5 h-4 w-4" />
        Add Item
      </Button>
    </div>
    <SectionList createOpen={dialogOpen} onCreateOpenChange={setDialogOpen} />
  </CardContent>
</Card>
```

Rules:

- **The "Add" button lives in the card header row**, right-aligned, never inside
  the list component itself.
- **Dialog open state is owned by the page** (the route component), not the list.
- **The list receives `createOpen: boolean` and `onCreateOpenChange:
  (open: boolean) => void`** and renders the `<Dialog>` internally — keeping the
  Dialog markup co-located with the form it opens.
- **If every item is already added** (all tags attached, say), wrap the `Button`
  in a `<Tooltip>` and disable it, explaining why. Never hide it.

The result is that the add affordance is in the same place relative to the
section title on every page, which is the whole point.

## App shell

`routes/__root.tsx` renders the chrome and an `<Outlet />`. Navigation items are
a const array with an `isActive` predicate per item, so an item's active rule
lives next to the item rather than in a chain of `pathname.startsWith` calls
scattered through the header:

```tsx
const NAV_ITEMS = [
  { href: '/', label: 'Dashboard', icon: Home, isActive: (p: string) => p === '/' },
  { href: '/persons', label: 'People', icon: Users, isActive: (p: string) => p.startsWith('/persons') },
] as const;
```

Both the desktop nav and the mobile tab bar map the same array. Adding a
destination is one entry, not two.

Responsive split: desktop nav is `hidden md:flex`, the bottom tab bar is
`md:hidden fixed inset-x-0 bottom-0`. The tab bar carries
`pb-[env(safe-area-inset-bottom)]` so it clears the home indicator on iOS Safari.

```tsx
aria-current={active ? 'page' : undefined}
```

on every nav link. It is the accessible signal for "you are here", and it costs
one attribute.

## Writing a new layout component

1. It takes `ReactNode` slots, never renders domain content itself.
2. It owns spacing, alignment, and overflow — nothing else.
3. It takes `className` and merges with `cn()`, so a caller can adjust without
   forking it.
4. Booleans that toggle a structural class (`spacing`) are props with defaults,
   not variants.
5. If two pages hand-roll the same wrapper twice, that is the signal to extract
   it — not before.
