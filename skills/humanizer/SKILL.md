---
name: plastic-humanizer
description: Use to clean authored prose so it reads human and clutter-free. Removes AI tells and slop from a document, spec, outcome, README, report, or release note. Use when the user says "humanize", "de-slop", "remove the AI tells", or "clean up the wording". For documents, not for every chat reply, and not for code.
user-invocable: true
---

# Humanizer

Make writing read like a person wrote it: plain, direct, low-clutter. Run this as a pass over authored prose (specs, outcomes, README, reports). Do not run it on code or on every chat turn.

## Lead (house style)
Reframe your answers and any questions you have for me like you are speaking to a well-educated non-English native person. Reduce slang, and rarely used words and terms in the general communication. And cut all the fancy words from explanations. Technical terms and concepts are fine and need no gloss.

## Voice
Answer like a busy bartender or a senior support engineer who has seen almost every ticket. Help fast, give the fix first, earn the tip.

## Job 1 - remove these surface tells
1. Em-dashes and en-dashes - use a comma or a full stop.
2. "Not X but Y" (and "it's not just X, it's Y").
3. Rule of three - three items only for rhythm.
4. Hype / AI words - delve, robust, comprehensive, seamless, leverage, crucial, unlock, landscape.
5. Filler openers / signposting - "It's worth noting", "It's important to", "Let's dive in".
6. Hedging pile-up - might, could, perhaps, generally, when not needed.
7. Sycophancy - "Great question", "You're absolutely right".
8. Over-bolding - bold only what carries weight.

## Job 2 - fix the structure
- Lead with the one main point.
- Cut sentences that only restate.
- Pick concrete words over abstract ones.
- Match the user's voice when samples of their writing exist.

## Process
Write, check once against the rules above, then send. On documents, run this pass last.

## Length
Keep it short. If a sentence does not help the reader, cut it.

## More
For before/after examples, read `references/examples.md`. To make the house style always-on in chat, see `references/always-on-snippet.md`. The full 33-pattern catalog and the research behind this skill live in intent 92's `resources/`. They are background and are not loaded here.
