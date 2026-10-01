# plastic hook resume

`plastic hook resume` replies to the SessionStart event by printing the state the rows carry: no
day ledger, no file read, rows alone. Session s-1 opens the store with `hook resume` (source
startup), opens two intents, Alpha and Beta, writes a note, then calls `hook resume` again with
the row's source. The second reply must still carry both intents and the note.

Each row gives the source, the exit code, the first line of the reply, and which pieces of state
it names:

| source  | exit | first line                                                                            | names                                        |
| ------- | ---: | -------------------------------------------------------------------------------------- | --------------------------------------------- |
| startup |    0 | Plastic: a new session in store global. Run plastic next before anything else.         | Alpha, Beta, intent new, stopped after Beta  |
| clear   |    0 | Plastic: the context was cleared. The rows below carry the state; run plastic next.    | Alpha, Beta, intent new, stopped after Beta  |
| compact |    0 | Plastic: the session was compacted. The rows below carry the state; run plastic next.  | Alpha, Beta, intent new, stopped after Beta  |
