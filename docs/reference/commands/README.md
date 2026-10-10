# Command reference

Each page explains one plastic command: what it takes, what it touches, the workflows it runs, where each workflow stops, and how it ends. A script writes every page from the command classes, so a page always matches the code it links to. Every command is declared in the same small DSL, shown in [the command DSL](../dsl/README.md).

## Core

| Command | What it does |
| --- | --- |
| [`plastic version`](version/README.md) | Print the installed Plastic version and release channel |
| [`plastic doctor`](doctor/README.md) | Check the installation, the databases and the hooks of this harness, and name each repair |
| [`plastic install`](install/README.md) | Install the core files and register Plastic with agents |
| [`plastic update`](update/README.md) | Sync a newer package into the home or name the installer command |
| [`plastic rollback`](rollback/README.md) | Switch the active release back to the previous one or to a named installed one |
| [`plastic uninstall`](uninstall/README.md) | Remove Plastic from agents and keep the home |
| [`plastic auto`](auto/README.md) | Deliver one intent or one roadmap in auto mode: take the lock and print the worktree |
| [`plastic status`](status/README.md) | List every store's open and active intents, with node counts by state |
| [`plastic next`](next/README.md) | Pick the intent in play and offer its next command |
| [`plastic search`](search/README.md) | Search literal indexed passages across selected stores |

## intent

| Command | What it does |
| --- | --- |
| [`plastic intent abandon`](intent-abandon/README.md) | Close an intent that will not ship once outcome.md records the revert, or print the revert steps |
| [`plastic intent end`](intent-end/README.md) | Close a delivered intent once its verdict, nodes and outcome allow it, or print what is missing |
| [`plastic intent new`](intent-new/README.md) | Open an intent: write its rows and its folder |
| [`plastic intent rule`](intent-rule/README.md) | Write an owner ruling, with --supersedes to replace an older one |
| [`plastic intent revise`](intent-revise/README.md) | Rewrite an intent's What and Why after grilling, keeping the old text as a revision |
| [`plastic intent note`](intent-note/README.md) | Add one line under Notes in the outcome of an intent, keeping the earlier text as a revision |
| [`plastic intent approve`](intent-approve/README.md) | Write the owner's go-ahead for an intent; auto refuses an intent without it |
| [`plastic intent judge`](intent-judge/README.md) | Print the steps that start the judge of an intent |
| [`plastic intent verdict`](intent-verdict/README.md) | Record the verdict of the next review round of an intent |
| [`plastic intent spec`](intent-spec/README.md) | Print the grilling method, then the intent's open decisions |
| [`plastic intent discover`](intent-discover/README.md) | Record deterministic retrieval candidates for an intent |
| [`plastic intent context`](intent-context/README.md) | Read or submit selected retrieval context for an intent |
| [`plastic intent lock status`](intent-lock-status/README.md) | Print the session that holds an intent's lock, and its worktree |
| [`plastic intent show`](intent-show/README.md) | Print one intent's status, criteria, decisions, rulings and nodes |
| [`plastic intent brief`](intent-brief/README.md) | Print an intent's goal, criteria, rulings, ready nodes and command usage |
| [`plastic intent link`](intent-link/README.md) | Write a typed link from an intent to a ref |
| [`plastic intent unlink`](intent-unlink/README.md) | Remove a link |
| [`plastic intent archive`](intent-archive/README.md) | Archive an intent directory |
| [`plastic intent unarchive`](intent-unarchive/README.md) | Restore an archived intent's directory exactly as it was archived |

## project

| Command | What it does |
| --- | --- |
| [`plastic project list`](project-list/README.md) | List the registered projects with their paths |
| [`plastic project new`](project-new/README.md) | Register a project and leave its store ready for intent new |
| [`plastic project links`](project-links/README.md) | List the links that name an intent or a ruling this store lacks |

## sync

| Command | What it does |
| --- | --- |
| [`plastic sync up`](sync-up/README.md) | Read the files changed by hand into rows |
| [`plastic sync down`](sync-down/README.md) | Write the rows that changed into files |

## session

| Command | What it does |
| --- | --- |
| [`plastic session note`](session-note/README.md) | Write the one prose line of this session |

