---
name: plastic-agent-advisor
description: >-
  Consult the advisor for expensive reasoning: one-way doors, plans, adversarial
  review of a plan or conclusion before an irreversible step, a deadlock after two
  failed attempts, or ranking several plausible options. Use when the user asks for
  a second opinion, a hard design decision, an architecture review, help breaking a
  deadlock, or says "ask the advisor". Also sets which advisor is the default when
  asked ("make Fable my advisor", "switch my advisor", "use the real advisor").
user-invocable: true
---

# Agent Advisor

Plastic ships two consultation agents, never dispatched by the auto pipeline, summoned
only when you decide the reasoning is worth buying:

- **`plastic-advisor`** ("the real advisor"): the frontier model itself, expensive,
  billed through usage credits. Spawn it for a few rounds on the hardest problem, then
  close the session.
- **`plastic-faux-advisor`** ("the imitation advisor"): an ordinary model carrying the
  same reasoning discipline inline in its own body, so it reasons the same disciplined
  way at a fraction of the cost. The cheaper default.

## When to consult (and when not to)

Buy a consultation for: decisions with one-way doors (architecture, migration order,
public contracts); turning a goal plus evidence into a step plan with checks;
adversarial review of your plan or conclusion before an irreversible step; a deadlock
after two failed attempts where you cannot say why; ranking several plausible options
when the ordering decides where you spend the next day.

Never buy a consultation for: anything a tool can answer (search, reading code, running
tests, documentation), writing code at volume, confirming a decision you already made,
style or naming a linter would settle, or anything reversible and cheap you have not
tried first. The full buy/never-buy list, the effort table, and the entry test live in
`references/advisor-protocol.md`; read it before writing a brief for the first time in
a session.

## Routing: which advisor answers

1. Read the harness-scoped config: `advisor.claude.default`, the only advisor routing key
   the installer writes. If unset, use `plastic-advisor`, the shipped default.
2. If the user names which advisor they want ("ask the real one", "use Fable", "ask the
   cheap one"), honor that directly and dispatch `plastic-advisor` (the real advisor) or
   `plastic-faux-advisor` (the cheaper imitation) accordingly, overriding step 1 for this
   consultation only.
3. If `advisor.enabled` reads `false`, neither advisor agent nor this skill is
   installed; this step should not be reachable, but if it is, tell the user the
   advisor is disabled and point at "Setting the default" below.
4. Dispatch the resolved agent with a brief built per `references/advisor-protocol.md`
   section 4 (natural prose, the block is a completeness check, not a form to fill).
   State EFFORT and the answer shape explicitly; classify low and prove your way up,
   never open high "to be safe".
5. Consume the answer per the protocol's section 5: run the Operating Manual's
   five-question self-test on the advisor's plan before executing it. Advice is input,
   not authority; the plan is the advisor's, the outcome is yours.

Read the resolved config value with:

```bash
ruby ~/.plastic/scripts/read-config advisor.claude.default --project <repo>
```

(Omit `--project` outside a registered project; falls back to the global value.)

## Setting the default advisor

When asked to change the default ("make Fable my advisor", "switch my advisor", "use
the cheaper one by default"), present the two options in plain language and write the
choice:

- **Faux Fable** (`plastic-faux-advisor`, recommended): an ordinary model carrying the
  frontier reasoning instructions. Much cheaper, available on any plan, reasons in the
  same disciplined way.
- **Fable 5** (`plastic-advisor`): the frontier model itself. The strongest reasoning
  available, billed through usage credits, so summon it for a few rounds and close it.

These are the same two options the installer offers at install and update time. Write
the choice to `advisor.claude.default` in the global `~/.plastic/config.yml` (or the
project's `.plastic_store/config.yml` when the user scopes the change to one project):
read the file as YAML, set `advisor.claude.default` to the agent name (`plastic-advisor`
or `plastic-faux-advisor`, never a model name or nickname), and write it back. Confirm
the new default back to the user in one line.

## References

- `references/advisor-protocol.md`: the full shipped Advisor Protocol (what to buy,
  effort and answer shape, the entry test, how to write a brief that earns its cost, the
  answer contract, session economics, anti-patterns). Read it before the first
  consultation in a session; the second consultation in the same advisor thread costs a
  fraction of the first, so keep follow-ups on one thread rather than opening a new one.
