# Forms

TanStack Form + zod, with the field components bound once through
`createFormHook` so a form body is a list of fields rather than a list of
render-prop closures.

## The shared field context

`components/ui/form-field.tsx` — created once per app:

```tsx
import { createFormHookContexts } from '@tanstack/react-form';
import { Field, FieldError, FieldLabel } from '@/components/ui/field';
import { Input } from '@/components/ui/input';

export const { fieldContext, useFieldContext, formContext, useFormContext } =
  createFormHookContexts();

export function TextField({ label, type = 'text' }: { label: string; type?: string }) {
  const field = useFieldContext<string>();
  const isInvalid = field.state.meta.isTouched && !field.state.meta.isValid;

  return (
    <Field data-invalid={isInvalid || undefined}>
      <FieldLabel htmlFor={field.name}>{label}</FieldLabel>
      <Input
        id={field.name}
        name={field.name}
        type={type}
        value={field.state.value}
        onBlur={field.handleBlur}
        onChange={(e) => field.handleChange(e.target.value)}
        aria-invalid={isInvalid}
      />
      {isInvalid && <FieldError errors={field.state.meta.errors} />}
    </Field>
  );
}

export function FormError({ formError }: { formError: string | null }) {
  if (!formError) {
    return null;
  }

  return (
    <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-3 text-red-800 text-sm">
      {formError}
    </div>
  );
}
```

`isTouched && !isValid` — not `!isValid` alone. An untouched empty required field
must not be red before the user has typed anything.

`htmlFor={field.name}` / `id={field.name}` wires the label to the input;
`aria-invalid` and `role="alert"` are what make the error reachable by a screen
reader. These are not decoration.

## A form

```tsx
import { createFormHook } from '@tanstack/react-form';
import { useState } from 'react';
import { z } from 'zod';
import type { CreateLabelInput as NewLabel } from '@/__generated__/graphql';
import { Button } from '@/components/ui/button';
import { FieldGroup } from '@/components/ui/field';
import { FormError, TextField, fieldContext, formContext } from '@/components/ui/form-field';

const labelSchema = z.object({
  label: z.string().min(1, 'Label is required.'),
  color: z
    .string()
    .min(1, 'Color is required.')
    .regex(/^#[0-9a-fA-F]{6}$/, 'Must be a valid hex color (e.g. #ff0000).'),
});

export const { useAppForm } = createFormHook({
  fieldComponents: { TextField },
  formComponents: {},
  fieldContext,
  formContext,
});

interface LabelFormProps {
  onSubmit: (value: NewLabel) => Promise<void>;
  onCancel: () => void;
}

export function LabelForm({ onSubmit, onCancel }: LabelFormProps) {
  const [formError, setFormError] = useState<string | null>(null);

  const form = useAppForm({
    defaultValues: { label: '', color: '#000000' },
    validators: { onSubmit: labelSchema },
    onSubmit: async ({ value }) => {
      setFormError(null);
      try {
        await onSubmit(value);
        form.reset();
      } catch (err: unknown) {
        setFormError(err instanceof Error ? err.message : 'An unexpected error occurred.');
      }
    },
  });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        form.handleSubmit();
      }}
    >
      <FieldGroup className="gap-4">
        <form.AppField name="label">{() => <TextField label="Label" />}</form.AppField>
        <form.AppField name="color">{() => <TextField label="Color" type="color" />}</form.AppField>

        <FormError formError={formError} />

        <div className="flex gap-2">
          <form.Subscribe selector={(state) => [state.canSubmit, state.isSubmitting]}>
            {([canSubmit, isSubmitting]) => (
              <Button type="submit" disabled={!canSubmit || isSubmitting}>
                {isSubmitting ? 'Creating...' : 'Create'}
              </Button>
            )}
          </form.Subscribe>
          <Button type="button" variant="outline" onClick={onCancel}>
            Cancel
          </Button>
        </div>
      </FieldGroup>
    </form>
  );
}
```

## Rules

**The form does not call the mutation.** It takes `onSubmit: (value) => Promise<void>`
and `onCancel: () => void`. The route component owns the mutation, the cache
update, and what happens next. This is what lets one form serve a page, a dialog,
and a test.

**Validate on submit, not on change.** `validators: { onSubmit: schema }`.
Validating every keystroke marks a field invalid while the user is still typing
it. Use `onChange` only where live feedback is genuinely the point (a password
strength meter, a slug preview).

**`form.Subscribe` around the submit button**, selecting only `canSubmit` and
`isSubmitting`. Reading `form.state` in the component body re-renders the entire
form on every keystroke.

**Reset only on success.** `form.reset()` goes inside the `try`, after the await.
Resetting in a `finally` discards what the user typed when the server rejected it.

**Server errors go to `FormError`,** not to a toast. The user is looking at the
form.

**Mirror the server's zod schema where one exists.** The client schema is for
immediate feedback; the server's is the one that decides. They will drift — a
test asserting the two agree is cheap, and the server-side drift test pattern is
in the `ts-testing` skill if it is available.

## Dialogs

A form in a dialog keeps the same contract; the dialog is the page's state:

```tsx
// route component
const [open, setOpen] = useState(false);

<Dialog open={open} onOpenChange={setOpen}>
  <DialogContent>
    <LabelForm
      onSubmit={async (value) => {
        await createLabel({ variables: { input: value } });
        setOpen(false);
      }}
      onCancel={() => setOpen(false)}
    />
  </DialogContent>
</Dialog>
```

Closing on success is the caller's job, inside `onSubmit`, after the await — so a
failed mutation leaves the dialog open with the error visible.
