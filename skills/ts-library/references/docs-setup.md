# Documentation

Five artifacts, each with a different reader:

| File | Reader | Written by |
| --- | --- | --- |
| `README.md` | someone deciding whether to install it | you |
| `AGENTS.md` | an agent working in the repo | you |
| `docs/api/` | someone using it | TypeDoc |
| `CHANGELOG.md` | someone upgrading | semantic-release |
| `llms.txt` / `context7.json` | an agent consuming the package | you |

## README

Usage, not internals. Install, the smallest working example, then the handful of
options that matter. Link to the wiki for the API reference rather than
duplicating it — a hand-maintained API list in a README is stale within two
releases.

A `example.md` alongside it is a good home for the long worked example the
README should not carry.

## AGENTS.md

At the repo root: the stack, the structure, the conventions, and the invariants
that are invisible in review — "the main entry must never import `envelop.ts`",
"peer deps are ranges", "never edit CHANGELOG.md". `CLAUDE.md` is a one-line file
pointing at it, so both toolchains read the same document.

## TypeDoc → GitHub Wiki

`typedoc.json`:

```json
{
  "$schema": "https://typedoc.org/schema.json",
  "entryPoints": ["src/index.ts", "src/scoping.ts", "src/envelop.ts"],
  "plugin": ["typedoc-plugin-markdown", "typedoc-github-wiki-theme"],
  "out": "docs/api",
  "readme": "none",
  "githubPages": false,
  "sidebar": { "autoConfiguration": true, "heading": "API Reference" },
  "hidePageHeader": true,
  "hideBreadcrumbs": true,
  "useCodeBlocks": true,
  "expandObjects": true,
  "intentionallyNotExported": ["RootOperations", "ResolveFn", "Tagged"]
}
```

- **`entryPoints` must list every subpath export.** A subpath missing here is a
  public API with no documentation, and nothing warns.
- `intentionallyNotExported` silences the warning for internal types that appear
  in a public signature but are not themselves exported. Adding a name here is a
  decision — the alternative is exporting the type.
- `readme: "none"` — the wiki has its own landing page, and TypeDoc would
  otherwise inline the README into it.
- **`docs/api/` is generated and gitignored.** Committing it produces a diff on
  every release that nobody reads.

The package overview docblock at the top of `src/index.ts` becomes the front
page. It is the one place to explain what the package is *for*.

Add to CI's test workflow, after the tests:

```yaml
      - name: Generate API docs
        run: npm run docs

      - name: Publish API docs to wiki
        if: github.ref == 'refs/heads/main'
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # GitHub wikis are a separate git repo. The wiki must be initialized
          # once (create any page in the UI) before .wiki.git exists.
          git clone --depth 1 \
            "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.wiki.git" wiki
          rm -rf wiki/*
          # typedoc-github-wiki-theme already emits Home.md (landing page),
          # _Sidebar.md (navigation) and wiki-compatible page names.
          cp -r packages/graphql-casl/docs/api/. wiki/
          cd wiki
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add -A
          git diff --cached --quiet || git commit -m "docs: sync API reference [skip ci]"
          git push
```

`git diff --cached --quiet ||` — an unchanged run must not fail the job, and
`git commit` with nothing staged exits non-zero.

The job needs `permissions: contents: write`.

## llms.txt and context7.json

For a package meant to be consumed by agents. `llms.txt` is a flat, link-free
summary of what the package does and how to call it — the thing an agent reads
instead of crawling the wiki. `context7.json` registers the docs source with
Context7.

Both are hand-written and short. They go stale silently, so revisit them
whenever the public API changes.

## CHANGELOG.md

Written by `@semantic-release/changelog` from the commit messages. **Never edit
it by hand** — the next release regenerates the section you touched, and your
edit is lost with no conflict.

The lever for changelog quality is the commit message. A `fix:` subject that
reads as a sentence in a release note is worth the extra ten seconds.
