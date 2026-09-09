---
node: n1
kind: work
files: [path/to/file.rb, test/path_to_file_test.rb]
budget: 100000
---
# n1 - <one-line description of what this node builds>

<Why this node exists and what it changes, in a sentence or two.>

## n1 failure-mode matrix
| Operation | Failure mode | Test |
| --- | --- | --- |
| <operation> | <what goes wrong without this code, and its consequence> | `some_test#test_name` |

## Steps
1. Red: the matrix's tests above, committed before any code.
2. Write the code that makes them pass.
3. Green, then the whole suite at its baseline.

## Proven by
(filled at close from the ledger: commit, suite counts, review verdict)
