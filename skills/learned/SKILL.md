---
name: learned
description: Extract and persist learnings, corrections, and patterns from the current session to memory. Invoke immediately after any user correction or rejected suggestion, after validation of a non-obvious choice, when the user says "remember this" / "catat ini", when a new preference, tool, workflow, or project decision surfaces, or at session end via /learn.
---

## Step 1 — Scan the conversation

Read back through the full current conversation. Tag each finding:

| Signal | Category | Memory type |
|--------|----------|-------------|
| "no", "wrong", "don't", "stop doing", rejection of suggestion | Correction | `feedback` |
| "yes exactly", "perfect", implicit acceptance of unusual choice | Validation | `feedback` |
| Tool/workflow/style choice revealed | Preference | `user` or `feedback` |
| Decision, constraint, deadline, architecture choice | Project fact | `project` |
| External system, URL, dashboard, doc location | Pointer | `reference` |

**Skip anything that is:**
- Derivable from reading the code or git history
- Code structure — module/entity maps, route lists, file layouts, tech-stack dumps. That belongs to graphify (`graphify-out/`) and each project's CLAUDE.md; saved here it only goes stale
- Already covered by MEMORY.md or global rules (CLAUDE.md, LANGUAGE.md, KARPATHY.md)
- Ephemeral task state

**Asked to remember something on that list** ("remember this module structure", "remember this file layout")? Don't drop it silently. Ask what was non-obvious about it — the gotcha, the decision behind it, why it surprised — and save that instead.

---

## Step 2 — Check existing memories

Read `MEMORY.md` (already in context at session start). For each finding:
- Existing file already covers it → **update that file**
- A correction contradicts an existing memory → **fix or delete that memory** and its index line. A wrong memory is worse than a missing one — it gets recalled as fact in future sessions
- Genuinely new → **create new file**

Never duplicate. When in doubt, update.

---

## Step 3 — Write each memory

**Memory directory.** The harness names it in the system prompt's `# Memory` section (`~/.claude/projects/<encoded-cwd>/memory/`) and guarantees it exists: write there directly, no `mkdir`, no existence check. Derive it only when that section is missing (Claude Code encodes the project path by replacing `/` and `.` with `-`):
```bash
MEMORY_DIR="$HOME/.claude/projects/$(pwd | sed 's|[/.]|-|g')/memory"
```
Outside a project (e.g. running from `~`), fall back to `~/.claude/memory/`.

**File naming**: `[kebab-slug].md` — the filename matches the `name:` field exactly. Type lives in metadata, not the filename.

Required frontmatter:
```
---
name: [kebab-slug]
description: [one-line — specific enough to judge relevance without reading the file]
metadata:
  type: [user | feedback | project | reference]
---
```

**Body rules by type:**

`feedback` → Lead with the rule. Then:
- **Why:** [reason from context, or inferred]
- **How to apply:** [when this kicks in]

`user` → Facts about the user: role, expertise, preferences. Positive framing only.

`project` → Lead with the fact/decision. Convert relative dates to absolute ("next sprint" → "2026-07-13") so staleness can be judged later. Then:
- **Why:** [motivation]
- **How to apply:** [how this shapes future suggestions]

`reference` → What it is, where it is, when to use it.

Link related memories with `[[name]]`.

---

## Step 4 — Update MEMORY.md index

Update `MEMORY.md` in the memory directory. Create it if it doesn't exist.

For **each new file**: append one line:
```
- [Title](filename.md) — one-line hook
```
For each deleted file: remove its line.

Keep existing entries intact. Index stays under 200 lines — if it grows past that, run consolidation.

---

## Step 5 — Report

Report only what changed, one line per memory, then stop:
```
Learned:
✓ New: [slug].md — [one-line]
✓ Updated: user-profile.md — added [what]
✗ Deleted: [slug].md — [why it was wrong]
— Skipped: [reason]
```

