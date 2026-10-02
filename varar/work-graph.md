# the work graph

One intent, Alpha, carries two rulings, two nodes and an edge through a full
pass: a node is claimed, fails, is released, is claimed again, and is marked
done. The rows below run the storage kernel's command line in a fresh home
each time, replaying every step up to the check named, then look at what
that check shows.

Each row gives the check, the exit code and what it shows:

| check          | exit | shows                                                                                                 |
| -------------- | ---: | ------------------------------------------------------------------------------------------------------ |
| graph show 1   |    0 | node: n1 done do the thing, node: n2 open build it, edge: n1 to n2                                    |
| intent brief 1 |    0 | ruling: D1 Flowbite styles every delivery (superseded), ruling: D2 Direct mode only, ready: n2 build it |
