# Tools

Plastic uses SQLite for deterministic store retrieval. RTK, QMD and Enola are companion tools.
Plastic never runs them and stores none of their output. The `plastic architecture` commands
only tell the agent to map the code with a tool it chooses.

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
findings its explainers compute. `plastic architecture status --project SLUG` tells the agent to
check whether the project's architecture map is current. `plastic architecture refresh --project
SLUG` tells the agent to regenerate the map. Both commands print instructions only. The agent
chooses the mapping tool, runs it, and reads the result. Plastic does not run Enola and does not
save the map, because the tool can produce it again at any time.

Plastic also asks for the map at two points of an intent. When it hands planning to the agent, it
tells the agent to fetch the map first. In `plastic intent end`, it tells the agent to fetch the map
once more and to note the tool and the source revision under Verification in outcome.md. These are
reminders only. Plastic does not check them.

### Using them together

Reach for RTK on every shell command's output, for QMD when a question is answered somewhere in
a store's history, and for Enola when a question is about how the code is put together. None of
the three is required: a plain macOS or Linux system with git and sqlite3 runs every Plastic
command on its own.
