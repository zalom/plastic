# A second home rebuilds the same state

A second home holds the printed files of a first home and none of its databases. The first home
opened an intent, wrote two nodes and an edge, approved the intent, claimed and finished one node,
and gave a verdict. The files of that store were then moved to the second home. A call of
`plastic sync up` in the second home reads those files into rows, through the storage kernel's
command line.

Each row gives the state and the comparison of the two homes:

| state                    | comparison         |
| ------------------------ | ------------------ |
| nodes with their states  | equal              |
| edges                    | equal              |
| verdicts                 | equal              |
| findings of a node       | equal              |
