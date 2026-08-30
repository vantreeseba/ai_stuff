# Onboarding

A first-run flow that has to survive three things: a fresh device, an existing
account signing in on a *new* device, and someone who wants to run it again.

## The guard

In `app/(app)/_layout.tsx`, next to the other segment guards:

```tsx
export default function AppLayout() {
  const pathname = usePathname();
  useLiveUpdates();
  const onboardingDone = storage.getItem('onboarding_done');

  if (!onboardingDone && !pathname.startsWith('/onboarding')) {
    return <Redirect href="/onboarding" />;
  }

  if (Platform.OS === 'web') return <WebLayout />;
  return <NativeLayout />;
}
```

The `!pathname.startsWith('/onboarding')` half is what stops the redirect loop.
Every layout guard needs its own version of that escape.

The nav chrome hides itself during onboarding rather than the route rendering
outside the layout:

```tsx
const isOnboarding = pathname.startsWith('/onboarding');
...
{!isOnboarding && <header>…</header>}
```

Keeping the route inside `(app)` means it still gets the Apollo provider, the
error boundary, and the auth guard. A sibling route outside the group would need
all three again.

## The local flag is a cache, not the truth

`onboarding_done` lives in local storage, which is per-device. The same account
on a second device has an empty flag and would be sent through setup again — with
data already on the server.

So the first step **asks the server** and self-heals:

```tsx
const CHECK_ONBOARDED = graphql(`
  query CheckOnboarded {
    myActivityTypes { id }
  }
`);

export default function OnboardingPage() {
  const router = useRouter();
  const params = useLocalSearchParams<{ step?: string; force?: string }>();
  const step = Math.max(1, Math.min(4, Number(params.step ?? 1)));
  const force = params.force === 'true';
  const checked = useRef(false);

  const { data, loading } = useQuery(CHECK_ONBOARDED, {
    skip: step > 1 || force,
    fetchPolicy: 'network-only',
  });

  useEffect(() => {
    if (checked.current || loading || step > 1 || force) return;
    if (data && data.myActivityTypes.length > 0) {
      checked.current = true;
      storage.setItem('onboarding_done', '1');
      router.replace('/today');
    }
  }, [data, loading, step, force, router]);

  if (step === 1 && loading) {
    return (
      <div className="flex flex-1 items-center justify-center">
        <p className="text-muted-foreground text-sm">Checking setup…</p>
      </div>
    );
  }
  ...
}
```

Four details, each load-bearing:

- **`fetchPolicy: 'network-only'`** — a cached answer would defeat the check on
  the device where it matters most.
- **`skip: step > 1 || force`** — only ask on entry, not on every step.
- **`checked.current`** — a `useRef` latch so the redirect fires once. Without
  it, a re-render before navigation completes fires `router.replace` again.
- **`router.replace`, never `push`** — the user must not be able to back-swipe
  into onboarding they just escaped.

The probe is a *cheap existence query* (`myActivityTypes { id }`), not a
dedicated `hasOnboarded` field. It needs no server work and stays correct if the
definition of "set up" changes.

## Steps in the URL

```tsx
const step = Math.max(1, Math.min(4, Number(params.step ?? 1)));

function goToStep(s: number) {
  router.push({ pathname: '/onboarding', params: { step: String(s) } });
}
```

Step number in the query string, not in component state:

- refresh, deep link, and back-button all work with no extra code
- `Math.max(1, Math.min(4, …))` clamps, so `?step=99` and `?step=abc` land on a
  valid step instead of a blank screen
- `router.push` between steps means the platform back gesture goes back a step

`?force=true` re-runs the flow for someone who already finished — a settings link
points at it, and it skips the "already set up" probe.

## Steps are components, the route is a shell

```
components/domain/onboarding/
  StepActivityTypes.tsx
  StepTimeBlocks.tsx
  StepHabits.tsx
  StepTodos.tsx
```

```tsx
const STEPS = [
  { label: 'Activity Types' },
  { label: 'Time Blocks' },
  { label: 'Habits' },
  { label: 'Todos' },
] as const;
```

The route owns the shell — progress indicator, back/next/skip — and each step
owns its own queries, mutations, and validation. Reordering the flow is a change
to `STEPS`; a step is testable on its own.

## Finishing and skipping do the same thing

```tsx
function handleFinish() {
  storage.setItem('onboarding_done', '1');
  router.replace('/today');
}

function handleSkipAll() {
  storage.setItem('onboarding_done', '1');
  router.replace('/today');
}
```

**Skip must set the flag.** A skip that leaves it unset traps the user in the
loop on the next launch. Two identically-bodied functions is the right call here
— the intents differ, so keeping them separate leaves room for analytics or a
confirmation on one without touching the other.

Every step is skippable, and each writes its data as it goes rather than
accumulating a draft to submit at the end. Someone who abandons at step 3 keeps
what steps 1 and 2 created.
