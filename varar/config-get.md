# plastic config get

`plastic config get KEY` prints the value of one setting: the shipped default, then the global
section, then with `--harness NAME` that harness's section, the later one winning. The rows
below run the storage kernel's command line in a fresh home each time, as session s-1.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| ----- | ---- | ---- | ------ | --------- |
| none | `config get screens` | 0 | screens true | plastic config set screens VALUE |
| config set screens false | `config get screens` | 0 | screens false | plastic config set screens VALUE |
| config set screens false --harness codex | `config get screens --harness codex` | 0 | screens false | plastic config set screens VALUE --harness codex |
| config set screens false --harness codex | `config get screens` | 0 | screens true | plastic config set screens VALUE |
| none | `config get nothing.here` | 2 | no setting nothing.here; plastic config list names them | none |
