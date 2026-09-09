# Spec: Reporting improvements V2

Owner ruling 2026-09-05 (the /goal text), read together with the evidence in
`resources/evidence--display-path.md`.

## Asked

Every report Plastic prints for work reaches the terminal painted in the agreed colors and
layout, bound to the skill that shows state. Each intent has a pre-delivery, an in-delivery, and a
post-delivery report; a roadmap has the same three; the dashboard that prints on continue or on
load project has its own report. No report arrives as plain text in a terminal that can paint.
The font is the terminal's, never Plastic's business. Implementation is free: Ruby stays unless
it cannot do the job.

## Decisions

- D1. The unit is a screen: plain Markdown or text is the floor on every harness, and a painted
  form is substituted wherever the harness can paint (316a1 D3, 317 owner ruling 2026-08-31 stand).
- D2. Painting is a property of the screen family, not of one verb: every report that reaches the
  owner has a ScreenPaint grammar, so the hook can paint it. Day summary, dashboard, roadmap, and
  the new plan screen join the family. Agent report stays internal and unpainted.
- D3. The hook engages on the screen wherever it sits in the reply: prose before it passes
  through, a fence around it is dropped, and the screen region is painted. Opening the reply with
  the screen stays the rule for skills, but a slip no longer costs the colors.
- D4. Every skill that shows state names its report verb and prints it before any prose. A test
  pins the binding for each such skill: continuing, auto, ending, dashboard, roadmap, speccing,
  executing, session start.
- D5. Per intent: `report-screen plan <dir>` is the pre-delivery report (Asked, decisions count,
  steps planned with S1..SN, risks or Needs-you), `state` is in-delivery, `delivered` is
  post-delivery. Per roadmap: `report-screen roadmap <roadmap> plan|state|delivered`.
- D6. The dashboard on continue and on load project is a screen printed by `dashboard.rb` with its
  own grammar and painted form, replacing the Markdown prose.
- D7. Font, panel background, and pixel fidelity are out of scope (318 ceiling). Colors, bold,
  alignment, and glyphs are in scope. Nothing in Plastic reads or sets a font.
- D8. Doctor gains a display check: the hook is registered, and a replay of one screen through it
  returns a painted block. A verbose setting is reported as a warning with the reason.
- D9. Surfaces: Claude Code normal view is the target; the agents view is verified by the owner
  once; Codex and `claude -p` stay plain by contract and the docs say so.
- D10. Delivery order: the painter and grammar work first (they unblock every other intent),
  then the new verbs in parallel, then the skill bindings and the doctor check, then the live
  verification and the release.
- D11. Width: the painter keeps its 115-column design; a screen never reads the terminal size
  (317a1 D14 stands). The owner's terminals are 315 columns wide.
- D12. The existing catalog artifact is the reference for the printed forms; each new screen adds
  its capture to `resources/evidence--display-path.md` on delivery.
