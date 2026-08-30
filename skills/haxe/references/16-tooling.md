<!--label:tooling-->
## Tooling: LSP, Diagnostics & Fast Feedback

Haxe's editor intelligence (completion, go-to-definition, diagnostics) is powered by
the **compiler itself**, not a separate parser. The same display services that back
the language server are available from the command line, so an agent can get the
*exact* type information and errors the compiler sees instead of guessing.

<!--label:tooling-verify-->
### Always verify with the compiler

**Do not trust hand-reasoning about whether Haxe code type-checks — ask the compiler.**
After writing or editing `.hx` code, run a type-check before claiming it works:

```
haxe build.hxml --no-output
```

`--no-output` compiles and type-checks but generates no target files — the fastest way
to surface type errors, unification failures, and missing fields. Only do a full build
(`haxe build.hxml`) + run when you need to verify runtime behavior. See
`references/07-compiler-usage.md` for `--no-output` and `references/13-debugging.md`
for diagnosing what it reports.

<!--label:tooling-lsp-tool-->
### Use a code-intelligence tool when your agent has one

Some agent harnesses expose a language-server / code-intelligence tool (for example a
`LSP` tool backed by a Haxe language server, which may need enabling in that harness's
own configuration). **When such a tool is available, prefer it** for code intelligence
— it gives accurate, compiler-backed answers without parsing CLI output. Typical
operations, whatever the harness calls them:

- `hover` — type/signature/docs for a symbol
- `goToDefinition` / `goToImplementation` — locate a symbol or its implementors
- `findReferences` — every use of a symbol
- `documentSymbol` / `workspaceSymbol` — outline a file or search the project
- `prepareCallHierarchy` / `incomingCalls` / `outgoingCalls` — call relationships

Such tools normally report **1-based line and character** positions (as shown in the
editor), unlike the raw `--display` byte offsets below.

**If your harness has no such tool — or it errors, does not cover `.hx`, or lacks a
mode you need such as `@diagnostics` — use the CLI display services below.** They are
the portable path: they need nothing but the `haxe` binary and work in any agent, any
editor, and any shell. Everything a language server reports is reproducible from them.

> Regardless of which you use, type-checking (`haxe build.hxml --no-output`) is still
> the authority on whether code compiles — code intelligence answers "what is this?",
> the compiler answers "does it build?".

<!--label:tooling-lsp-->
### The Haxe language server (for the user's editor)

When the user works in an editor, recommend the official Haxe language server rather
than relying on generic syntax highlighting:

- **VS Code**: the [vshaxe](https://marketplace.visualstudio.com/items?itemName=nadako.vshaxe)
  extension bundles [`haxe-language-server`](https://github.com/vshaxe/haxe-language-server).
- **Other editors** (Vim/Neovim, Helix, Emacs, Sublime): point their LSP client at the
  `haxe-language-server` binary, which speaks LSP over `--wait stdio`.
- It requires **Haxe 3.4.0+** and a valid `.hxml` (or `haxe.json`) so it knows the
  classpath, target, and libraries. If completion/diagnostics are wrong, the usual
  cause is the wrong or missing build file — fix the `.hxml` first.

The language server only wraps the compiler display API below; everything it reports
is reproducible from the CLI.

<!--label:tooling-display-->
### Display services from the CLI

Use `--display file@bytePosition[@mode]` to query the compiler directly (the position
is a **byte** offset, not a character offset). Common modes — see
`references/08-cr-features.md` for full examples and output:

Mode | Command shape | Use
 --- | --- | ---
field | `haxe --display Main.hx@120` | Fields available on a type at a point
toplevel | `haxe --display Main.hx@120@toplevel` | Identifiers/types in scope
usage | `haxe --display Main.hx@120@usage` | Find usages of a symbol
position | `haxe --display Main.hx@120@position` | Go-to-definition

Add `-D display-stdin` to feed unsaved buffer contents on stdin. JSON output (used by
editors) is available with the `--display`-`json` RPC protocol the language server uses.

<!--label:tooling-diagnostics-->
### Diagnostics mode (machine-readable errors/warnings)

The `@diagnostics` mode returns the file's errors, warnings, unused imports, and
unused-variable hints as JSON — useful when you want structured results instead of
parsing compiler text. Pass your build args so the classpath/target are correct, then
append the display query (the byte position is ignored for this mode, so `@0` is fine):

```
haxe build.hxml --display src/Main.hx@0@diagnostics
```

The output is a JSON array grouped by file. Each diagnostic carries a `kind`, a
`severity`, a `range` (1-based `line`/`character` for `start` and `end`), and `args`
with kind-specific detail:

```json
[
  {
    "file": "src/Main.hx",
    "diagnostics": [
      {
        "kind": 0,
        "severity": 1,
        "range": {
          "start": { "line": 6, "character": 9 },
          "end":   { "line": 6, "character": 17 }
        },
        "args": "Unknown identifier : helth"
      }
    ]
  }
]
```

`severity` follows the LSP convention: **1 = Error, 2 = Warning, 3 = Information,
4 = Hint**. The exact `kind` codes and `args` shape vary by diagnostic; treat the
example as the structure, not a fixed schema. For a one-off "does it compile" check,
`haxe build.hxml --no-output` is simpler — reach for `@diagnostics` when you need the
results as data (e.g. to act on a specific severity or range).

<!--label:tooling-server-->
### Completion/compilation server for speed

For repeated checks on a large project, start a persistent compilation server so the
compiler caches parsed files, haxelib lookups, and typed modules:

```
haxe -v --wait 6000
```

Then route builds and display queries through it instead of cold-starting each time:

```
haxe --connect 6000 build.hxml
```

This is the same caching the language server relies on; use it when iterating so each
type-check is near-instant. Details in `references/08-cr-features.md`
(Completion server).

<!--label:tooling-workflow-->
### Suggested agent workflow

1. Ensure a correct `.hxml` exists (classpath, `-main`, target, `-lib`s) — it drives
   both builds and the LSP.
2. For navigation/type lookups, use your agent's code-intelligence tool if it has
   one; otherwise use the CLI `--display`/completion server, which always works.
3. Edit `.hx`/`.hxml` following the references.
4. Type-check fast with `haxe build.hxml --no-output` (optionally via `--connect` to a
   running `--wait` server).
5. Fix reported errors; only then do a full build + run to verify behavior.
6. For the user's own editing, recommend installing the Haxe language server.
