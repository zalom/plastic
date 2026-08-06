# Lifecycle and Savepoints

This chapter holds the subagent report-home depth for how an insight reaches the intent when the writer cannot write the file itself.

Background sessions and dispatched sub-agents do not write the insight themselves. They carry
each nugget home in the completion report's `insights:` field, and the orchestrator (or any
agent that can write the file) persists it via the helper. A session that cannot write the
intent file still returns its report, so the insight survives.

For the stage table (What/Why/How/Exec, deliverable, owning skill), see PLASTIC.md's Lifecycle
Stages section; each named skill's own `references/` holds that stage's own depth.
