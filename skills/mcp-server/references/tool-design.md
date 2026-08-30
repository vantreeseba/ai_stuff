# Tool design

**Every tool is a new blast radius over someone's real data.** Build what is
specified; nothing speculative. Check `TODO_IDEAS.md` before proposing one — the
idea may already have been rejected for a reason that still holds.

## ToolDefinition

Tools are declared as data and registered in one loop, so the write gate and the
annotations are applied uniformly rather than per tool.

```typescript
import type { ZodRawShape } from 'zod';

/**
 * One MCP tool: its schema, whether it mutates, and its handler.
 *
 * `write` is the single gate — when `ACTUAL_ENABLE_WRITES` is off, write tools
 * are not registered at all, so they never appear in `tools/list`. An agent
 * should never see a tool it cannot call.
 */
export interface ToolDefinition<Args extends ZodRawShape = ZodRawShape> {
  name: string;
  title: string;
  description: string;
  /** Zod raw shape; the SDK converts it to JSON Schema and validates calls against it. */
  inputSchema: Args;
  /** True for anything that changes state. Governs registration, and the annotations below. */
  write?: boolean;
  /**
   * Set when calling the tool twice with the same arguments leaves the same
   * state (e.g. setting a budget amount). Omit for tools where a second call
   * compounds — merges, holds. Ignored for read tools, which are always
   * idempotent.
   */
  idempotent?: boolean;
  /**
   * Set when the tool overwrites or removes existing data, as opposed to only
   * adding to it. This is **not** the inverse of {@link idempotent}: replacing
   * a note wholesale is idempotent *and* destructive, while creating a payee is
   * neither. MCP clients may auto-approve non-destructive tools, so deriving
   * this from idempotency would wave through every in-place overwrite.
   */
  destructive?: boolean;
  /** Returns the value to serialize as the tool result. Throwing yields a tool error, not a transport error. */
  run: (args: Record<string, unknown>) => Promise<unknown>;
}

/** Build a tool definition, preserving the literal type of its input schema. */
export function defineTool<Args extends ZodRawShape>(definition: ToolDefinition<Args>): ToolDefinition<Args> {
  return definition;
}
```

`defineTool` exists purely to keep the literal type of `inputSchema` — an
annotated `const x: ToolDefinition = {…}` would widen it to `ZodRawShape` and
lose the argument types inside `run`.

## The write gate

```typescript
/** Every tool this server can serve, before the write gate is applied. */
export function allTools(repos: Repos, enableWrites = true): ToolDefinition[] {
  return [
    ...accountTools(repos),
    ...transactionTools(repos),
    // `preview_rule_effects` is a read tool that can nonetheless insert a payee,
    // so it needs to know whether writing is permitted at all.
    ...ruleTools(repos, enableWrites),
  ] as ToolDefinition[];
}

/** The tools actually served, given the write gate. */
export function enabledTools(repos: Repos, enableWrites: boolean): ToolDefinition[] {
  const tools = allTools(repos, enableWrites);
  return enableWrites ? tools : tools.filter((tool) => !tool.write);
}
```

One gate, `<NAME>_ENABLE_WRITES`, governing every mutating tool. **There is no
second destructive tier** — deletes are ordinary writes. Splitting the gate
produces a matrix nobody can reason about at deploy time.

Filtering rather than rejecting at call time is the point: a tool an agent can
see is a tool it will try, and a refusal it cannot fix wastes a turn and reads
as a bug.

## Registration

```typescript
export function createActualServer(deps: ServerDeps): McpServer {
  const server = new McpServer({ name: 'mcp-actual', version: SERVER_VERSION });

  for (const tool of enabledTools(deps.repos, deps.enableWrites)) {
    // An empty raw shape still registers a schema that rejects a call carrying
    // no `arguments` at all, which is exactly how clients invoke no-arg tools —
    // so omit the schema entirely rather than declaring an empty one.
    const hasInputs = Object.keys(tool.inputSchema).length > 0;
    server.registerTool(
      tool.name,
      {
        title: tool.title,
        description: tool.description,
        ...(hasInputs ? { inputSchema: tool.inputSchema } : {}),
        annotations: {
          readOnlyHint: !tool.write,
          // Declared per tool, not derived from idempotency: MCP defines
          // destructive as "may overwrite or remove" versus "only adds", which
          // is orthogonal. `update_note` is idempotent and destructive;
          // `create_payee` is neither.
          destructiveHint: Boolean(tool.write) && Boolean(tool.destructive),
          idempotentHint: !tool.write || Boolean(tool.idempotent),
          // Every tool talks to an external server.
          openWorldHint: true,
        },
      },
      async (args: Record<string, unknown>) => {
        try {
          const result = await tool.run(args ?? {});
          return { content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }] };
        } catch (err) {
          // Surface upstream/network failures as a readable tool error the agent
          // can act on, not a transport-level exception.
          return { content: [{ type: 'text' as const, text: errorChainMessage(err) }], isError: true };
        }
      },
    );
  }

  return server;
}
```

