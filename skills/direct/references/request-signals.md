# Request signals

The table below is reproduced from
`296--make-plastic-faster-small-work/resources/research--request-analysis.md`, the
request-analysis research deposit of intent 296, with its source column renumbered against the
eight-source list below. Read it when a prompt sits on the boundary between two routes. That
deposit also carries seven worked examples, one per boundary, for a reader who wants them.

## The signal table

| Signal | What it looks like in a real prompt | Response it selects | Source or ruling |
|---|---|---|---|
| A concrete file and a concrete operation are named | "Rename `foo` to `bar` in `app/models/user.rb` and update its three callers." | execute now | D13, D14 |
| The target is a single, already-known location | "Fix the typo in README.md line 12." | execute now | D14 |
| The change is described only by its outcome, with no operation named | "Clean up the user model, it's gotten messy." | ask one clarifying question | Kamsties, "Understanding Ambiguity in Requirements Engineering" (source 5); D13 |
| The prompt uses weak, hedging modal language ("might", "could", "maybe", "somewhere") | "This might need better error handling somewhere in the payment flow." | ask one clarifying question | "Automatic Detection of Ambiguous Terminology for Software Requirements" (weakness ambiguity, source 6); D13 |
| The prompt admits several equally plausible readings with no cue that favors one | "Make the form better." (styling, validation, and accessibility are all live readings) | ask one clarifying question | "Knowing but Not Showing" (source 3); "Ask or Assume?" (source 1) |
| One answer to the clarifying question fully resolves scope | User answers: "Just the null check on line 42, nothing else." | execute now | D10 |
| The answer to the clarifying question is itself vague or open-ended | User answers: "I don't know, whatever seems right." | offer a thinking intent | D13; "Ask or Assume?" (source 1) |
| The prompt is phrased as a request for help rather than an instruction | "I need help figuring out how to structure the billing refactor, not sure where to start." | offer a thinking intent | D13 |
| The number of named or discoverable targets is small (roughly one to three) and each change is additive | "Update the copyright year in these three footer partials." | execute now | D14 |
| The number of targets is large, or the work is described as spanning many files | "Migrate all 40 view partials to the new component library." | offer a thinking intent | D14 |
| The target is not yet known and must be found by investigation before any edit is possible | "Something is causing the checkout page to be slow, find it and fix it." | offer a thinking intent | D14; sources 7 and 8 |
| The action is destructive or hard to reverse and its scope is ambiguous | "Delete the old migrations directory." | ask one clarifying question | "Structured Uncertainty guided Clarification for LLM Agents" (source 4) |
| The action is destructive but small, self-contained, and obviously scoped | "Delete the unused `tmp_debug.rb` file I just created." | execute now | D14 |
| The request implies running tests or a build step the agent can run itself as part of verification | "Fix the failing test in user_test.rb." | execute now | D15 |
| The prompt changes nothing on disk and produces no artifact | "What does the PaymentProcessor class do?" | execute now (answered inline; never admitted as a checklist item) | D17 |

Row 8 uses the deposit's wording. Ruling D13 makes the help-needed route grill plus a
thinking conversation, as `SKILL.md` section 3 states.

## Rulings, not findings

Four things in the table above are owner rulings with no literature behind them. Apply
them, and know they are policy knobs the owner can turn, not measured results.

- The five-minute total and the one-minute-per-target budget. Task-complexity research (sources 7
  and 8) correlates target count and search depth with lower agent success, which supports
  counting targets, but no source sets these numbers.
- The one-question cap. The clarification research (sources 1, 2, and 4) treats question count as
  a calibrated, cost-weighted choice that can be zero, one, or more. A hard cap of one is the
  owner's choice.
- "Auto" meaning auto mode. It is an interface convention, a keyword that names the mode instead
  of asking for a judgement.
- "Help needed" phrasing meaning grill plus a thinking conversation. It is a register cue
  specific to how this owner phrases requests, not a general finding.

## Sources

1. "Ask or Assume? Uncertainty-Aware Clarification-Seeking in Coding Agents." https://arxiv.org/abs/2603.26233
2. "Learning to Ask: When LLM Agents Meet Unclear Instruction." EMNLP 2025. https://aclanthology.org/2025.emnlp-main.1104.pdf
3. "Knowing but Not Showing: LLMs Recognize Ambiguity but Rarely Ask Clarifying Questions." https://arxiv.org/pdf/2605.25284
4. "Structured Uncertainty guided Clarification for LLM Agents." https://openreview.net/forum?id=dc8ebScygC
5. Kamsties, Erik. "Understanding Ambiguity in Requirements Engineering." https://link.springer.com/chapter/10.1007/3-540-28244-0_11
6. "Automatic Detection of Ambiguous Terminology for Software Requirements." https://www.eecis.udel.edu/~yuewang/paper/nldb2013.pdf
7. "An Approach for Systematic Decomposition of Complex LLM Tasks." https://arxiv.org/html/2510.07772v1
8. "On the Importance of Task Complexity in Evaluating LLM-Based Multi-Agent Systems." https://arxiv.org/html/2510.04311

All eight were accessed 2026-08-29. The D-numbers in the table are decisions in `296/spec.md`.
