# Feature Modules

Each screen family from the UI/UX Guideline (§7) is one feature module. Modules follow the same internal layout so the codebase stays predictable:

```
features/<module>/
├── application/    # Riverpod notifiers + feature state (freezed)
├── presentation/   # screens + widgets
└── (domain lives in lib/domain, data in lib/data — shared, not per-feature)
```

The **`campaign_list`** module is the reference implementation showing the full pattern (AsyncNotifier → repository → typed AsyncValue UI states). Copy its shape when building the rest.

## Module status

| Module | Design ID | Phase | Status |
|--------|-----------|-------|--------|
| `campaign_dashboard` | W-01 | P1 | placeholder |
| `campaign_list` | W-02 | P1 | **implemented** (table + create/nav) |
| `campaign_wizard` | W-03 | P1 | **implemented** (5-step + draft + submit) |
| `campaign_approval` | W-04 | P1 | **implemented** (2-column + SoD gate) |
| `campaign_detail` | W-05 | P1 | **implemented** (tabs + session ops) |
| `registration` | W-06 | P1 | **implemented** (master search + basket) |
| `bulk_import` | W-07 | P1 | **implemented** (upload → dry-run → commit) |
| `session_readiness` | M-01 | P2 | to build |
| `carpenter_search` | M-02 | P2 | **implemented** (offline-first search → capture) |
| `camera_capture` | M-03 | P2 | **implemented** (5-step flow → sync engine) |
| `offline_queue` | M-04 | P2 | **implemented** (live queue + retry/pause/discard) |
| `crm_queue` | C-01 | P3 | placeholder |
| `crm_case` | C-02 | P3 | **implemented** (3-zone review + optimistic lock) |
| `carpenter_360` | A-01 | P3 | to build |
| `analytics` | A-02 | P3 | placeholder |
| `integrity_ops` | A-03 | P3 | to build |
| `configuration` | AD-01 | P4 | to build |

`placeholder` = routed via `PlaceholderScreen` so the shell is navigable end-to-end (P0). See [`TASK_BREAKDOWN.md`](../../TASK_BREAKDOWN.md) for the task-level plan.
