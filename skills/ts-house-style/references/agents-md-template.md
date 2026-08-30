# AGENTS.md convention

## The two-file rule

`AGENTS.md` at the repo root is the single source of truth. `CLAUDE.md` is a
pointer at it and nothing else:

```markdown
Use AGENTS.md instead.
```

or, where the tool supports transclusion:

```markdown
@AGENTS.md
```

Never let both hold content. Two files that describe the same conventions
diverge within a month, and the reader has no way to know which one is current.

## What goes where

`AGENTS.md` holds what someone needs before touching anything: overview, stack,
commands, structure, key conventions, and the index of `.agents/` files.
Everything that is only needed once you are *in* an area goes in `.agents/`.

The test: if it would be read by someone changing a resolver but not by someone
changing a screen, it belongs in `.agents/server-patterns.md`.

## Template

```markdown
# AGENTS.md — <Project>

## Project Overview

<Two or three sentences: what it is, who it is for, what the ownership model is.
Name the monorepo packages.>

## Tech Stack

| Layer    | Technology |
|----------|-----------|
| Frontend | ... |
| API      | ... |
| Database | ... |
| Testing  | ... |
| Linting  | Biome |
| Runtime  | Node 22+, ESM |

## Commands

All commands run from the **repo root** unless noted.

### Development
​```bash
npm run dev          # both, concurrently
npm run dev:server   # API only (:3001)
npm run dev:app      # client only (:3000)
​```

### Quality
​```bash
npm run typecheck
npm run lint / lint:fix
npm test
​```

**After every chunk of work:** run `npm run lint:fix && npm run typecheck`.

### Database / Codegen / Build
<the rest of the script vocabulary>

Prefer these `package.json` scripts over ad-hoc `npx` invocations — they wrap
env loading, workspace targeting, and flag conventions.

## Project Structure

<tree, one line of purpose per package>

## Key Conventions

<the four or five rules that are actually violated in review. Each one gets a
bad/good code block, not a sentence. Examples: guard-clause order, curly braces,
inferred types, the typed graphql() helper.>

## Agent File Convention

All planning, tracking, and pattern guides live in `.agents/`.
Never create these files at the repo root.
Always add new `.agents/` files to the reference list below.

## Agent Reference Files

- [`.agents/project-structure.md`](.agents/project-structure.md) — ...
- [`.agents/server-patterns.md`](.agents/server-patterns.md) — ...
```

## The `.agents/` set

| File | Holds |
| --- | --- |
| `project-structure.md` | full directory tree, DB schema columns, route table, GraphQL operation index |
| `db-patterns.md` | Drizzle table definitions, connection, query patterns, migrations |
| `server-patterns.md` | resolver authoring guide, zod constraint table, auth details, DataLoader usage |
| `graphql-patterns.md` | full SDL, naming conventions, cache invalidation |
| `client-patterns.md` | Apollo setup, routing, cache invalidation, fragment colocation, styling |
| `deployment.md` | Docker, environment variables, Postgres setup |
| `todo.md` | open features, known issues, deferred work |

**Every new `.agents/` file is added to the reference list in `AGENTS.md`.** A
file nothing links to will not be found and will not be read — it is worse than
not writing it, because the author now believes it is documented.

## Planning documents

A design note for one feature — `plan-caldav.md`, `review-todo.md` — lives in
`.agents/`, **never at the repo root**. The root is for files a human opening the
repo needs: README, AGENTS.md, LICENSE, config.

## Recording what you decided *not* to build

Keep a `TODO_IDEAS.md` (or a section in `.agents/todo.md`) of ideas that were
considered and deliberately rejected, each with the reasoning that deferred it.

Two reasons this earns its place. It stops the same idea being re-proposed and
re-rejected every few months. And when the reasoning stops holding — a
dependency ships the thing, a constraint lifts — the entry is where someone
notices.

**Check it before proposing something new**, because the idea may already have
been rejected for a reason that still applies.

## Tracking open work

Repos with milestones track open work in GitHub issues (`gh issue list`), not in
a file — read the current milestone before starting a feature. Repos without
them use `.agents/todo.md`. Pick one per repo; two trackers is none.
