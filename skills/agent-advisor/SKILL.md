---
name: plastic-agent-advisor
description: >-
  Consult the advisor for expensive reasoning: one-way doors, plans, adversarial
  review of a plan or conclusion before an irreversible step, a deadlock after two
  failed attempts, or ranking several plausible options. Use when the user asks for
  a second opinion, a hard design decision, an architecture review, help breaking a
  deadlock, or says "ask the advisor". Also sets which advisor is the default when
  asked ("make Primary Advisor my default", "switch my advisor", "use Secondary Advisor").
user-invocable: true
---

# Agent Advisor

Plastic ships two consultation agents, never dispatched by the auto pipeline, summoned
only when you decide the reasoning is worth buying:

- **Primary Advisor** (`plastic-primary-advisor`): Fable at medium effort. Use it for
  normal consultation.
- **Secondary Advisor** (`plastic-secondary-advisor`): Fable at high effort. Use it only
  as an explicit escalation for harder or higher-risk reasoning.

## When to consult (and when not to)

Buy a consultation for: decisions with one-way doors (architecture, migration order,
public contracts); turning a goal plus evidence into a step plan with checks;
adversarial review of your plan or conclusion before an irreversible step; a deadlock
after two failed attempts where you cannot say why; ranking several plausible options
when the ordering decides where you spend the next day.

Never buy a consultation for: anything a tool can answer (search, reading code, running
tests, documentation), writing code at volume, confirming a decision you already made,
style or naming a linter would settle, or anything reversible and cheap you have not
  tried first. The full buy/never-buy list, answer-shape table, and entry test live in
`references/advisor-protocol.md`; read it before writing a brief for the first time in
a session.

## Routing: which advisor answers

1. Read the harness-scoped config: `advisor.claude.default`, the only advisor routing key
   the installer writes. If unset, use `plastic-primary-advisor`, the shipped default.
2. If the user explicitly asks for Primary Advisor or Secondary Advisor, honor that choice for
   this consultation. Otherwise, dispatch the configured agent from step 1.
3. If `advisor.enabled` reads `false`, neither advisor agent nor this skill is
   installed; this step should not be reachable, but if it is, tell the user the
   advisor is disabled and point at "Setting the default" below.
4. Dispatch the resolved agent with a brief built per `references/advisor-protocol.md`
   section 4 (natural prose, the block is a completeness check, not a form to fill).
   State the answer shape explicitly. Primary uses medium effort and Secondary uses high;
   only an explicit owner config override changes either value.
5. Consume the answer per the protocol's section 5: run the Operating Manual's
   five-question self-test on the advisor's plan before executing it. Advice is input,
   not authority; the plan is the advisor's, the outcome is yours.

Read the resolved config value with:

```bash
ruby ~/.plastic/scripts/read-config advisor.claude.default --project <repo>
```

(Omit `--project` outside a registered project; falls back to the global value.)

## Setting the default advisor

When asked to change the default, present the two options in plain language and write the
choice:

- **Primary Advisor** (`plastic-primary-advisor`, recommended): Fable at medium effort.
- **Secondary Advisor** (`plastic-secondary-advisor`): Fable at high effort.

These are the same two options the installer offers at install and update time. Write
the choice to `advisor.claude.default` in the global `~/.plastic/config.yml` (or the
project's `.plastic_store/config.yml` when the user scopes the change to one project):
read the file as YAML, set `advisor.claude.default` to the agent name (`plastic-primary-advisor`
or `plastic-secondary-advisor`, never a model name or nickname), and write it back. Confirm
the new default back to the user in one line.

## References

- `references/advisor-protocol.md`: the full shipped Advisor Protocol (what to buy,
  answer shape, the entry test, how to write a brief that earns its cost, the
  answer contract, session economics, anti-patterns). Read it before the first
  consultation in a session; the second consultation in the same advisor thread costs a
  fraction of the first, so keep follow-ups on one thread rather than opening a new one.
