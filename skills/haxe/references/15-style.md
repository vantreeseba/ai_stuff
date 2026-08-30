<!--label:style-->
## Code Style

Haxe has a de-facto standard style: the built-in defaults of the official
[Haxe formatter](https://github.com/HaxeCheckstyle/haxe-formatter) (the `formatter`
haxelib, used by the Haxe VS Code extension's "Format Document"). An empty
`hxformat.json` (`{}`) means "use these defaults".

**Style precedence — check the project root first:**
1. If the project ships a **`hxformat.json`** (formatter config) or a
   **`checkstyle.json`** (haxe-checkstyle config), those win. Read them and follow
   their rules; they override anything below.
2. Otherwise, **write and update code to match the formatter defaults** described
   here.

> Reference: defaults documented at
> <https://haxecheckstyle.github.io/haxe-formatter-docs/> and the project's
> `resources/default-hxformat.json`.

<!--label:style-defaults-->
### Preferred rules (formatter defaults)

**Indentation**
- Indent with **tabs**, not spaces. A tab is displayed as **4** columns.
- No trailing whitespace; files end with a **final newline**.
- `case`/`default` labels inside a `switch` are **indented** one level.
- Conditional-compilation blocks (`#if`/`#else`/`#end`) are **aligned**.

**Braces** — opening brace stays on the **same line** as the declaration/statement
(`leftCurly: "after"`), and the closing brace sits on its own line
(`rightCurly: "both"`). Empty braces stay together as `{}` (`emptyCurly: "noBreak"`).

```haxe
class Player {
    public function move(x:Float, y:Float):Bool {
        if (x < 0) {
            return false;
        }
        return true;
    }

    public function new() {}
}
```

**Spacing**
- **Spaces around binary operators**: `a + b`, `x == y`, `i < n` (`binopPolicy: "around"`).
- **Space only after commas**, never before: `move(x, y)` (`commaPolicy: "onlyAfter"`).
- **No spaces around the type-hint colon**: `health:Int`, `move(x:Float):Bool`
  (`typeHintColonPolicy: "none"`). This is the most common JS/TS habit to break.
- **No space before a call's `(`**: `move(10, 20)`, not `move (10, 20)`.
- **Space after the keyword** in `if`/`for`/`while`: `if (cond)`, `for (i in 0...n)`,
  `while (running)`.

**Line length & wrapping**
- Target a **maximum line length of 160** characters. Lines stay on one line until
  they exceed that, at which point the formatter wraps argument/array/object lists.

<!--label:style-applying-->
### Applying the style

- When **writing new code**, produce it already matching the rules above so it is
  formatter-clean.
- When **editing existing code**, match the surrounding file. If the project has a
  `hxformat.json`/`checkstyle.json`, or the file already follows a different
  consistent style, conform to that rather than reformatting unrelated lines.
- If the `formatter` haxelib is installed, the canonical check is
  `haxelib run formatter -s <File.hx>` (or formatting in VS Code); treat its output
  as the source of truth over this summary.
