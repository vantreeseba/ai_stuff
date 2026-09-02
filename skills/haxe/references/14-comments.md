<!--label:comments-->
## Comments & Documentation

Haxe has two comment forms and a dedicated *documentation comment* form built on
top of them. Documentation comments are understood by the compiler, `haxedoc`,
language servers (for hover/autocomplete), and the `dox` documentation generator,
so they are not "just comments" — they become part of the API surface.

<!--label:comments-syntax-->
### Comment syntax

- **Single-line comment** — `//` to end of line. Use for implementation notes,
  rationale, and `TODO`/`FIXME` markers that should *not* surface in generated docs.

  ```haxe
  // Implementation goes here
  return true;
  ```

- **Multi-line (block) comment** — `/* ... */`. Does not nest. Use for temporarily
  disabling code or for longer internal notes.

  ```haxe
  /* this whole block is internal,
     not part of the public docs */
  ```

- **Documentation comment** — a block comment whose opening is `/**`. This is the
  only comment form the compiler treats as documentation. It may be closed with
  either `*/` or `**/`; both are accepted.

<!--label:comments-doc-->
### Documentation comments

A documentation comment must immediately precede the declaration it documents — a
type (class, interface, enum, abstract, typedef), a field (var/function), an enum
constructor, or a function argument. Place it directly above the declaration with
no blank line between.

```haxe
/**
The `Player` class represents a game entity with health and movement.
**/
class Player {
    /** The player's current health. **/
    public var health:Int;

    /**
    Moves the player to a new set of coordinates.

    @param x The target X coordinate.
    @param y The target Y coordinate.
    @return True if the player successfully moved, false otherwise.
    **/
    public function move(x:Float, y:Float):Bool {
        // Implementation goes here
        return true;
    }
}
```

Conventions shown above:

- **Prefer the plain style — no leading `*` on each line.** Write the text directly
  inside `/** ... **/` as shown, rather than the JSDoc-style ` * ` prefix on every
  line. The leading-asterisk style is also accepted (the parser strips a leading
  `*`), but the plain style is recommended here: it is less visual noise and easier
  to edit. Single-line doc comments (`/** ... **/`) remain idiomatic for short field
  descriptions.
- **First sentence is the summary.** Tools use the opening sentence as the short
  description in lists and hover tooltips, so lead with a concise one-liner.
- **Document the contract, not the implementation.** Say what `move` returns and
  when, not how it computes it. Implementation detail belongs in `//` comments
  inside the body.

<!--label:comments-markup-->
### Markup inside doc comments

- **Markdown** is supported by `dox` and most language servers — use it for
  emphasis, lists, and links.
- **Inline code** uses backticks: `` `Player` ``, `` `health` ``. Reference
  types, fields, and arguments in backticks so they render distinctly.
- **Code blocks** use fenced triple backticks, optionally tagged `haxe`:

  ````haxe
  /**
  Example:
  ```haxe
  var p = new Player();
  p.move(10, 20);
  ```
  **/
  ````

<!--label:comments-tags-->
### Javadoc-style tags

Haxe doc comments support Javadoc-style `@` tags. The common ones:

Tag | Use
 --- | ---
`@param <name> <desc>` | Documents one function argument. Use the exact argument name; one `@param` per argument.
`@return <desc>` | Documents the return value. Omit for `Void` functions.
`@throws <Type> <desc>` | Documents an exception/error condition the function may raise.
`@see <ref>` | Points to a related type or field.
`@deprecated <desc>` | Notes that the field/type should no longer be used (pairs well with the `@:deprecated` metadata, which produces an actual compiler warning).

```haxe
/**
Moves the player to a new set of coordinates.

@param x The target X coordinate.
@param y The target Y coordinate.
@return True if the player successfully moved, false otherwise.
**/
```

> Note: tags are a documentation convention consumed by doc tooling — they are not
> type-checked. Keep `@param` names in sync with the signature manually; renaming an
> argument does not update its `@param`.

<!--label:comments-vs-metadata-->
### Doc comments vs. metadata

Do not confuse documentation comments with **metadata** (`@:` expressions such as
`@:deprecated`, `@:noCompletion`, `@:keep`). Metadata changes how the compiler
treats the declaration; doc comments only describe it. They are complementary:

```haxe
/**
Old movement API.

@deprecated Use `moveTo` instead.
**/
@:deprecated("Player.move is deprecated, use moveTo")
public function move(x:Float, y:Float):Bool { ... }
```

(See `references/generated/metas.md` for the metadata catalog.)

<!--label:comments-guidelines-->
### Guidelines for good comments

0. **Prefer single-line comments when possible.** For short notes — including
   short field/type descriptions — favor a concise comment over a multi-line block.
   Reserve full multi-line doc comments for cases that genuinely need them: most
   importantly, **functions, which should always carry `@param` and `@return`
   documentation** in the form shown above. So: lean on `//` and one-line `/** ... */`
   broadly, but never drop the structured param/return docs on functions.

   ```haxe
   /** The player's current health. **/   // short → single line, good
   public var health:Int;

   /**
   Moves the player to a new set of coordinates.

   @param x The target X coordinate.
   @param y The target Y coordinate.
   @return True if the player successfully moved, false otherwise.
   **/                                     // function → keep full param/return docs
   public function move(x:Float, y:Float):Bool { ... }
   ```

1. **Document every public type and field.** Anything `public` is API; give it at
   least a one-line doc comment. Private/internal helpers can use `//` notes.
2. **Lead with a summary sentence**, then add detail in following paragraphs.
3. **Use `@param`/`@return` for every function with arguments or a non-`Void`
   return**, and keep argument names exact.
4. **Reference code identifiers in backticks** so tools and readers can distinguish
   them from prose.
5. **Prefer doc comments for "what/why the caller cares", `//` for "how it works
   inside".** The implementation note `// Implementation goes here` is correctly a
   `//` comment, not a doc comment — it concerns the body, not the contract.
6. **Keep docs truthful and current.** A stale `@return` is worse than none because
   it appears authoritative in generated docs and IDE hovers.
