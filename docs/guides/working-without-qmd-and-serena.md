# Working without QMD and Serena

Who this is for: someone who has not installed QMD (a local search tool for
Plastic's stores) or Serena (a code navigation tool), and wonders what they
are missing.

After this guide you will know exactly what is optional, what still works
without it, and why nothing in Plastic's core cycle depends on either tool.

## The short answer

QMD, Enola, and Serena are recommendations, not requirements. Plastic works
fully without them. Nothing in the intent lifecycle, the locks, or the gates
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
- A search hint on some content searches, suggesting you search through QMD
  instead of scanning files. This hint never blocks anything. It is the same
  advisory gate covered in
  [what-the-gates-are-telling-you.md](what-the-gates-are-telling-you.md): it
  always allows the search to run.

## What still works, no matter what

- Reading and searching the intent stores, through the built-in fallback
  (scanning the index and files directly).
- Every lifecycle skill: creating intents, boarding them, running guided or
  auto mode.
- Every lock, code, and create gate. These do not know or care whether QMD or
  Serena exist.
- The complete auto-delivery cycle, start to finish.

So if you are working without QMD and Serena, you are not missing any part of
Plastic itself. You are only missing a search shortcut and one reminder line.
Install them later if you want faster search; nothing about how you use
Plastic today needs to change first.

## What to read next

Read [using-plastic-with-claude-code.md](using-plastic-with-claude-code.md)
to see how guided and auto mode fit together with roadmap-driven delivery,
Plastic's way of shipping a batch of intents toward one goal.
