# Tools

Plastic uses SQLite for deterministic store retrieval. RTK and QMD remain companion tools. Enola
is optional, but `plastic architecture refresh` can run it when you explicitly request an
architecture receipt. Search does not refresh Enola.

### RTK

RTK condenses command output so a long shell result costs fewer tokens without losing its
signal. It sits in front of the shell, not in front of Plastic: a hook rewrites a plain command
into its RTK-wrapped form, and Plastic itself never calls it. Run a command as usual; RTK trims
the output before it reaches the session.

### QMD

QMD is a local markdown search engine over the Plastic stores and any other collection of
markdown a person points it at. Plastic's own store search runs on sqlite3 and never calls QMD.
When QMD is set up, search a store's history with it before re-deriving a decision by hand: run
`qmd query` for a structured intent/lex/vec/hyde search, or `qmd search` for a plain BM25 keyword
search that needs no model downloads. QMD is set up and queried outside Plastic; no Plastic
command starts, registers with, or reads from it.

### Enola

Enola reads a codebase's architecture as queryable facts: symbols, dependencies, layers, and the
findings its explainers compute. Use `plastic architecture status --project SLUG` to read the saved
receipt. Use `plastic architecture refresh --project SLUG` to run an explicit refresh. The receipt
records the repository revision, executable and archive hashes, extractor version, coverage, and
limitations as provenance. A failed refresh preserves the prior receipt.

### Using them together

Reach for RTK on every shell command's output, for QMD when a question is answered somewhere in
a store's history, and for Enola when a question is about how the code is put together. None of
the three is required: a plain macOS or Linux system with git and sqlite3 runs every Plastic
command on its own.
