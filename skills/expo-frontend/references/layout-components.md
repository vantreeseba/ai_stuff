# Layout and zone components

Structural wrappers in `src/components/ui/` that own spacing, scroll, and
alignment so screens own only content. Reach for one rather than hand-rolling
`<div className="flex items-center justify-between">` inline — consistency across
screens, and a spacing change becomes a single edit.

| Component | Slot shape | Use for |
| --- | --- | --- |
| `Page` | `children`, `fill`, `scroll`, `width` | the shell every route wraps its content in |
| `PageHeader` | `title`, `subtitle`, `actions` | the title row at the top of a list screen |
| `CardGrid` | `children` | the responsive 1→2→3→4 column grid |
| `EmptyState` | `icon`, `title`, `description`, `action` | a list with nothing in it |
| `DetailPage` | `entity`, `loading`, `notFoundLabel`, `children(entity)` | a detail route's shell + guard |
| `DetailHeader` | `onBack`, `title`, `badge`, `subtitle`, `actions` | the back/title/actions row on a detail view |
| `SectionHeading` | `variant`, `children` | a small muted heading above a section |
| `QueryState` | `loading`, `error` | inline loading/error text beside data that still renders |
| `FormDialog` + `FormDialogFooter` | `open`, `title`, `children` | every form dialog's chrome |
| `ConfirmDialog` | `open`, `title`, `description`, `onConfirm` | destructive-action confirmation |

## `Page`

```tsx
type PageProps = {
  className?: string;
  children: ReactNode;
  /**
   * Full-height flex column (`h-full min-h-0 flex-col`) instead of the default
   * `flex-1`. Use for views whose body scrolls internally (calendar, today).
   */
  fill?: boolean;
  /** Whether the page itself scrolls. Off for views with an inner scroll area. */
  scroll?: boolean;
  /** `narrow` constrains content to `max-w-2xl` (settings, import). */
  width?: 'narrow';
};

export function Page({ className, children, fill = false, scroll = true, width }: PageProps) {
  return (
    <div
      className={cn(
        'container mx-auto px-4 py-6',
        fill ? 'flex h-full min-h-0 flex-col' : 'flex-1',
        scroll && 'overflow-y-auto',
        width === 'narrow' && 'max-w-2xl',
        className,
      )}
    >
      {children}
    </div>
  );
}
```

**`fill` versus the default `flex-1` is the distinction to get right.**

- Default (`flex-1`) — the page grows to fill its parent and, with `scroll`,
  scrolls as one document. This is what a list screen wants.
- `fill` (`h-full min-h-0 flex-col`) — the page is a fixed-height flex column
  whose *child* scrolls. This is what a calendar or a split view wants.

`min-h-0` comes with `fill` for the usual reason: a flex child defaults to
`min-height: auto` and refuses to shrink below its content, so an inner
`overflow-y-auto` never engages and the outer container scrolls instead. Getting
this wrong produces a page that scrolls when only the list should.

Pass `scroll={false}` whenever the body has its own scroll area — two nested
scrollers is a worse bug than none.

## `PageHeader`, `CardGrid`, `EmptyState`

```tsx
export function PageHeader({ title, subtitle, actions, className }: PageHeaderProps) {
  return (
    <div className={cn('mb-4 flex items-center justify-between gap-3', className)}>
      <div>
        <h2 className="text-xl font-semibold">{title}</h2>
        {subtitle ? <p className="text-sm text-muted-foreground">{subtitle}</p> : null}
      </div>
      {actions ? <div className="flex items-center gap-3">{actions}</div> : null}
    </div>
  );
}

// The responsive card grid (1 → 2 → 3 → 4 columns) shared by list pages.
export function CardGrid({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <div
      className={cn('grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4', className)}
    >
      {children}
    </div>
  );
}

// The centered icon / title / description / action shown when a list is empty.
export function EmptyState({ icon: Icon, title, description, action }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center gap-3 py-10 text-center">
      <div className="rounded-full bg-muted p-3">
        <Icon className="h-6 w-6 text-muted-foreground" />
      </div>
      <div>
        <p className="font-medium text-sm">{title}</p>
        {description ? <p className="text-sm text-muted-foreground">{description}</p> : null}
      </div>
      {action}
    </div>
  );
}
```

`EmptyState` takes `icon: IconComponent` — the type from `icons-base.ts`, which
is the part the native and web icon implementations have in common. Never type an
icon prop as a concrete lucide type; it will not resolve on the other platform.

