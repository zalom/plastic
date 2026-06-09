# Plastic Convention Checks

Assertion library for convention compliance evals on Plastic skills.
Load when running convention compliance evals on a Plastic skill.

## Directory Structure

| Check | Pass criteria |
|-------|--------------|
| SKILL.md exists | File present at skill root |
| Name matches directory | `name` in frontmatter equals directory name |
| Standard directories only | Only scripts/, references/, assets/, evals/ at root level (all optional) |
| References one level deep | No nested directories inside references/ |
| No orphan files | Every file in the skill dir is referenced from SKILL.md or another skill file |
| evals/ has evals.json | If evals/ exists, it contains evals.json |

## Frontmatter

| Check | Pass criteria |
|-------|--------------|
| `name` present | Non-empty, 1-64 chars |
| `name` format | Lowercase alphanumeric + hyphens, no leading/trailing/consecutive hyphens |
| `name` matches dir | Exact match with skill directory name |
| `description` present | Non-empty, 1-1024 chars |
| `description` phrasing | Starts with imperative verb or "Use when" pattern |
| `description` triggers | Mentions at least one trigger context ("Use when...") |
| `description` edge cases | Includes at least one indirect trigger (user doesn't name the domain) |
| No unknown required fields | Only uses fields from agentskills.io spec: name, description, license, compatibility, metadata, allowed-tools |

## Progressive Disclosure

| Check | Pass criteria |
|-------|--------------|
| Body line count | SKILL.md body (excluding frontmatter) under 500 lines |
| Body token count | SKILL.md body under 5000 tokens (estimate: lines * 10) |
| Deep detail in references | Content exceeding activation budget lives in references/ |
| Conditional reference triggers | Every reference file mentioned in SKILL.md has a "when" condition |
| No generic references | No "see references/ for more" — each reference has specific load trigger |
| Description token budget | Description stays under ~100 tokens for discovery stage |

## Content Quality

| Check | Pass criteria |
|-------|--------------|
| Gotchas are concrete | Each gotcha is a specific correction, not general advice |
| Gotchas positioned early | Gotchas section appears before or near the top of procedures |
| Defaults, not menus | Skill picks one approach; alternatives mentioned briefly if at all |
| Procedures over declarations | Instructions teach HOW to approach, not WHAT to produce |
| Reasoning over rigid directives | Uses "Do X because Y" pattern, not "ALWAYS/NEVER" without rationale |
| No redundant knowledge | Every instruction passes "would the agent get this wrong without it?" |
| No explaining basics | Does not explain HTTP, JSON, what a migration is, etc. |

## Eval Quality (when evals/ exists)

| Check | Pass criteria |
|-------|--------------|
| Standard format | evals.json follows agentskills.io eval structure |
| Prompts are realistic | Each prompt reads like a real user message |
| Varied phrasing | Prompts use different wording, detail levels, formality |
| Near-miss negatives | At least 2 should-not-trigger cases that share keywords |
| Expected output descriptive | expected_output describes success, not exact text |
| Assertions (if populated) | Each assertion is specific, verifiable, and countable |

## Intent Structure (when evaluating intent compliance)

| Check | Pass criteria |
|-------|--------------|
| Intent file exists | `{ID}--{slug}.md` present in intent directory |
| Frontmatter complete | id, intent, sources, chain, created, author, tags present |
| ID format correct | Follows Luhmann alternating: digits and letters alternate |
| Directory name matches | `{ID}--{slug}` format, 3-5 word slug |
| Lifecycle artifacts | Present artifacts match the intent's lifecycle stage |
| spec.md gate | plan.md only exists if spec.md exists |
| plan.md gate | checklist.md only exists if plan.md exists |
| outcome.md gate | outcome.md only exists if all checklist items checked |
| Insights append-only | `## Insights` section only grows, never shrinks |
