# plastic intent end

`plastic intent end ID` gives the harness checked instructions to finish the work,
verify each done criterion, and write an outcome. It does not infer acceptance
from done nodes. The session that delivered the intent closes it, after its code
is merged. Nothing hands the lock to another session.

Before the close, outcome.md records the merge and the architecture map as two
bullets under `## Verification`:

```markdown
## Verification
- Merged: plastic/1--alpha into alpha at abc123
- Architecture map: enola at abc123
```

The command takes only the intent. It closes when the latest review verdict is an
accept that no live node has outdated, every done criterion has a done node with
findings, and the outcome is substantive. Each missing piece hands the agent the
steps for it and closes nothing: the record problems and a missing verdict go to
the finish steps, a missing merge or map bullet goes to the merge check. Plastic
runs no version control command; it records what the agent writes.

With `review.pull_request` set to `required` in config.yml, the outcome also needs a
`Pull request:` bullet. The `Approved:` bullet is the person's approval; without it
the command refuses with exit 3 and the close waits. A second revise verdict uses
up the review rounds and the command refuses with exit 3.

The close writes a completion record with judge `verdict`, and the evidence maps
each criterion key to the done nodes that serve it and their findings. It releases
the delivery lock, prints the intent's files and hands the agent the wind-down step.
A repeated close exits 0, says the intent is already done, offers plastic next and keeps the first record.

The rows below use a disposable fixture with one verified node and outcome.
Each row gives the closure case, the exit code, the status, the completion records and the next line:

| closure case | exit | status | completion records | next line |
| --- | --- | --- | --- | --- |
| request verification | 0 | active | 0 | none |
| unverified close | 0 | active | 0 | none |
| accept delivery | 0 | done | 1 | none |
| repeat closure | 0 | done | 1 | plastic next --project global |
