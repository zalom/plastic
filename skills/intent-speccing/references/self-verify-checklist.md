# Self-Verify Checklist

Run this before presenting spec.md (SKILL.md step 7). Ten checks: the four points of
brainstorming's proven Spec Self-Review, merged with the six binding output checks this skill
adds. Fix any failing check, then re-verify from the top; do not present a spec that fails one of
these.

## Brainstorming's four Spec Self-Review points

1. **Placeholder scan.** Any "TBD", "TODO", incomplete section, or vague requirement left in the
   draft? Fix it before moving on.
2. **Internal consistency.** Do any two sections contradict each other? Does the Approach
   actually match what Goals and Acceptance Criteria describe?
3. **Scope check.** Is this spec focused enough for a single implementation plan, or does the
   Problem actually describe more than one independent piece of work that needs decomposing
   first?
4. **Ambiguity check.** Could any requirement be read two different ways? If so, pick one
   reading and rewrite the line so only that reading survives.

## The six binding output checks

5. **No template placeholder text remains.** No literal `<intent name>`, `<alternative>`, `...`,
   sample bracket text, or other template filler from `templates/spec.md` survives anywhere in
   the artifact.
6. **No header line.** The file starts at the `# Spec:` heading; there is no `Tier:` line (removed in 2.0, intent 304).
7. **All 8 sections present, in template order.** Problem, Goals, Non-Goals, Approach,
   Alternatives Considered, Decisions, Acceptance Criteria, Open Questions, each present once, in
   that order, none merged into another.
8. **Every `## Insights` ruling is traceable to a spec line.** Walk the Insights log entry by
   entry: each one lands in some section of the spec. Where two rulings conflict, the later one
   (further down the log) is the one that landed, and the earlier one does not silently persist
   in a different section.
9. **Acceptance criteria are concretely checkable.** Each Acceptance Criteria bullet reads as a
   fact a reviewer can confirm true or false by inspection, a command, or a named file, not a
   quality judgment a reviewer would have to interpret.
10. **No em-dashes or en-dashes anywhere in the artifact.** Scan the full file; replace any dash
    glyph with a comma, period, parenthesis, or colon.
