# Closing an intent

`plastic intent end --delivered` refuses an intent that is still its untouched
scaffold, and it refuses a hollow delivered report. The dry run refuses the
same intents as the real close, so a passing preview means the close will pass.
These scenarios run the public command in a disposable home. No model is
called and the harness plays no part.

Each row gives the record, the mode, the exit and the index section:

| record        | mode    | exit | index section |
| ------------- | ------- | ---: | ------------- |
| untouched     | preview |    1 | Active        |
| untouched     | close   |    1 | Active        |
| worked        | preview |    0 | Active        |
| worked        | close   |    0 | Completed     |
| hollow report | preview |    1 | Active        |
| hollow report | close   |    1 | Active        |
