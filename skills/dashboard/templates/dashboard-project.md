# 📦 {{slug}} · Project Board — {{date}}

{{description}}

**Recently worked** · last 24h
{{recently_worked.lines}}

## Where we go next · Value × Effort

|  | Small effort | Big effort |
|---|---|---|
| **High value** | ⚡ **Quick win** · {{matrix.quick_win.count}} | ★ **Next big thing** · {{matrix.next_big.count}} |
| **Low value** | → **Defer (agent)** · {{matrix.defer.count}} | ⚑ **Triage** · {{matrix.triage.count}} |

**⚡ Quick win** — small effort, high value
{{matrix.quick_win.lines}}

**★ Next big thing** — big effort, high value
{{matrix.next_big.lines}}

**→ Defer (agent)** — small effort, low value
{{matrix.defer.lines}}

**⚑ Triage** — big effort, low value
{{matrix.triage.lines}}

🔬 **Research → agent**
{{matrix.research.lines}}

## Intents · active {{counts.active}} · done {{counts.done}} · future {{counts.future}}

**Active**
{{active.lines}}

**Future**
{{future.lines}}

**Legend** · ○ What ◔ Why ◑ How ◕ Exec ● Done · ⚡ quick win ★ big → defer ⚑ triage 🔬 research

**What would you like to work on next?** (type an **intent id**, or **global** to go back)
