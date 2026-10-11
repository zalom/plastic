# plastic init

`plastic init` finds the agent harnesses installed on this machine, lists them with every
found one picked, and installs Plastic into each harness the person picks. A harness counts
as found when its settings folder is in the home or its program is on the PATH. With no
terminal, the call prints the numbered list and a next line that asks the person, and
writes nothing. `plastic init ANSWER` then reads the person's answer: numbers separated by
commas, `a` for all, or `q` to leave with no change.
