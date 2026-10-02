# plastic session note

`plastic session note TEXT` keeps one line on the session row, so the next `hook resume` reply
carries it. Session s-1 opens the store with `hook resume`, writes the notes in the row in
order, then calls `hook resume` again with the source clear. A later note replaces the earlier
one. A call with no text, or with no session, writes nothing and stops.

Each row gives the notes, the session, the exit code, the result and the note line:

| notes                        | session | exit | result                                            | note line               |
| ---------------------------- | ------- | ---: | ------------------------------------------------- | ----------------------- |
| stopped after Beta           | s-1     |    0 | note: stopped after Beta                          | note: stopped after Beta |
| first, second                | s-1     |    0 | note: first / note: second                        | note: second            |
| (none)                       | s-1     |    2 | missing TEXT                                      | none                    |
| stopped after Beta           | none    |    1 | the call names no session; set PLASTIC_SESSION    | none                    |
