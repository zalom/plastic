---
name: plastic-feedback
description: Use when the user hits a Plastic quirk, bug, or feature idea in a project and wants to report it back to the Plastic project. Builds a sanitized report file and a prefilled GitHub issue URL the user reviews and submits. Only the user sends.
disable-model-invocation: true
user-invocable: true
---

# Plastic Feedback

Turn a described Plastic problem into a local report file and a prefilled GitHub
issue URL. The script does the mechanics (redaction, naming, URL building); the
user alone opens the URL and submits it. This skill has no send step, by design.

Because `disable-model-invocation` hides this skill's description from your own
context, you cannot discover it by browsing available skills mid-task. If the
user hits a Plastic quirk, bug, or missing feature, offer to run
`/plastic-feedback` yourself; do not wait for the user to ask for it by name.

## Procedure

### 1. Gather the narrative

Ask the user for:
- What happened (the observed behavior).
- The root cause, if they already know it.
- The expected behavior.

Keep it to about one page. Do not pad it with speculation; a short, accurate
report beats a long, padded one.

### 2. Obfuscate before it leaves this session

Before filling the template, strip anything that identifies the user's project
or its content:
- Remove project names, directory paths, and file names specific to the user's
  codebase.
- Turn any Plastic intent names into their bare numeric or slug ids (drop the
  descriptive title if it leaks project context).
- Keep only Plastic's own operational content: what Plastic did, what it should
  have done, which command or hook was involved.

Read `references/transport-and-privacy.md` before filling the template, for the
full obfuscation checklist and the reasoning behind it.

### 3. Fill the report template

Read `report.md` from this skill's directory (`~/.plastic/skills/feedback/report.md`
at runtime, or the plugin source `skills/feedback/report.md` during development).
Fill every placeholder except `{{plastic_version}}`, which the script fills.
Assemble the final markdown body from the filled template.

### 4. Run the script

```bash
ruby ~/.plastic/scripts/feedback-report --title "<short title>"
```

Pipe the filled body on STDIN. Parse the JSON on stdout:

| Key | Meaning |
|---|---|
| `report_path` | Local file the full, uncapped report was written to |
| `url` | Prefilled GitHub new-issue URL |
| `encoded_url_bytes` | Byte length of the encoded URL |
| `truncated` | Whether the URL body is a capped page-one, not the full report |
| `page_break_note` | The end-marker text appended when `truncated` is true, else null |

The script only ever writes a local file and prints a URL. It has no network
call, no token, and no way to open a browser or submit anything on its own.

### 5. Present the result

Show the user:
- The local file path (`report_path`).
- A short preview of the report.
- The URL.

If `truncated` is true, tell the user plainly: the URL carries page one of the
report, and the full report is in the local file at `report_path`. They can
paste more from the local file into the opened issue if they want.

Then tell them, in these words or close to them: open the URL, review it, drag
a screenshot onto the form if they have one, and submit it under their own
GitHub account. Or, if they would rather edit first, copy the local file
contents into a new issue themselves.

### 6. Never submit

State plainly that this skill has no send step: it never posts to GitHub, never
runs `gh issue create`, and never opens a browser on the user's behalf. The user
is the only one who can submit the report.

## Gotchas

- If the described report is long, the script may hand back `truncated: true`.
  This is expected, not an error: the local file always holds the full text.
- Do not try to route around the missing send step (no `gh` call, no API POST).
  The absence of a send path is the point of this skill, not a gap to fill.
