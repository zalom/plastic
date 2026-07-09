---
name: plastic-brainstorming
description: "Explore intent requirements and design before implementation. Produces spec.md in the active intent directory."
user-invocable: true
---

# Brainstorming Ideas Into Designs

Help turn ideas into fully formed designs and specs through natural collaborative dialogue.

Announce: "I'm using the brainstorming skill to explore the design for intent {id} — {name}."

Start by understanding the current project context, then ask questions one at a time to refine the idea. Once you understand what you're building, present the design and get user approval.

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. This applies to EVERY project regardless of perceived simplicity.
</HARD-GATE>

## Active Intent Gate

Before proceeding, resolve the active intent:

1. **Detect store:** Read `~/.plastic/projects.yml`, match CWD against registered project paths. If match → project store at `~/.plastic/projects/{slug}/store/`. If no match → global store at `~/.plastic/store/`.
2. **Find active intent:** Read `INDEX.md` from the detected store. Look under `## Active`. If exactly one → use it. If multiple → ask which. If none → refuse: "No active intent. Create one first with /plastic-creating-intent"
3. **Resolve intent directory:** `{store}/store/{id}--{slug}/`

All artifacts go to the intent directory. Never write to external paths.

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every project goes through this process. A todo list, a single-function utility, a config change — all of them. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be short (a few sentences for truly simple projects), but you MUST present it and get approval.

## Checklist

You MUST create a task for each of these items and complete them in order:

1. **Explore project context** — check files, docs, recent commits, read active intent
2. **Ask clarifying questions** — one at a time, understand purpose/constraints/success criteria
3. **Propose 2-3 approaches** — with trade-offs and your recommendation
4. **Present design** — in sections scaled to their complexity, get user approval after each section
5. **Write spec** — save to `{intent_dir}/spec.md` and commit to store repo
6. **Spec self-review** — placeholder scan, consistency, scope, ambiguity
7. **User reviews written spec** — ask user to review before proceeding
8. **Transition to planning** — invoke `plastic-writing-plans`

## Process Flow

The Checklist above states the ordered flow (steps 1-8). For the same flow as a
diagram, read `references/design-principles.md`.

**The terminal state is invoking `plastic-writing-plans`.** Do NOT invoke any other implementation skill. The ONLY skill you invoke after brainstorming is `plastic-writing-plans`.

## The Process

**Understanding the idea:**
- QMD-first (when available): before scanning the store with grep/Read for prior decisions, specs, or outcomes, run `ruby ~/.plastic/scripts/qmd-sync search "<terms>"` to surface candidate, prior, or related intents, then open the authoritative intent file for any hit you act on. The command is a no-op when QMD is absent, so fall back to the existing INDEX.md / file scan.
- Check out the current project state first (files, docs, recent commits)
- Before asking detailed questions, assess scope: if the request describes multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag this immediately. Don't spend questions refining details of a project that needs to be decomposed first.
- If the project is too large for a single spec, help the user decompose into sub-projects: what are the independent pieces, how do they relate, what order should they be built? Then brainstorm the first sub-project through the normal design flow. Each sub-project gets its own spec → plan → implementation cycle.
- For appropriately-scoped projects, ask questions one at a time to refine the idea
- Prefer multiple choice questions when possible, but open-ended is fine too
- Only one question per message - if a topic needs more exploration, break it into multiple questions
- Focus on understanding: purpose, constraints, success criteria

**Exploring approaches:**
- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why

**Presenting the design:**
- Once you believe you understand what you're building, present the design
- Scale each section to its complexity: a few sentences if straightforward, up to 200-300 words if nuanced
- Ask after each section whether it looks right so far
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify if something doesn't make sense

**Design for isolation and clarity, and working in existing codebases:** before
proposing a design, read `references/design-principles.md` for unit-boundary
guidance (what makes a good interface, when a file has grown too large) and
existing-codebase guidance (follow established patterns, fold in targeted
improvements without unrelated refactoring).

## After the Design
**Documentation:**
- Write the validated design (spec) to `{intent_dir}/spec.md` using the `${CLAUDE_PLUGIN_ROOT}/templates/spec.md` form
- Use elements-of-style:writing-clearly-and-concisely skill if available
- Commit to the store repo:
  ```
  cd {store_root} && git add . && git commit -m "docs: spec for intent {id} — {name}"
  ```

**Spec Self-Review:**
After writing the spec document, look at it with fresh eyes:
1. **Placeholder scan:** Any "TBD", "TODO", incomplete sections, or vague requirements? Fix them.
2. **Internal consistency:** Do any sections contradict each other? Does the architecture match the feature descriptions?
3. **Scope check:** Is this focused enough for a single implementation plan, or does it need decomposition?
4. **Ambiguity check:** Could any requirement be interpreted two different ways? If so, pick one and make it explicit.

Fix any issues inline. No need to re-review — just fix and move on.

**User Review Gate:**
After the spec review loop passes, ask the user to review the written spec before proceeding:
> "Spec written and committed to `{intent_dir}/spec.md`. Please review it and let me know if you want to make any changes before we start writing out the implementation plan."

Wait for the user's response. If they request changes, make them and re-run the spec review loop. Only proceed once the user approves.

**Implementation:**
- Invoke `plastic-writing-plans` to create the implementation plan
- Do NOT invoke any other skill. `plastic-writing-plans` is the next step.

## Key Principles

- **One question at a time** - Don't overwhelm with multiple questions
- **Multiple choice preferred** - Easier to answer than open-ended when possible
- **YAGNI ruthlessly** - Remove unnecessary features from all designs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Incremental validation** - Present design, get approval before moving on
- **Be flexible** - Go back and clarify when something doesn't make sense