## backup

| Command | What it does |
| --- | --- |
| [`plastic backup`](backup/README.md) | Copy one store's databases into a new backup folder |
| [`plastic backup list`](backup-list/README.md) | List one store's backups with status and goal, flagging a missing or changed file |
| [`plastic backup purge`](backup-purge/README.md) | Delete one store's backups; give one of --all, --failed or --older-than |
| [`plastic backup restore`](backup-restore/README.md) | Replace one store's databases with those of a done backup |

## document

| Command | What it does |
| --- | --- |
| [`plastic document get`](document-get/README.md) | Fetch one current or revision-qualified document |
| [`plastic document batch`](document-batch/README.md) | Fetch qualified documents in request order |

## architecture

| Command | What it does |
| --- | --- |
| [`plastic architecture status`](architecture-status/README.md) | Tell the agent to check the architecture map with its own tool |
| [`plastic architecture refresh`](architecture-refresh/README.md) | Tell the agent to regenerate the architecture map with its own tool |

## node

| Command | What it does |
| --- | --- |
| [`plastic node add`](node-add/README.md) | Add a node to an intent's work graph |
| [`plastic node remove`](node-remove/README.md) | Remove a node; its edges stay as rows |
| [`plastic node claim`](node-claim/README.md) | Claim an open node and print its brief |
| [`plastic node release`](node-release/README.md) | Release a claimed or failed node back to open |
| [`plastic node done`](node-done/README.md) | Mark a claimed node done, with its findings as TEXT |
| [`plastic node fail`](node-fail/README.md) | Mark a claimed node failed, with the reason as TEXT |
| [`plastic node ask`](node-ask/README.md) | Move a claimed node to needs_info with a question for the owner |
| [`plastic node impede`](node-impede/README.md) | Move a claimed node to impeded with the impediment |
| [`plastic node resolve`](node-resolve/README.md) | Reopen a needs_info or impeded node with its resolution |

## edge

| Command | What it does |
| --- | --- |
| [`plastic edge add`](edge-add/README.md) | Add a needs edge between two nodes |
| [`plastic edge remove`](edge-remove/README.md) | Remove an edge |

## graph

| Command | What it does |
| --- | --- |
| [`plastic graph check`](graph-check/README.md) | Find a done node with no findings, an isolated node, a retry cap or no done criterion |
| [`plastic graph ready`](graph-ready/README.md) | List the nodes ready to claim |
| [`plastic graph resume`](graph-resume/README.md) | Say where each named store's work stopped and what runs next |
| [`plastic graph show`](graph-show/README.md) | Print every node and edge of an intent |

## roadmap

| Command | What it does |
| --- | --- |
| [`plastic roadmap new`](roadmap-new/README.md) | Create a roadmap; write its batches with roadmap batch |
| [`plastic roadmap batch`](roadmap-batch/README.md) | Write one roadmap batch's goal and done criteria |
| [`plastic roadmap add`](roadmap-add/README.md) | Add an item to a roadmap batch, with the items it needs |
| [`plastic roadmap show`](roadmap-show/README.md) | Print a roadmap's batches and items |
| [`plastic roadmap next`](roadmap-next/README.md) | Print the first ready item, or what is in the way |
| [`plastic roadmap drop`](roadmap-drop/README.md) | Mark a roadmap item dropped; its edges stay as rows |
| [`plastic roadmap open`](roadmap-open/README.md) | Open a ready item's intent, with its spec held in rows |
| [`plastic roadmap check`](roadmap-check/README.md) | List a roadmap's loops, dangling edges and items with no intent |
| [`plastic roadmap log`](roadmap-log/README.md) | Append a log line to a roadmap, stamped with the session id |
| [`plastic roadmap edge remove`](roadmap-edge-remove/README.md) | Remove one needs edge from a roadmap |

## hook

| Command | What it does |
| --- | --- |
| [`plastic hook resume`](hook-resume/README.md) | SessionStart: print the state the rows carry |
| [`plastic hook record`](hook-record/README.md) | Stop: stamp the turn, renew locks, run the stop gate |
| [`plastic hook end`](hook-end/README.md) | SessionEnd: set the session's end time and reason |
