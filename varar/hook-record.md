# plastic hook record

`plastic hook record` answers the Stop event: it stamps the session's last turn on its row in
local.db and prints nothing, so the session stops. With `--end` it answers SessionEnd instead
and sets only the end time and the reason. Session s-1 opens the store with `hook resume`
before each row. A call that names no session records nothing, and a call that names a new
session opens a row for it. No lock is held, so the stop gate has nothing to block.

Each row gives the arguments, the event, the session, the exit code, the message and the row:

| arguments       | event              | session | exit | message                                                | row                                  |
| --------------- | ------------------ | ------- | ---: | ------------------------------------------------------ | ------------------------------------ |
| (none)          | {}                 | s-1     |    0 | none                                                   | s-1 claude-code, turn stamped, open  |
| --harness codex | {}                 | s-1     |    0 | none                                                   | s-1 codex, turn stamped, open        |
| --end           | {"reason":"clear"} | s-1     |    0 | none                                                   | s-1 claude-code, no turn, ended clear |
| (none)          | {}                 | none    |    0 | plastic hook: the event names no session; nothing recorded | s-1 claude-code, no turn, open    |
| (none)          | {}                 | s-9     |    0 | none                                                   | s-9 claude-code, turn stamped, open  |
| (none)          | not json           | s-1     |    0 | plastic hook: the event is not a JSON object; read as empty | s-1 claude-code, turn stamped, open |
