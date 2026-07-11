# Transport and Privacy

Read this before filling `report.md` and before presenting the URL to the user.

## Obfuscation checklist (do this before filling the template)

Run through this list on the narrative gathered from the user, before it goes
into `report.md`:

- Strip project names. Refer to "the project" or "a consumer project", never
  the user's actual project name.
- Strip file paths and directory names specific to the user's codebase.
- Turn Plastic intent names into their bare ids. Drop the descriptive title if
  it names project content (an intent title like "Fix the checkout flow" leaks
  what the user is building; "intent 42" does not).
- Keep only Plastic's own operational content: which command, hook, or skill
  ran, what it did, what it should have done instead.
- Before presenting the URL, re-read the filled report once and confirm none
  of the above slipped back in.

## Mechanical redaction (what the script also strips)

`scripts/lib/feedback_report.rb` redacts these patterns to `[REDACTED]` before
the report ever touches disk, as a second, mechanical layer under the
obfuscation above:

| Secret kind | Pattern shape |
|---|---|
| GitHub tokens | `ghp_`, `gho_`, `ghs_`, `ghr_`, `ghu_`, `github_pat_` prefixes |
| Anthropic/OpenAI keys | `sk-ant-...`, `sk-...` |
| AWS access key id | `AKIA...` |
| Bearer tokens | `Bearer <token>` |
| Slack tokens | `xoxb-`, `xoxa-`, `xoxp-`, `xoxr-`, `xoxs-` prefixes |
| Google API keys | `AIza...` |
| PEM private key blocks | `-----BEGIN ... PRIVATE KEY----- ... -----END ... PRIVATE KEY-----` |
| Key/value assignments | `api_key = ...`, `secret: ...`, `token = ...`, `password: ...` (value only) |

Treat this list as a safety net, not the primary defense. The mechanical
patterns catch a specific, known shape; the obfuscation pass above is what
catches project-identifying context a regex cannot recognize.

## Why a prefilled URL, and not something else

The report is sent by opening a prefilled `https://github.com/zalom/plastic/issues/new`
URL in the user's own browser. Submission happens in an authenticated session
that belongs to the user, not to the agent or the script. Nothing in this
skill or in `feedback-report` can complete that submission on its own: there
is no send method, no token, and no network call anywhere in the code path.

Other transports were considered and rejected:

- **`gh issue create`**: the CLI can send on its own; only `--web` is
  browser-submitted, and the plain form cannot be guaranteed not to send
  directly. It also assumes `gh` auth, which a consumer-project user may not
  have.
- **An API POST with a token**: the agent could send it, and the token itself
  becomes a credential worth stealing.
- **An anonymous POST endpoint**: still agent-reachable, with no built-in spam
  resistance, and it needs server infrastructure this project does not run.
- **Email or `git send-email`**: the CLI sends the message, review is opt-in
  rather than forced, and it needs a working mail transport most machines do
  not have configured.

Only the prefilled-URL approach makes "the agent cannot send" a structural
fact instead of a rule the agent could break by taking a shortcut.
