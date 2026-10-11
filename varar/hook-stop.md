# plastic hook stop

`plastic hook stop` answers the Stop event: it stamps the session's last turn on its row in
local.db and prints nothing, so the session stops. Session s-1 opens the store with `hook start`
before each row, and that start records the harness claude-code. The stop keeps the harness the
start recorded. A call that names no session records nothing, and a call that names a new
session opens a row for it with no harness. No lock is held, so the stop gate has nothing to block.

Each row gives the arguments, the event, the session, the exit code, the message and the row:

| arguments       | event    | session | exit | message                                                     | row                                 |
| --------------- | -------- | ------- | ---: | ----------------------------------------------------------- | ----------------------------------- |
| (none)          | {}       | s-1     |    0 | none                                                        | s-1 claude-code, turn stamped, open |
| --harness codex | {}       | s-1     |    0 | plastic: invalid option: --harness plastic hook stop        | s-1 claude-code, no turn, open      |
| (none)          | {}       | none    |    0 | plastic hook: the event names no session; nothing recorded  | s-1 claude-code, no turn, open      |
| (none)          | {}       | s-9     |    0 | none                                                        | s-9 no harness, turn stamped, open  |
| (none)          | not json | s-1     |    0 | plastic hook: the event is not a JSON object; read as empty | s-1 claude-code, turn stamped, open |
