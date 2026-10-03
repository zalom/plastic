# Search commands

Plastic indexes readable intent documents as immutable revisions and searchable passages in each store's SQLite databases. `sync up` records changed files before a search can read them.

## Commands

| Command | What it does |
| --- | --- |
| `plastic search TERMS [--source-project SLUG] [--limit N]` | Searches literal terms in selected stores. The default limit is 20 passages. |
| `plastic document get REFERENCE [--passage N]` | Fetches a qualified document, or one numbered passage of it. |
| `plastic document batch REFERENCE...` | Fetches qualified documents in request order. |
| `plastic intent discover ID TERMS... [--source-project SLUG]` | Records deterministic candidates for an intent. |
| `plastic intent context ID [--from FILE]` | Reads the latest saved context of an intent, or saves the selection in `FILE`. |

Each command accepts `--json`, which returns every field as structured data. Search reads the selected stores and does not write to them. Pass repeated `--source-project` options to search across several stores. When an agent harness sets `PLASTIC_SOURCE_PROJECTS`, that is the default scope. Explicit options replace that scope.

## Search literal passages

Search treats terms as literal text. Quotes, punctuation, dashes, and colons do not become FTS operators. Results include the store, immutable qualified reference, passage rank, BM25 metadata, and a bounded excerpt. Federated searches combine each store's local rankings with reciprocal rank fusion and use stable reference ordering for ties.

```text
$ plastic search "byte budget" --source-project plastic --limit 20
```

Search is deterministic retrieval. It does not call a model, rebuild an index, run a mapping tool, or change archive state.

## Fetch a document

Use the qualified reference returned by search to read the full document. Add `--passage N` to read one passage by its position, counted from 1. A revision-qualified reference remains readable after a newer head replaces it.

```text
$ plastic document get "plastic://plastic/401/spec.md?revision=SHA256" --json
```

## Prepare agent context

Use `plastic intent discover` to save candidates and provenance for an intent. An agent selects the evidence and submits it with `plastic intent context`. Plastic validates references and saves the selected context. The agent decides relevance and interpretation. Before a context is saved, `plastic intent context ID` fails with exit code 1 and says that the intent has no retrieval context.
