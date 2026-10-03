# Work without QMD, Serena, or Enola

Plastic works without QMD, Serena, and Enola. Its store search, document fetch, context records,
and lifecycle commands use the local SQLite databases.

Use `plastic search TERMS --source-project SLUG` to find indexed passages and `plastic document
get REFERENCE` to read immutable evidence. `plastic intent discover` and `plastic intent context`
keep selected evidence and its provenance with an intent.

QMD remains useful for its own semantic or hybrid store search. Serena remains useful for code
navigation. Enola remains useful for mapping a codebase's architecture. `plastic architecture status`
and `plastic architecture refresh` tell the agent to check or regenerate that map with a tool it
chooses. Plastic does not run the tool and does not store the map.

No command requires these tools to plan, deliver, or close an intent.
