# Work without QMD, Serena, or Enola

Plastic works without QMD, Serena, and Enola. Its store search, document fetch, context records,
and lifecycle commands use the local SQLite databases.

Use `plastic search TERMS --source-project SLUG` to find indexed passages and `plastic document
get REFERENCE` to read immutable evidence. `plastic intent discover` and `plastic intent context`
keep selected evidence and its provenance with an intent.

QMD remains useful for its own semantic or hybrid store search. Serena remains useful for code
navigation. Enola can provide an architecture receipt when you run `plastic architecture refresh`
or when you generate a snapshot directly. The receipt names its revision, coverage, limitations,
and tool hashes. Search does not generate or refresh it.

No command requires these tools to plan, deliver, or close an intent.
