# ACTION_1: Drive the reporting-v2 roadmap

The parent intent does no code itself. Its operations are record and orchestration; each has a
failure mode and the check that catches it.

| Operation | Failure mode | Caught by |
| --- | --- | --- |
| Evidence gathering | a claim without a capture or a number | every claim in `resources/evidence--display-path.md` names its probe file |
| Branch intent scaffold | hand-authored intent files | all seven created through `new-intent`; `validate-intent` at end-intent |
| Roadmap file | entry status drifts from INDEX | `roadmap-savepoint rebuild` and the roadmap skill's sync verb before each batch |
| Batch dispatch | two leads edit ScreenPaint's registry body at once | batch-2 branches add files under `scripts/lib/screens/`; merge gate runs the suite on alpha |
| Close | outcome without proof rows | `end-intent` hollow-close gate (exit 7) needs matrix tables per step |
