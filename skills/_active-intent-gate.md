## Active Intent Gate

Before proceeding, resolve the active intent:

1. **Detect store:**
   - Read `~/.plastic/projects.yml`
   - Match CWD against registered project paths
   - If match → project store at `~/.plastic/projects/{slug}/store/`
   - If no match → global store at `~/.plastic/store/`

2. **Find active intent:**
   - Read `INDEX.md` from the detected store
   - Look under `## Active` for intent entries
   - If exactly one active intent → use it
   - If multiple active intents → ask user which one
   - If no active intent → refuse: "No active intent. Create one first with /plastic-creating-intent"

3. **Resolve paths:**
   - Intent directory: `{store}/store/{id}--{slug}/`
   - Spec: `{intent_dir}/spec.md`
   - Plan: `{intent_dir}/plan.md`
   - Checklist: `{intent_dir}/checklist.md`
   - Resources: `{intent_dir}/resources/`
   - Outcome: `{intent_dir}/outcome.md`

All lifecycle artifacts MUST be written to the intent directory. Never write to `docs/superpowers/specs/`, `docs/superpowers/plans/`, or any other external path.
