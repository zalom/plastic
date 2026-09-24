# Tools

No Plastic command depends on RTK, QMD or Enola. Plastic itself calls only git and sqlite3.
These three are companion tools a person can run beside Plastic, by hand, for the parts Plastic
does not do itself: condensing shell output, searching the stores by meaning, and reading a
codebase's architecture as queryable facts.

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
findings its explainers compute (cycles, layer violations, dead routes, hotspots). Plastic's own
checks (the doctor, the change gate) never call it. Generate a snapshot on a repository by hand
(`enola --generate <repo>`), then query it directly, before or after a Plastic delivery, to see
what a change did to the structure.

### Using them together

Reach for RTK on every shell command's output, for QMD when a question is answered somewhere in
a store's history, and for Enola when a question is about how the code is put together. None of
the three is required: a plain macOS or Linux system with git and sqlite3 runs every Plastic
command on its own.
