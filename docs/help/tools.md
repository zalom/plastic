# Tools

Plastic uses SQLite for deterministic store retrieval. RTK and Enola are companion tools.
Plastic never runs them and stores none of their output. The `plastic architecture` commands
only tell the agent to map the code with a tool it chooses.

### RTK

RTK condenses command output so a long shell result costs fewer tokens without losing its
signal. It sits in front of the shell, not in front of Plastic: a hook rewrites a plain command
into its RTK-wrapped form, and Plastic itself never calls it. Run a command as usual; RTK trims
the output before it reaches the session.

### Enola

Enola reads a codebase's architecture as queryable facts: symbols, dependencies, layers, and the
findings its explainers compute. `plastic architecture status --project SLUG` tells the agent to
check whether the project's architecture map is current. `plastic architecture refresh --project
SLUG` tells the agent to regenerate the map. Both commands print instructions only. The agent
chooses the mapping tool, runs it, and reads the result. Plastic does not run Enola and does not
save the map, because the tool can produce it again at any time.

Plastic asks for the map at one point of an intent, and only for code work. When it hands planning
to the agent in a project that names a repository, it tells the agent to map the code with a tool
such as Enola and to read the project's `AGENTS.md`, so the graph is planned from the real
architecture. Nothing runs after the plan or after delivery: `plastic intent end` asks for no map
line, and the reminder before planning is not checked.

### Using them together

Reach for RTK on every shell command's output and for Enola when a question is about how the code
is put together. Neither is required: a plain macOS or Linux system with git and sqlite3 runs every
Plastic command on its own.

For a question about what the project decided or delivered, ask `plastic search` with three to five
different keywords, not the whole question, and read one passage with `plastic document get REF
--passage N`. For how the code changed, read its history with git, and for how it is put together,
ask Enola. `plastic project load` prints a `history:` row that says so, and each `delivered:` row
ends with the `Merged:` or `Committed:` line of its outcome.
