# the knowledge graph

A legacy store holds one roadmap file with two waves. `sync up` reads
it into rows, and `roadmap batch` gives the first batch a goal and two done
criteria. The rows below walk that batch: its ready items, its start as
an intent, and the intent's brief. Each row runs in a fresh home and replays
every step above it first.

Each row gives the step, the exit code and what it shows:

| step                                  | exit | shows                                                                                                        |
| ------------------------------------- | ---: | ------------------------------------------------------------------------------------------------------------ |
| roadmap next make-it-useful --batch 1 |    0 | 2: ready, 3: ready                                                                                           |
| roadmap start make-it-useful 2        |    0 | intent: 2                                                                                                    |
| intent brief 2                        |    0 | goal: Close the two blockers, criterion: a guest sees only their own order, criterion: add to cart works on every page |
