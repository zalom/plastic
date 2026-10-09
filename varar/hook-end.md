# plastic hook end

`plastic hook end` answers the SessionEnd event: it sets the end time and the reason on the
session's row in local.db and nothing else, because only that event knows why a session ended.
Session s-1 opens the store with `hook resume` before each row. A call that names no session, or an option
the hook does not take, records nothing.

Each row gives the arguments, the end event, the session, the exit code, the message and the ended row:

| arguments       | end event           | session | exit | message                                                    | ended row                             |
| --------------- | ------------------- | ------- | ---- | ---------------------------------------------------------- | ------------------------------------- |
| (none)          | {"reason":"clear"}  | s-1     | 0    | none                                                       | s-1 claude-code, no turn, ended clear |
| --harness codex | {"reason":"logout"} | s-1     | 0    | plastic: invalid option: --harness plastic hook end        | s-1 claude-code, no turn, open        |
| (none)          | {}                  | none    | 0    | plastic hook: the event names no session; nothing recorded | s-1 claude-code, no turn, open        |