Three things here are worth keeping verbatim:

- **Omit `inputSchema` for a no-arg tool.** An empty raw shape registers a
  schema that rejects a call carrying no `arguments` at all — which is exactly
  how clients invoke no-arg tools.
- **`isError: true`, not a thrown exception.** A thrown error is a transport
  failure the agent cannot see or act on. `errorChainMessage` walks the `cause`
  chain so the agent gets "could not reach the sync server: ECONNREFUSED", not
  "Error".
- **The annotation triple is orthogonal, not derived.** `readOnlyHint` falls out
  of `write`, but destructive and idempotent do not imply each other, and
  clients auto-approve on them.

## Prompts

Prompts are **not write-gated**: they cannot change anything, and a read-only
server is where an agent most needs the workflow to tell it so. Each renders
against the gate (`{ enableWrites }` in its context) instead of being withheld
by it.

One SDK wart worth knowing:

```typescript
/**
 * Rebuild a prompt's argument schema so a request omitting `arguments`
 * altogether still validates.
 *
 * Every prompt argument is optional, but `registerPrompt` wraps the shape with
 * `objectFromShape` and then parses `request.params.arguments` against it —
 * and `z.object(...)` rejects `undefined` outright. A client invoking a prompt
 * bare, the most natural way to use one, would get "Required" instead of the
 * prompt. `.default({})` fixes the parse but hides `.shape`, which the SDK
 * reads to advertise the arguments in `prompts/list`, so the shape is
 * re-attached. Applied *after* registration because `registerPrompt` re-wraps
 * whatever it is given.
 *
 * The prompt tests cover both halves, so an SDK upgrade that makes this
 * unnecessary — or breaks it — fails loudly rather than silently.
 */
function tolerateMissingArguments(shape: ZodRawShape) {
  return Object.assign(z.object(shape).default({}), { shape });
}
```

The pattern generalizes: when you work around an SDK bug, **test both halves of
the workaround**, so the upgrade that fixes it fails loudly.

## Data rules

- **All upstream access goes through the one wrapped client.** Never import the
  upstream library outside `src/<domain>/`. A new tool adds a repo method.
- **Sync before you read** when other clients write to the same store.
- **Money is integer minor units.** Never float math. Return a decimal alongside
  the integer for readability, but never *accept* one — float money input is a
  correctness trap.

  ```typescript
  /**
   * Render an integer cent amount as a Money pair. Conversion happens exactly
   * once, at the boundary — everything upstream sums integers, because float
   * arithmetic on money silently loses cents.
   */
  export function money(amount: number): Money {
    return { amount, amountDecimal: api.utils.integerToAmount(amount) };
  }
  ```

- Describe tools from the schema or the source of truth where possible, so the
  description cannot drift from the behaviour.
- Return JSON, pretty-printed. An agent reads it; a human debugging it reads it
  too.

## Fronting a GraphQL schema

`@cubicecho/graphql-mcp` turns a GraphQL schema into an MCP server: each
query/mutation becomes a tool, described from the SDL. Mount it on the **same
schema object** the `/graphql` endpoint serves, beside it on the same port —
that is what makes the two surfaces provably the same API rather than two that
are meant to agree.

Default to **reads only**. Mutations become tools just as happily; that is a
deliberate decision per project, not a default.

## The shared/ package

On servers that ship a web UI, **`shared/` is the contract**. Config shapes,
upstream API responses, and REST DTOs are zod schemas in `shared/src/`; the
server validates at every boundary and the app imports the inferred types.
Never duplicate a shape — extend the schema and let the types flow.

```typescript
export type ServerConfig = z.infer<typeof serverConfigSchema>;
```

```typescript
const input = installRequestSchema.parse(req.body); // throws → 400 via error middleware
```

Never swallow an error — rethrow with `{ cause }` and a message naming what
failed.