**Every list screen renders an `EmptyState`, with the primary action in it.** A
blank screen is a bug.

A typical list screen is then just:

```tsx
<Page>
  <PageHeader title="Habits" actions={<Button onPress={openCreate}>New habit</Button>} />
  <QueryState loading={loading} error={error} />
  {habits.length === 0 ? (
    <EmptyState icon={Repeat} title="No habits yet" action={<Button onPress={openCreate}>Create one</Button>} />
  ) : (
    <CardGrid>{habits.map((h) => <HabitCard key={h.id} habit={h} />)}</CardGrid>
  )}
</Page>
```

## `DetailPage` and `DetailHeader`

`DetailPage` folds the shell and the loading/not-found guard together, and uses a
render prop so the entity is non-null inside:

```tsx
type DetailPageProps<T> = {
  /** The loaded entity, or null/undefined while loading or when missing. */
  entity: T | null | undefined;
  loading?: boolean;
  /** Shown when the entity is absent and not loading. */
  notFoundLabel: string;
  className?: string;
  /** Rendered only once the entity is present, so it is non-null inside. */
  children: (entity: T) => ReactNode;
};

export function DetailPage<T>({ entity, loading, notFoundLabel, className, children }: DetailPageProps<T>) {
  return (
    <Page {...(className ? { className } : {})}>
      {entity ? (
        children(entity)
      ) : (
        <p className="text-muted-foreground">{loading ? 'Loading…' : notFoundLabel}</p>
      )}
    </Page>
  );
}
```

The render prop is the point: it removes the `if (!entity) return null` and the
`entity!` from every detail route.

`DetailHeader` composes back button + optional colour dot + title + badge +
subtitle + actions. The `aria-label` on the back button is not optional — it is
an icon-only control.

## `QueryState`

```tsx
// Inline loading / error text for a query whose data may still render
// alongside it. Renders the error (priority) or the loading line, else null.
export function QueryState({ loading, error, loadingLabel = 'Loading…', errorLabel = 'Error' }: {
  loading?: boolean | undefined;
  error?: { message: string } | null | undefined;
  loadingLabel?: string;
  errorLabel?: string;
}) {
  if (error) {
    return <p className="text-sm text-destructive">{errorLabel}: {error.message}</p>;
  }
  if (loading) {
    return <p className="text-sm text-muted-foreground">{loadingLabel}</p>;
  }
  return null;
}
```

Designed for `cache-and-network`: it renders *alongside* data that is already on
screen, rather than replacing it. Error takes priority over loading — a failed
background refetch should say so, not show a spinner forever.

## Dialogs

`FormDialog` owns the chrome; the caller owns the form body and the footer:

```tsx
// Dialog chrome shared by every form dialog: Dialog + sized content + header.
// The caller keeps ownership of the <form.AppForm><Form>…</Form> body and the
// footer (via FormDialogFooter) — TanStack's form generics make wrapping the
// form itself more trouble than it saves.
```

That comment records a real decision: wrapping the `<form>` too was tried and
abandoned because TanStack Form's generics do not survive the indirection. When a
wrapper would have to fight a library's type inference, wrap the chrome and stop.

`FormDialogFooter` handles the server-error slot:

```tsx
/**
 * A rejected mutation's message, shown above the buttons. Field validation
 * stays inline beneath its field — this is for what only the server knows,
 * such as a delete the database refuses (`onDelete: 'restrict'`).
 */
error?: string | null;
```

Two error channels with a clear split: **field validation renders under its
field, server rejections render above the buttons.** Mixing them means the user
hunts for the message.

`ConfirmDialog` for every destructive action — `variant="destructive"` on the
confirm button, `loading` disabling it while in flight.

## Buttons take `onPress`, not `onClick`

Cross-platform components use React Native's event name. `onClick` silently does
nothing on native, and it is easy to type out of web habit. If a component takes
`onPress`, it is cross-platform; if it takes `onClick`, it is web-only and belongs
behind a platform variant.

## Writing a new one

1. `ReactNode` slots, no domain content.
2. Owns spacing, alignment, and overflow — nothing else.
3. Takes `className`, merges with `cn()`.
4. Structural toggles are props with defaults (`fill`, `scroll`, `width`), not
   variants.
5. Icon props are typed `IconComponent` from `icons-base.ts`.
6. Extract when two screens hand-roll the same wrapper — not before.
