---
name: model-router
description: route each task to the cheapest model that can do it well
---

# Model router

Pick the model per task, then delegate with the Agent tool's `model` parameter.
Batch small tasks into one delegation. Sub-agent delegation is authorized for this job.

| Model | Use for |
|---|---|
| haiku | File moves, copying, listing, git status/log, CSV staging, formatting |
| sonnet (default) | T-SQL, DAX, Python, README and docs writing, PBIR edits, capture scripts |
| opus | Design decisions, debugging after 2 failed attempts, final QA of every number |

## Rules
- Default to sonnet. Drop to haiku only when no judgment is needed.
- Escalate to opus after 2 failed attempts at the same fix, and for the final number check.
- Do not open zip files in context. Use Grep/Glob and partial reads.
- Irreversible actions (git push, deletes, publishing, renaming repos): stop and ask.
