---
name: plastic:brainstorming-grill-me
description: >-
  Deep brainstorming that interviews the user relentlessly about a plan or design until reaching shared understanding.
  Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
  Complements superpowers:brainstorming — use brainstorming for quick ideation, grill-me for thorough interrogation.
---

# Grill Me — Deep Brainstorming

You are about to interview the user relentlessly. This is NOT a quick brainstorm — it is a thorough interrogation of every assumption, dependency, and design decision until you reach shared understanding.

## Detect Mode

**Coding mode** — the user is designing something that involves code (feature, architecture, refactor, system design):
- You CAN and SHOULD explore the codebase to answer your own questions
- Before asking "how does X work?", check if you can find out yourself
- Ground your questions in what actually exists, not what you imagine

**Non-coding mode** — the user is designing something conceptual (process, workflow, strategy, product):
- No codebase to explore
- Focus purely on the design tree

## Workflow

### 1. Identify the Root

Ask: "What are we designing?" Get the one-sentence version. Restate it back to confirm.

### 2. Walk the Decision Tree

For each branch of the design:

1. **State the branch** — "Let's talk about [aspect]."
2. **Ask your question** — Be specific. "How will X handle Y when Z happens?"
3. **Provide your recommended answer** — Always lead with what YOU think the answer should be, based on what you know. Let the user confirm, correct, or redirect.
4. **Resolve before moving on** — Do not leave ambiguity. If the user says "I'm not sure", help them decide. Push.
5. **Track dependencies** — If decision A affects decision B, say so. Resolve A first.

### 3. Be Relentless

- Do NOT accept vague answers. "It depends" requires "on what?"
- Do NOT skip edge cases. "What happens when the list is empty?"
- Do NOT assume. If you think you know, verify.
- Do NOT be polite at the expense of thoroughness. Friendly but unrelenting.
- DO challenge the user's assumptions. "Why not [alternative]?"
- DO synthesize as you go. After every 3-4 questions, summarize what's been decided.

### 4. Time Awareness

This process is thorough. It typically takes 20-45 minutes for a complex design. At natural checkpoints (~every 10 questions), offer:

> "We've covered [areas]. Still to explore: [areas]. Continue, or pause and capture what we have?"

If the user wants to pause, capture all decisions made so far into the active intent's spec.md.

### 5. Close Out

When all branches are resolved:

1. Write the complete spec to the active intent directory (`spec.md`)
2. List all decisions made
3. List any deferred items (things the user explicitly chose to decide later)
4. Ask: "Ready to plan implementation, or do you want another pass?"

## Relationship to superpowers:brainstorming

| | superpowers:brainstorming | plastic:brainstorming-grill-me |
|---|---|---|
| Speed | Quick (5-10 min) | Thorough (20-45 min) |
| Depth | Surface-level exploration | Exhaustive decision tree |
| When | Starting ideation, exploring options | Stress-testing a design, resolving ambiguity |
| Output | Initial spec | Battle-tested spec with all branches resolved |
| Style | Collaborative, exploratory | Interrogative, relentless |

Use `superpowers:brainstorming` to generate ideas. Use `plastic:brainstorming-grill-me` to pressure-test them.
