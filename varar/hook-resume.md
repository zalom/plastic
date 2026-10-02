# plastic hook resume

`plastic hook resume` replies to the SessionStart event by printing the state the rows carry: no
day ledger, no file read, rows alone. Session s-1 opens the store with `hook resume` (source
startup), opens two intents, Alpha and Beta, writes a note, then calls `hook resume` again with
the row's source and session. The second reply must still carry both intents and the note. In
the last row Claude Code has started a new session, s-2, after s-1 ended with the reason clear.

Each row gives the source, the session, the exit code, the first line and the names:

| source  | session | exit | first line                                                                             | names                                       |
| ------- | ------- | ---: | -------------------------------------------------------------------------------------- | ------------------------------------------- |
| startup | s-1     |    0 | Plastic: a new session in store global. Run plastic next before anything else.         | Alpha, Beta, intent new, stopped after Beta |
| clear   | s-1     |    0 | Plastic: the context was cleared. The rows below carry the state; run plastic next.    | Alpha, Beta, intent new, stopped after Beta |
| compact | s-1     |    0 | Plastic: the session was compacted. The rows below carry the state; run plastic next.  | Alpha, Beta, intent new, stopped after Beta |
| clear   | s-2     |    0 | Plastic: the context was cleared. The rows below carry the state; run plastic next.    | Alpha, Beta, intent new, stopped after Beta |
