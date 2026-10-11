# plastic hook start

`plastic hook start` replies to the SessionStart event: it names the harness, records it on the
session row, and prints the state the rows carry: no day ledger, no file read, rows alone. Session
s-1 opens the store with `hook start` (source startup) from a Claude Code shell, opens two
intents, Alpha and Beta, writes a note, then calls `hook start` again with the row's source and
session. The second reply must still carry both intents and the note. In the last row Claude
Code has started a new session, s-2, after s-1 ended with the reason clear.

Each row gives the source, the session, the exit code, the first line, the names and the harness:

| source  | session | exit | first line                                                                                    | names                                       | harness     |
| ------- | ------- | ---: | --------------------------------------------------------------------------------------------- | ------------------------------------------- | ----------- |
| startup | s-1     |    0 | Plastic: a new session in store global. Run plastic next before anything else.                | Alpha, Beta, intent new, stopped after Beta | claude-code |
| clear   | s-1     |    0 | Plastic: the context was cleared. The rows below carry the state; run plastic graph resume.   | Alpha, Beta, intent new, stopped after Beta | claude-code |
| compact | s-1     |    0 | Plastic: the session was compacted. The rows below carry the state; run plastic graph resume. | Alpha, Beta, intent new, stopped after Beta | claude-code |
| clear   | s-2     |    0 | Plastic: the context was cleared. The rows below carry the state; run plastic graph resume.   | Alpha, Beta, intent new, stopped after Beta | claude-code |
