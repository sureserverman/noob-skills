---
name: propagate-skill-across-ide-repos
description: >
  Use when the user asks to deploy or propagate a skill to Cursor, Codex, Gemini, OpenCode,
  noob-skills, or all IDE/tool skill directories at once. Trigger on "propagate this skill",
  "copy this skill everywhere", "deploy to all my tools", or after finalizing a new/updated
  skill in ~/.claude/skills/.
---

# Propagate Skill Across IDE Repos

After finalizing a skill in `~/.claude/skills/`, copy it to all target locations so it is available in every IDE and tool environment.

## Targets

| Target | Path |
|---|---|
| Claude Code (source) | `~/.claude/skills/{name}/SKILL.md` |
| Cursor | `~/.cursor/skills/{name}/SKILL.md` |
| Codex | `~/.codex/skills/{name}/SKILL.md` |
| Gemini | `~/.gemini/skills/{name}/SKILL.md` |
| OpenCode | `~/.config/opencode/skills/{name}/SKILL.md` |
| noob-skills | `~/dev/noob-skills/skills/{name}/SKILL.md` |

**OpenCode note:** OpenCode has first-class Anthropic-style SKILL.md support. It discovers skills from (in priority order): `.opencode/skills/` (project), `~/.config/opencode/skills/` (global — our target), `.claude/skills/`, `.agents/skills/`. The global XDG path above is the one to mirror to.

## Workflow

1. Confirm the skill is finalized and tested (all baseline/GREEN checks pass)
2. Copy to each target, creating the directory if needed:

```bash
SKILL_NAME="the-skill-name"
SRC="$HOME/.claude/skills/$SKILL_NAME/SKILL.md"

for TARGET in \
  "$HOME/.cursor/skills/$SKILL_NAME" \
  "$HOME/.codex/skills/$SKILL_NAME" \
  "$HOME/.gemini/skills/$SKILL_NAME" \
  "$HOME/.config/opencode/skills/$SKILL_NAME" \
  "$HOME/dev/noob-skills/skills/$SKILL_NAME"; do
  mkdir -p "$TARGET"
  cp "$SRC" "$TARGET/SKILL.md"
done
```

3. Verify all copies are identical:

```bash
md5sum "$HOME/.claude/skills/$SKILL_NAME/SKILL.md" \
       "$HOME/.cursor/skills/$SKILL_NAME/SKILL.md" \
       "$HOME/.codex/skills/$SKILL_NAME/SKILL.md" \
       "$HOME/.gemini/skills/$SKILL_NAME/SKILL.md" \
       "$HOME/.config/opencode/skills/$SKILL_NAME/SKILL.md" \
       "$HOME/dev/noob-skills/skills/$SKILL_NAME/SKILL.md"
```

All hashes must match.

## Propagating multiple skills at once

Wrap the loop:

```bash
for SKILL_NAME in brainstorming executing-plans dispatching-parallel-agents; do
  SRC="$HOME/.claude/skills/$SKILL_NAME/SKILL.md"
  for TARGET in \
    "$HOME/.cursor/skills/$SKILL_NAME" \
    "$HOME/.codex/skills/$SKILL_NAME" \
    "$HOME/.gemini/skills/$SKILL_NAME" \
    "$HOME/.config/opencode/skills/$SKILL_NAME" \
    "$HOME/dev/noob-skills/skills/$SKILL_NAME"; do
    mkdir -p "$TARGET"
    cp "$SRC" "$TARGET/SKILL.md"
  done
done
```

## When to propagate

- After creating a new skill
- After updating an existing skill (re-propagate to keep all copies in sync)
- Do NOT propagate work-in-progress skills