**Card form.** When the user explicitly typed `/learn` and the `show_widget` tool (visualize MCP) is available, render those same lines as one card instead: call `read_me` once, silently (module `mockup`; skip if already called this session), then `show_widget` with the template below — one row per memory, drop the rows you don't need. The card is the whole report; at most one sentence of prose outside the tool call. Auto-invocations mid-task (after a correction, a "remember this") keep the text form: the reply has to continue, and `read_me` costs several thousand tokens.

```html
<h2 class="sr-only">Memory changes this session: [N] new, [N] updated, [N] deleted, [N] skipped.</h2>
<div style="background: var(--surface-2); border: 0.5px solid var(--border); border-radius: 12px; padding: 1rem 1.25rem;">
  <div style="display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 8px;">
    <span style="font-size: 15px; font-weight: 500;">[project]</span>
    <span style="font-size: 13px; color: var(--text-muted);">[today YYYY-MM-DD]</span>
  </div>
  <div style="display: flex; gap: 12px; align-items: baseline; padding: 8px 0; border-top: 0.5px solid var(--border);">
    <span style="font-size: 12px; padding: 2px 8px; border-radius: var(--radius); background: var(--bg-success); color: var(--text-success); white-space: nowrap;"><i class="ti ti-plus" aria-hidden="true"></i> New</span>
    <span style="font-family: var(--font-mono); font-size: 13px; white-space: nowrap;">[slug].md</span>
    <span style="font-size: 13px; color: var(--text-secondary);">[one-line]</span>
  </div>
  <div style="display: flex; gap: 12px; align-items: baseline; padding: 8px 0; border-top: 0.5px solid var(--border);">
    <span style="font-size: 12px; padding: 2px 8px; border-radius: var(--radius); background: var(--bg-accent); color: var(--text-accent); white-space: nowrap;"><i class="ti ti-edit" aria-hidden="true"></i> Updated</span>
    <span style="font-family: var(--font-mono); font-size: 13px; white-space: nowrap;">[slug].md</span>
    <span style="font-size: 13px; color: var(--text-secondary);">added [what]</span>
  </div>
  <div style="display: flex; gap: 12px; align-items: baseline; padding: 8px 0; border-top: 0.5px solid var(--border);">
    <span style="font-size: 12px; padding: 2px 8px; border-radius: var(--radius); background: var(--bg-danger); color: var(--text-danger); white-space: nowrap;"><i class="ti ti-trash" aria-hidden="true"></i> Deleted</span>
    <span style="font-family: var(--font-mono); font-size: 13px; white-space: nowrap;">[slug].md</span>
    <span style="font-size: 13px; color: var(--text-secondary);">[why it was wrong]</span>
  </div>
  <div style="display: flex; gap: 12px; align-items: baseline; padding: 8px 0; border-top: 0.5px solid var(--border);">
    <span style="font-size: 12px; padding: 2px 8px; border-radius: var(--radius); background: var(--surface-1); color: var(--text-secondary); white-space: nowrap;"><i class="ti ti-minus" aria-hidden="true"></i> Skipped</span>
    <span style="font-size: 13px; color: var(--text-secondary);">[reason]</span>
  </div>
</div>
```

Nothing else.

---

## Consolidation mode (`/learn consolidate`)

Memory hygiene is owned by the dedicated `anthropic-skills:consolidate-memory` skill — the SessionStart hook (`~/.claude/hooks/memory-consolidation-check.mjs`) nudges toward it and tracks a `.last-consolidated` marker. Don't reimplement it here.

When user types `/learn consolidate`:
1. Resolve the memory directory (Step 3)
2. Invoke the `anthropic-skills:consolidate-memory` skill for this project
3. After it completes, stamp the marker so the hook's nudge resets:
   ```bash
   node -e "require('fs').writeFileSync('<memory-dir>/.last-consolidated', new Date().toISOString()+'\n')"
   ```
