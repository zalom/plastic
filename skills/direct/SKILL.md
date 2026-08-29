---
name: plastic-direct
description: Use when a prompt asks for a change, a fix, an edit, a file, or an answer, and no thinking conversation is open on an intent. Judges whether the work is small enough to run right now, asks one clarifying question when one answer would settle it, or offers a thinking intent when it would not. Do not use for a prompt that says "auto" or "continue", a prompt asking to start a new intent, or a prompt inside an open thinking conversation, which belong to plastic-auto, plastic-intent-continuing, plastic-intent-creating, and plastic-intent-speccing.
user-invocable: false
---

# Direct mode

Route the prompt in one read, then act. Direct work runs inline in this session, never through a
dispatched agent, unless the user asks for agents.

## 1. Estimate before you start

Judge the prompt alone, before doing any of the work:

1. Count the targets the prompt names, or that one grep finds.
2. Require each change to be a named operation on a known target (rename this, add a check there,
   delete that line), not an outcome ("clean it up", "make it faster").
3. Budget about one minute per target and sum.
4. At or under five minutes, run it now. Five minutes is an owner ruling, not a measured
   threshold.
5. A bounded sum above five minutes, offer a dedicated intent.
6. An unknown target, or a change described only by its outcome, cannot be bounded. Ask one
   question when one answer would supply the missing operation or target. Otherwise offer a
   thinking intent. A target that only investigation can find is never settled by one
   question.

Tests or a build the prompt implies do not count against the budget. Verification is part of
direct work, not a reason to leave direct mode.

## 2. One question, then run

A clarifying question is allowed in direct mode and does not by itself turn the request into a
thinking intent. Ask one, then run. If the answer is still vague, offer a thinking intent rather
than asking a second question or guessing.

## 3. The routes

| What the prompt looks like | Where it goes |
|---|---|
| Clear, and bounded at or under five minutes | Run it now, inline |
| Clear, but the bounded estimate is above five minutes | Offer a dedicated intent, `plastic-intent-creating` |
| Vague, and one answer would resolve it | Ask one clarifying question, then run |
| Still vague after that one answer | Offer a thinking intent, `plastic-intent-speccing` |
| Phrased as needing help rather than as an instruction | Offer grill plus a thinking conversation, `plastic-intent-speccing` |
| Says "auto" explicitly | Hand off to `plastic-auto` |

Read `references/request-signals.md` when a prompt sits on the boundary between two routes, for
the 15 observable signals and the response each one selects.

## 4. Record and verify

- Verification in direct mode is the UI, the tests, or the user. There is no reviewer agent per
  item.
- Only a prompt that changes something on disk or produces an artifact becomes a checklist item.
  A pure question is answered inline and recorded nowhere.
- Direct work records into the day ledger that the per-session pointer names. Assume the pointer
  exists. Never write it.

## 5. What direct does not take

The capture hook detects `auto` and `continue` before you read the prompt, so defer rather than
keyword-match them yourself. `auto` goes to `plastic-auto`, and `continue` goes to
`plastic-intent-continuing`. On `auto` with no registered intent, route through
`plastic-intent-creating` first, because auto requires a registered intent. A prompt that arrives
inside an open thinking conversation belongs to that conversation, not here.
