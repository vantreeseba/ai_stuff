---
name: haxe
description: >
  Write haxe code following proper syntax and using the manual. 
  Use this skill when reading or writing any haxe or hxml files.
  The extensions for these files are typically .hx and .hxml.
version: 0.0.6
license: MIT
---

# Haxe

## References

The purpose for these documents is described in the resource here,
under the heading `About this Document`
```
references/01-introduction.md
```

**MANDATORY: You MUST read the relevant reference file(s) BEFORE reading or
writing any Haxe/HXML code that touches the topic they cover. Do not rely on
prior/general knowledge of Haxe — Haxe is not JavaScript, and its syntax and
semantics differ in ways that cause silent errors. If a task plausibly relates
to a reference below, read it first. When in doubt, read it.**

Match the task to the reference(s) and consult them every time:

```
references/
  01-introduction.md   — what Haxe is, targets, how to read these docs
  02-types.md          — the kinds of types (class, enum, abstract, etc.)
  03-type-system.md    — unification, type parameters, type inference
  04-class-field.md    — fields, properties, inline, generics
  05-expression.md     — expression & statement syntax (READ FOR ANY CODE)
  06-lf.md             — pattern matching, string interpolation, DCE, etc.
  07-compiler-usage.md — compiler flags, HXML, build setup
  08-cr-features.md    — advanced compiler features
  09-macro.md          — macros
  10-std.md            — standard library APIs
  11-haxelib.md        — haxelib / dependency management
  12-target-details.md — per-target (JS, C++, etc.) specifics
  13-debugging.md      — debugging Haxe programs
  14-comments.md       — comments & documentation (doc comments, @param/@return)
  15-style.md          — code style (formatter defaults; project hxformat/checkstyle)
  16-tooling.md        — LSP, compiler display/diagnostics, fast type-check loop
  generated/
    defines.md         — compiler defines catalog
    metas.md           — metadata (@:) catalog
```

## Writing code. 

**CRITICAL: Always look at the `references/05-expression.md` and others to ensure code syntax.**

1. **Haxe is not javascript**: Follow syntax as described in references. 

## Choosing and declaring types

**Check `references/02-types.md` whenever you declare a type or annotation.** Haxe has seven distinct type groups (class, enum, structure, function, dynamic, abstract, monomorph), and the right choice is rarely the JavaScript-shaped one. Prefer the compiler's inference over redundant annotations as that file describes.

## Type system, generics, and typedefs

**Read `references/03-type-system.md` before using type parameters, typedefs, or relying on unification.** Typedefs are real types (not textual aliases), and unification rules govern when two types are compatible. Consult it when a "type X should be Y" error appears.

## Class structure and fields

**Read `references/04-class-field.md` before writing classes, properties, or accessors.** Properties use `get`/`set` accessor syntax and `inline`/`final`/`static` modifiers that differ from other languages. Look here for generic functions on classes as well.

## Idiomatic language features

**Read `references/06-lf.md` before reaching for a manual loop or verbose pattern.** Haxe favors abstracts, anonymous structures, array/map comprehensions, pattern matching (`switch`), and string interpolation. Use these idioms instead of porting imperative JS patterns.

## Standard library

**Check `references/10-std.md` before implementing functionality that may already exist.** The std library provides collections, string/math helpers, and common utilities. Use it rather than reinventing these.

## Macros

**Read `references/09-macro.md` before writing or modifying any macro, including `@:build`/`@:autoBuild`.** Macros transform the AST at specific compilation stages and are not textual preprocessors. Do not attempt macro code without consulting this file first.

## Comments and documentation

**Read `references/14-comments.md` before adding comments or doc comments.** Prefer single-line comments, but always give functions full `@param`/`@return` doc comments. The file also covers doc-comment syntax and the difference from `@:` metadata.

## Code style

**Read `references/15-style.md` whenever you write or update Haxe code.** Prefer a project `hxformat.json` or `checkstyle.json` if one exists; otherwise follow the Haxe formatter defaults (tabs, same-line braces, `name:Int` with no space, spaces around operators). Match the surrounding file when editing rather than reformatting unrelated lines.

## Targets and debugging

**Read `references/12-target-details.md` for target-specific behavior and `references/13-debugging.md` when diagnosing failures.** Output semantics differ per target (JS, C++, etc.), so verify assumptions there. Use the debugging reference before guessing at the cause of a runtime or build error.


## Verifying code with the compiler and LSP

**Read `references/16-tooling.md` and verify code with the compiler instead of guessing.** For navigation and type lookups, use your agent's code-intelligence tool if it has one (some harnesses expose an `LSP` tool backed by a Haxe language server); otherwise — and this path always works — query the compiler directly with `--display`, or run a completion server (`--wait`/`--connect`). After editing `.hx`, type-check fast with `haxe build.hxml --no-output` (no codegen) and fix what it reports before claiming the code works — code intelligence answers "what is this?", the compiler answers "does it build?". For the user's own editing, recommend the Haxe language server (vshaxe / `haxe-language-server`) driven by a correct `.hxml`.

## Compiler Options
When selecting a main entry point:

1. Use the relative path from the code path defined in the HXML.

An example directory structure
```
/src
  Main.hx
```

An example HXML with codepath and main defined:
```
-cp src
-main Main
-js bin/main.js
```


When building for node.js do the following:

1. Ensure the hxnodejs library is installed.
2. Include it in the JS section of the HXML (build.hxml) using `-lib hxnodejs`. 
3. The build target is still JS like `-js bin/js/main.js`.

An example HXML:
```
-lib hxnodejs
-cp src
-main Main
-js bin/js/main.js
```

## Testing

After changes to any .hxml file, test it by running:
```
haxe {name}.hxml
```

After changes to a .hx file, first type-check it quickly without generating output:
```
haxe build.hxml --no-output
```

Once it type-checks, build with the hxml and run the output to verify behavior.
An example:
```
haxe build.hxml
node /bin/js/main.js
```

For repeated checks on a larger project, start a compilation server (`haxe -v --wait 6000`)
and route builds through it (`haxe --connect 6000 build.hxml`) for near-instant feedback.
See `references/16-tooling.md`.

