# Authoring an Agent Skill

Open this when writing or restructuring a single Agent Skill: the frontmatter, the
description that triggers it, the body voice, and the on-disk layout. Rule ids in brackets
(A1 through B10) point at the synthesis standard the rules come from.

For the three load levels (metadata, body, resources), the thin-router pattern, and how to
split a body into `references/`, read `progressive-disclosure.md`. This file does not repeat
that model.

## Contents

- Skill file layout
- Frontmatter fields
- The `name` field
- The `description` field (triggering)
- Optional frontmatter fields
- Body voice
- Body content
- Self-check

## Skill file layout

A skill is a directory whose name matches the `name` field. The directory holds `SKILL.md`
plus optional buckets. Pick a bucket by how the file touches context.

| Path | Loads when | Holds |
|------|-----------|-------|
| `SKILL.md` | The skill triggers | Frontmatter plus the body |
| `references/` | The body points at it, on demand | Deep how-to, specs, variant material |
| `scripts/` | Executed, never read into context | Repeated deterministic code |
| `assets/` | Copied into output, never read | Templates, boilerplate the output needs |
| `evals/` | Run by the eval harness | Eval cases for the skill |

When picking a bucket, follow `progressive-disclosure.md` for the cross-cutting layout rules:
references one level deep (C5), no orphan or auxiliary files in the skill (C9), and each fact
stored once (C7).

## Frontmatter fields

`SKILL.md` opens with YAML frontmatter. Two fields are required.

| Field | Required | Constraints |
|-------|----------|-------------|
| `name` | Yes | 1 to 64 chars. Lowercase alphanumeric plus hyphens. No leading, trailing, or consecutive hyphens. Matches the directory name. |
| `description` | Yes | 1 to 1024 chars. Non-empty. States what and when. |

Invent no other top-level fields. Unknown fields are ignored or rejected and add noise [A6].

## The `name` field

Rules [A5]:

1. 64 chars or fewer.
2. Lowercase letters, numbers, and hyphens only.
3. No leading, trailing, or consecutive hyphens.
4. Must match the parent directory name exactly.
5. Must not contain `anthropic` or `claude`.
6. Prefer the gerund form, which reads as a capability (`processing-pdfs`, `creating-skills`,
   not `pdf-tool`).
7. Never start with `plastic-`. That prefix is reserved for skills and hooks Plastic itself
   ships; doctor's ownership checks (`stray_skills`) and the installer's purge both key off it,
   so a user-authored skill carrying it reads as squatting on Plastic's own namespace.

## The `description` field (triggering)

The description is the only text loaded at discovery time. The body is not loaded when the
agent decides whether to trigger, so the description alone has to win the match.

Rules:

1. Write the description as triggering conditions only ("Use when ..."), never as a summary of
   the workflow [A1]. A workflow summary makes the agent act on the summary and skip the body,
   dropping steps. Documented failure: a description that summarized "code review between
   tasks" produced one review instead of two.
2. Write in the third person [A2]. The description is injected into the system prompt, where
   mixed point of view degrades discovery.
3. State both what the skill does and when to use it, and front-load concrete trigger terms
   [A3]. The model picks from many skills on this text and the listing is budget-truncated, so
   terms placed late may never be read.
4. Include at least one indirect trigger where the user does not name the domain [A4]. Real
   prompts rarely name the skill, so a keyword-only description misses oblique requests.

Shape:

```yaml
description: >
  [One clause: what it does]. Use when [primary trigger], [secondary trigger],
  or when [indirect trigger where the user does not name the domain].
```

For side-effecting workflows (deploy, release, destructive ops), set
`disable-model-invocation: true` so only the user fires the skill [A7]. Auto-triggering on
irreversible work is a known failure mode.

## Optional frontmatter fields

Use only the documented optionals below. Add nothing beyond them [A6].

| Field | Holds |
|-------|-------|
| `license` | Short name or filename reference |
| `compatibility` | Environment requirements, 1 to 500 chars, only when needed |
| `metadata` | String-to-string map with unique keys |
| `allowed-tools` | Space-separated tool list (experimental) |
| `model` | Claude Code extension: pin the model for this skill |
| `disable-model-invocation` | Claude Code extension: only the user may fire the skill |
| `user-invocable` | Claude Code extension: set false to hide the skill from the user's / slash menu while leaving it agent-invocable; default true |
| `context: fork` | Claude Code extension: run the body as a forked task |
| `paths` | Claude Code extension: scope the skill to matching paths |

## Body voice

Rules:

1. Write in imperative or infinitive voice ("Run the validator", "Extract the text"), never
   second person ("you should", "you can") [B1]. Command voice is shorter and binds tighter;
   hedged second-person language is a known slop pattern.
2. Use one consistent term per concept ("extract", never also "pull", "get", "retrieve")
   [B6]. Synonym drift makes the agent unsure whether two terms name the same operation.

## Body content

The body persists in context every turn the skill is active, so each line is a recurring
cost. Spend lines only where the agent would otherwise go wrong.

Rules:

1. State what to do, not how or why, and cut anything the model already knows [B2]. Claude is
   already capable; the body is for the project-specific and the non-obvious.
2. Apply the test "would the agent get this wrong without it?" to every instruction. If no,
   delete it [B7]. Instructions that restate default competence are pure token cost.
3. Challenge every paragraph with "does this justify its token cost?" and prefer one excellent
   example over many mediocre ones [B3].
4. Lead each section with one bold maxim and close it with one concrete self-check [B4]. The
   maxim is what survives in context; the check lets the agent apply the rule mid-task.
5. Put gotchas as concrete corrections, placed early [B5]. A correction only helps if the
   agent reads it before it makes the mistake. Write the specific fact, not general advice:

   ```markdown
   ## Gotchas
   - The `users` table uses soft deletes. Queries must include `WHERE deleted_at IS NULL`.
   - User id is `user_id` in the DB, `uid` in auth, `accountId` in billing. Same value.
   - The `/health` endpoint returns 200 even when the DB is down. Use `/ready`.
   ```

6. Carry reference and decision material in tables and numbered lists. Use a flowchart only
   for a genuinely non-obvious decision or an early-stop loop [B10]. Tables are denser per
   token; flowcharts waste tokens on reference, code, or linear steps.
7. State the tradeoff and ship an escape hatch instead of policing edge cases with long
   rationalization tables [B8]. Add an Excuse-and-Reality table only for a discipline skill
   where an eval has actually shown the agent rationalizing a violation.
8. Avoid time-sensitive content. Move deprecated material into a collapsed "Old patterns"
   section [B9]. Dated instructions rot and mislead.

## Self-check

Before shipping the skill, confirm each line:

- [ ] `name` matches the directory, is lowercase-hyphen, and carries no `claude`/`anthropic`.
- [ ] `description` reads as "Use when ...", third person, with front-loaded triggers and at
      least one indirect trigger.
- [ ] No invented frontmatter fields; optionals are drawn only from the table above.
- [ ] Side-effecting skill sets `disable-model-invocation`.
- [ ] Body is imperative, with one term per concept.
- [ ] Every instruction passes "would the agent get this wrong without it?".
- [ ] Gotchas are concrete corrections, placed early.
- [ ] Reference and decision material is in tables or lists, not prose.
- [ ] `references/` files are one level deep; no orphan or auxiliary files in the skill.
