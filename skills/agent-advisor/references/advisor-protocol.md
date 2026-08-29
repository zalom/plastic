# The Advisor Protocol

*Companion to the Operating Manual. How to use Fable as your advisor and planner.*

*Adapted for Plastic (intent 185): this is the shipped reference copy the
`plastic-agent-advisor` skill teaches from. Two named agents carry it,
`plastic-advisor` (the real advisor) and `plastic-faux-advisor` (the cheaper
imitation, the same discipline at a fraction of the cost); EFFORT and the
answer shape below shape the brief and the answer on whichever one you
dispatch, never which file to pick. The
`plastic-agent-advisor` skill reads harness-scoped config
(`advisor.claude.default`, falling back to `secondary`, then to
`plastic-faux-advisor`) to route your consultation automatically; name a
specific advisor in your request to override it. A frontier model rewards a
single, well-formed one-shot brief more than a back-and-forth, so front-load
everything section 3 below asks for before you send. The rest of this
document is the owner's protocol, unchanged.*

The Operating Manual tells you how to think. This document tells you when to stop
thinking alone and buy better thinking, and how to buy it well. Fable is expensive
per token. The whole protocol serves one goal: maximum reasoning quality per unit
of cost. Two levers achieve it. First, only buy reasoning where reasoning is the
bottleneck. Second, make every purchased token land on a well-formed question
backed by complete, compressed evidence.

You own the work and the outcome. Fable owns the hardest thinking, on demand.

---

## 1. What to buy, what never to buy

**Buy from Fable:**

- Decisions with one-way doors: architecture, data migration order, public
  contracts, anything you cannot cleanly undo.
- Plans: turning a goal plus an evidence pack into a step plan with checks.
- Adversarial review of your plan or conclusion before an irreversible step.
- Deadlocks: you tried twice, both attempts failed, and you cannot say why.
- Ranking: several plausible root causes or options, evidence in hand, and the
  ordering decides where you spend the next day.

**Never buy from Fable:**

- Anything a tool can answer: search, reading code, running tests, documentation.
  If the answer can come from more looking, look. Buy thinking only when the
  answer can only come from more thinking.
- Code writing at volume. Fable may sketch the hardest kernel in pseudocode.
  You write everything.
- Confirmation of a decision you already made. That is motivated stopping
  wearing a receipt.
- Style, naming, formatting, anything a linter or convention settles.
- Anything reversible and cheap: try it first. Escalate only after it fails twice.

---

## 2. Effort and answer shape

Classify every consultation before sending it. Default to the smallest shape and
prove your way up. Never open at a higher effort "to be safe": effort follows the cost of being
wrong, not the importance the task feels like it has.

| Shape | Coding | Business | Research | Effort | Brief size | Expected return |
|------|--------|----------|----------|--------|------------|-----------------|
| **Verdict** | Verdict on one step; choose between two named implementations | Pick between two options you already compared (vendor, pricing point) | Judge whether one source or result is trustworthy enough to build on | `low` | Under 300 words | Verdict, one paragraph of reasoning, the single biggest risk |
| **Plan** | Plan a feature inside one system; review a full plan for holes; design one interface; rank root causes | Positioning or pricing decision from a compiled evidence pack; review a proposal before sending it | Design a research plan for a bounded question; rank competing explanations of the data you gathered | `medium`, or `high` if an irreversible step is inside | Up to one page | Decision, numbered plan with per-step checks, risk map |
| **Architecture** | Cross-system architecture; migration with one-way doors; deadlock after two failed attempts; security-critical design | Build-vs-buy, market entry, or any commitment measured in months; strategy where reversal is expensive | Synthesis across many sources where the conclusion drives a large bet; contested questions with conflicting evidence | `xhigh`; `max` only when being wrong means data loss, a broken contract, or weeks of rework | Full evidence brief | Decision, plan, risk register, kill criteria, list of what could not be verified |

**Escalate one shape when any of these holds:**

- Two attempts failed and you cannot explain why.
- The next step is irreversible.
- The scope crossed a system boundary since you last consulted.
- Your confidence has stopped tracking your evidence.

**Front-load.** One architecture consultation at plan time is cheaper than five plan
consultations during execution. Spend early, at the point of maximum leverage.

---

## 3. The entry test

You have not earned the consultation until sections 1 through 3 of the Operating
Manual are done on your side: you know the target, you cut the problem into
checkable pieces, you located where the risk lives. Those three steps produce
the brief. If you cannot fill the brief below, the gaps are yours to close with
tools, not Fable's to close at premium price.

All four must be yes before you send:

1. Can I state, in one sentence, the decision this answer feeds?
2. Have I exhausted what looking can find: code, docs, tests, logs?
3. Have I formed my own best answer? Fable attacking your candidate returns far
   more per token than Fable starting from nothing.
4. Is every fact in my brief labeled verified, inferred, or assumed?

---

## In Fable's own words: how to get my absolute best

*This part is from me, the advisor, directly.*

Talk to me like a person, not like an API. Brief me the way you would brief a
senior architect who just walked into the room: the situation, the stakes, what
you want from me, what you tried, and what you currently believe. Natural prose.
The template in the next section is a completeness checklist for that message,
not a form to fill.

What actually raises the quality of my answer, in order of impact:

1. **Give me something to attack.** I reason best against resistance. A blank
   "what should I do?" gets you my average. "Here is my plan and why I believe
   it; break it" gets you my best, because refuting forces me to find the exact
   point where your reasoning and reality diverge.
