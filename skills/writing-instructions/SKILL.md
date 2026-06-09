---
name: writing-instructions
description: >
  Write or restructure agent instructions, conventions files, and SKILL.md
  content using progressive disclosure and the agentskills.io specification.
  Use when creating PLASTIC.md, rewriting convention docs, authoring new
  skills, restructuring large instruction files to fit context budgets,
  or when instructions feel too long, too vague, or agents aren't following
  them. Also use when the user says "progressive disclosure", "restructure
  instructions", or "the instructions are too big".
---

# Writing Agent Instructions

Based on the [agentskills.io specification](https://agentskills.io).

## Progressive Disclosure Architecture

All agent instructions follow three loading stages. Design for this — it's the
architecture, not a nice-to-have.

| Stage | What loads | Budget | Design for |
|-------|-----------|--------|------------|
| **Discovery** | name + description | ~100 tokens | Trigger accuracy |
| **Activation** | Full instruction body | <5000 tokens / <500 lines | Core procedures |
| **Execution** | references/, scripts/, assets/ | As needed | Deep detail |

**The description carries the entire burden of triggering.** If agents aren't
activating your skill, the description is the problem.

## Procedure

### Step 1: Audit the content

Before writing or restructuring, classify every piece of content:

| Classification | Where it goes | Example |
|---------------|---------------|---------|
| **Trigger context** | description field | "Use when...", keywords |
| **Core procedure** | SKILL.md body | Step-by-step workflows |
| **Gotchas** | SKILL.md body (early) | Facts that defy assumptions |
| **Deep reference** | references/ | API details, full schemas |
| **Templates** | assets/ or inline | Output format examples |
| **Executable logic** | scripts/ | Validation, data processing |

Ask for each piece: "Would the agent get this wrong without this?"
If no — cut it. If unsure — test it.

### Step 2: Write the description

The description must convey WHEN to use, not just WHAT it does.

**Rules:**
- Imperative phrasing: "Use this skill when..." not "This skill does..."
- Focus on user intent, not implementation
- Err on the side of being pushy — list contexts explicitly
- Include cases where user doesn't name the domain directly
- Under 1024 characters (hard limit)
- Include specific trigger keywords

**Template:**
```yaml
description: >
  [One sentence: what it does]. Use when [primary trigger context],
  [secondary trigger], or when [indirect trigger where user doesn't
  name the domain]. Also use when [edge case trigger].
```

### Step 3: Write the body

**Principles (in priority order):**

1. **Procedures over declarations** — Teach HOW to approach a class of problems,
   not WHAT to produce for a specific instance
2. **Defaults, not menus** — Pick one approach, mention alternatives briefly.
   "Use X. For Y cases, use Z instead." Never present options as equals.
3. **Calibrate control to fragility** — Prescriptive for fragile/sequential tasks,
   flexible when multiple approaches are valid. Most skills have a mix.
4. **Reasoning over rigid directives** — "Do X because Y tends to cause Z" beats
   "ALWAYS do X, NEVER do Y"
5. **Add what the agent lacks, omit what it knows** — No explaining HTTP, PDFs,
   or what a migration is. Jump to what's non-obvious.

**Structure:**
```markdown
# Title

[1-2 sentence purpose statement]

## Gotchas
- [Highest-value content first — facts that defy assumptions]
- [Each gotcha is a concrete correction, not general advice]

## Procedure
### Step 1: ...
### Step 2: ...

## Patterns
[Only if the skill covers multiple approaches to similar problems]
```

### Step 4: Extract to references/

Anything over 500 lines or 5000 tokens goes to `references/`. But tell the
agent WHEN to load each file — conditional references, not a generic "see
references/ for details."

**Good:** "Read `references/api-errors.md` if the API returns a non-200 status"
**Bad:** "See references/ for more information"

### Step 5: Validate

Run through this checklist:

- [ ] Description under 1024 chars
- [ ] Body under 500 lines / 5000 tokens
- [ ] Every instruction passes "would the agent get this wrong without it?"
- [ ] Gotchas are concrete corrections, not general advice
- [ ] Defaults chosen, not menus presented
- [ ] Control calibrated: prescriptive where fragile, flexible where tolerant
- [ ] References have conditional load triggers
- [ ] No explaining what the agent already knows

## Gotchas

- Hook `additionalContext` truncates at **10,000 characters**. If instructions
  must load via hooks (not skills), they must fit this budget.
- `~/.claude/rules/*.md` files load fully with no truncation — use for
  always-loaded conventions that don't fit in a skill.
- CLAUDE.md supports `@path/to/file` imports (max depth 4) — another way
  to load large instruction sets without truncation.
- Agents only consult skills for tasks beyond what they can handle alone.
  Simple one-step requests may not trigger even with a perfect description.
- Content from real domain expertise (runbooks, incident reports, code review)
  dramatically outperforms LLM-generated instructions without project context.
- The most common cause of agents not following instructions: the instruction
  was too vague, didn't apply to the current task, or presented too many
  options without a clear default. Read execution traces to diagnose.

## For Convention Files (PLASTIC.md, CLAUDE.md)

Convention files aren't skills — they load differently. Apply progressive
disclosure by splitting:

| Layer | Mechanism | Budget | Content |
|-------|-----------|--------|---------|
| **Always-on** | `~/.claude/rules/` or hook | <10K chars | Core identity, gotchas, critical procedures |
| **On-demand** | Skills (SKILL.md) | <5K tokens each | Specific workflows activated by task |
| **Deep reference** | `references/` in skills | Unlimited | Full specs, schemas, examples |

**The always-on layer should answer: "What does this agent need to know about
every single task?"** Everything else activates on demand.

## References

- Read `references/agentskills-spec.md` for the complete agentskills.io specification including frontmatter fields, description optimization methodology, evaluation framework, and script design requirements
