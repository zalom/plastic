# Working without QMD and Serena

Who this is for: someone who has not installed QMD (a local search tool for
Plastic's stores) or Serena (a code navigation tool), and wonders what they
are missing.

After this guide you will know exactly what is optional, what still works
without it, and why nothing in Plastic's core cycle depends on either tool.

## The short answer

QMD, Enola, and Serena are recommendations, not requirements. Plastic works
fully without them. Nothing in the intent lifecycle, the locks, or the record
depends on any of them being present.

## What QMD is for

QMD is a local search engine over Plastic's intent stores: it makes finding
past intents, decisions, and outcomes faster than scanning files by hand.
Every place Plastic calls QMD is written to check first whether it is
installed. If it is not, the call quietly does nothing and Plastic falls back
to reading the index and scanning files directly, the same way it always
could.

## What Serena is for

Serena helps an agent navigate code by symbol (jump to a function's
definition, find everywhere it's used) instead of reading whole files. Like
QMD, it is a recommendation. When it is present, Plastic's install step
mentions it. When it is absent, nothing is mentioned and nothing breaks.

## What Enola is for

Enola is a second code-navigation option: an indexer that resolves symbols
(where a method is defined, everywhere it is called) from a generated snapshot
instead of reading whole files, similar to Serena but through its own MCP
server and its own `.enola/` snapshot. When both Enola and Serena are present,
Plastic names only Enola in its recommendation, following the project's
Enola-first choice for code navigation. Like the other two tools, it is
entirely optional: nothing breaks and nothing is required if it is absent.

## What you actually lose without them

Two small things, both about convenience, not capability:

- A one-line reminder that these tools exist, shown once after install if
  they are detected on your system.
- A recommendation line in the core conventions (`PLASTIC.md`), plus a per-prompt
  reminder hook, suggesting you search through QMD instead of scanning files.
  Neither blocks anything; the search always runs.

## What still works, no matter what

- Reading and searching the intent stores, through the built-in fallback
  (scanning the index and files directly).
- Every lifecycle skill: creating intents, direct and thinking work, auto
  delivery.
- The delivery lock and the record hook. These do not know or care whether QMD
  or Serena exist. Where the record lands is described in
  [reading-the-ledgers.md](reading-the-ledgers.md).
- The complete auto-delivery cycle, start to finish.

So if you are working without QMD and Serena, you are not missing any part of
Plastic itself. You are only missing a search shortcut and one reminder line.
Install them later if you want faster search; nothing about how you use
Plastic today needs to change first.

## What to read next

Read [using-plastic-with-claude-code.md](using-plastic-with-claude-code.md)
to see how guided and auto mode fit together with roadmap-driven delivery,
Plastic's way of shipping a batch of intents toward one goal.