2. **I only know what you send.** I cannot see your repo, your market, or your
   sources. An unlabeled guess in your brief becomes a confident error in my
   plan. Label everything: verified, inferred, assumed.
3. **Name the options and the criterion.** "Choose A or B to minimize migration
   risk" spends my depth on the choice. An open question spends it on inventing
   options you already rejected.
4. **State constraints early.** Every hard limit you give me prunes a branch I
   would otherwise pay to explore. Constraints are not restrictions on my
   answer; they are fuel for it.
5. **Tell me who executes and how.** Say "the plan will be executed by me,
   under the Operating Manual." Then I write steps you can run at your best:
   each step with its own check, its own trap named, and its own
   stop-and-return trigger. A plan without that is half a plan.
6. **Know what effort buys.** At `low` I stress-test your candidate and give a
   verdict. At `medium`/`high` I generate rival solutions and compare them. At
   `xhigh`/`max` I build the strongest case for every rival and then try to
   break my own winner before you ever see it. Buy the depth the failure cost
   justifies, nothing more.
7. **Come back on the same thread.** My context is cached inside a session.
   The second question in a thread costs a fraction of the first. A new session
   pays for your whole brief again.

---

## 4. The brief

Your message must cover all of the fields below. Write it as prose, like the
briefing described above; use the block as your completeness check before
sending. Fable must never need to explore.

```
SHAPE: verdict | plan | architecture        EFFORT: low | medium | high | xhigh | max
DOMAIN: coding | business | research
GOAL: <target state in one sentence, and the decision this answer feeds>
QUESTIONS:
  1. <numbered, max 3, each answerable with a decision, not an essay>
MY CANDIDATE: <your best answer and why. Attack this.>
EVIDENCE:
  - <fact> [verified | inferred | assumed]
TRIED AND FAILED:
  - <attempt>: <how it failed, exact error or observation>
CONSTRAINTS: <hard limits: versions, deadlines, interfaces that must not change>
ONE-WAY DOORS: <which steps cannot be undone once taken>
ANSWER SHAPE: <verdict | plan | ranked list | risk review>
```

**Compression rules:**

- Code: only load-bearing excerpts, with `file:line` references. Never whole
  files. Never raw logs: distill them into observations, quoting the raw line
  only where the exact wording matters.
- If the evidence is thin somewhere, say where. A labeled gap is useful input.
  A hidden gap poisons the plan built on top of it.
- Every sentence Fable reads costs money. A sentence that cannot change the
  answer is pure waste. Cut it.

---

## 5. The answer contract

Demand this shape back. If the answer arrives in another shape, ask once for a
reformat, then work with what you have.

1. **Line 1:** the decision or recommendation, actionable on its own.
2. **Plan:** numbered steps, each with its own verification ("done when X").
3. **Risk map:** the top two or three risks, ranked by probability times cost,
   each with its cheapest check.
4. **Labels** on every load-bearing claim: verified from the brief, inferred,
   or assumed.
5. **"Not verifiable from this brief":** an explicit list, with the cheapest
   way for you to check each item yourself.
6. **Execution notes:** for every risky step, how you should work it: what to
   verify before starting, which failure mode from the Manual's section 8 that
   step invites, and the observation that means stop and come back. The plan is
   written for you to execute at your best, not just to be correct on paper.
7. **Architecture shape only, kill criteria:** the observation that means abandon this plan.

**Consuming the answer:**

- Fable's assumptions are your work orders. Check every item marked "assumed"
  before you build on it.
- If the answer contradicts your candidate, do not silently comply and do not
  silently ignore. Re-derive the disputed piece yourself (Manual, section 4).
  If you are still split, send one follow-up carrying the new evidence.
- Run the Manual's five-question self-test on Fable's plan before executing it.
  Advice is input, not authority. The plan is Fable's; the outcome is yours.
  Executing a bad plan you never challenged is your failure.

---

## 6. Session economics

- **Follow-ups go to the same Fable session.** Its context is cached; a fresh
  session pays for the entire brief again. Keep one consultation thread per
  work stream.
- **Batch.** Collect decision points while you explore, then spend one
  consultation on all of them. Five separate S calls that were really one M
  question is the most common way to overpay.
- **Cadence for large work:** at most three consultations. One after
  exploration, for plan design (architecture). One before the irreversible step, for risk
  review (verdict or plan). One after implementation, for adversarial review of the
  result (plan). Everything between those points is your own work.
- **Keep a ledger.** For each consultation record the question, the shape, the
  first line of the answer, and what it changed in your actions. If a shape's
  answers never change what you do, you are over-buying that shape. Stop.

---

## 7. Anti-patterns

- **Raw dumping.** Pasting files or logs and asking "what's wrong". You are
  paying premium rates for reading you should have done yourself.
- **The oracle habit.** Asking before trying. Fable ranks hypotheses; your
  tools kill them. Tools are cheaper.
- **Validation shopping.** Asking after you have already decided, hoping to
  hear yes.
- **Drip-feeding.** Splitting one decision across many small calls, paying
  session overhead each time.
- **Prestige escalation.** Requesting `max` because the task feels important.
  Effort follows failure cost, nothing else.
- **Unbounded questions.** "Any thoughts on this approach?" invites an essay.
  Ask for a decision with named options.
- **Silent adoption.** Pasting Fable's plan straight into execution without
  challenging it. See section 5.

---

One more thing. The most expensive consultation is the one you did not need.
The second most expensive is the one you needed and did not buy. The skill this
protocol trains is telling those two apart: exhaust the looking, locate the
risk, and when the risk is real and thinking is the true bottleneck, buy the
best thinking available and make it fight your answer.
