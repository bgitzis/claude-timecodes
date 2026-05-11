# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`claude-timecodes` adds timestamps and speaker labels to Claude Code conversations. It's a Node.js CLI + bash hook script + local web viewer, distributed via `npx github:ProducerGuy/claude-timecodes` (not published to npm — see commit `9af0615`).

**Zero runtime dependencies** — pure Node.js stdlib only. `package.json` has no `dependencies` field, and that constraint is intentional. Don't add deps without strong justification.

ESM (`"type": "module"`), Node 18+. No build step, no transpilation, no tests, no lint config. `node bin/cli.js <command>` runs directly.

## Common commands

```bash
# Run the CLI locally without installing
node bin/cli.js sessions
node bin/cli.js view <session-id>
node bin/cli.js web              # launches viewer on :8420

# Install the hooks into the user's ~/.claude (writes to ~/.claude/settings.json)
node bin/cli.js install
node bin/cli.js uninstall

# Test the hook script directly — it reads JSON on stdin
echo '{"hook_event_name":"UserPromptSubmit"}' | hooks/timecode.sh
echo '{"hook_event_name":"SessionStart","model":"claude-opus-4-6"}' | hooks/timecode.sh
```

When testing `install`, be aware it mutates `~/.claude/settings.json` and copies `hooks/timecode.sh` to `~/.claude/timecode.sh`. The install is idempotent (checks for `timecode.sh` in existing hook entries before adding).

## Architecture

Three pieces that all read the same data — Claude Code's per-session JSONL files at `~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl`:

**1. Hook script (`hooks/timecode.sh`)** — bash, requires `jq`. Fires on four events configured in `lib/install.js`:
- `SessionStart` — extracts the model ID from the hook input and persists a formatted name (e.g. `Claude Opus 4.6`) to `~/.claude/timecodes.json` as `currentModel`. This is the only writer of that field; the other events read it back.
- `UserPromptSubmit` — emits `systemMessage` (visible to user) AND `additionalContext` (injected into Claude's context so the model can reason about time).
- `Stop` — `systemMessage` only.
- `PostToolUse` — both, with the tool name appended.

The hook is the only component that talks to the running Claude Code session. The CLI and web viewer are read-only over the JSONL files after the fact.

**2. CLI (`bin/cli.js`)** — single file, switch on `argv[0]`. Subcommands: `sessions`, `view`, `search`, `at`, `export`, `web`, `install`, `uninstall`, `config`. Heavy lifting lives in `lib/`; the CLI is mostly arg parsing + formatting.

**3. Web viewer (`lib/server.js` + `viewer.html`)** — Node `http` server on 127.0.0.1, serves `viewer.html` at `/` and JSON at `/api/sessions`, `/api/session/:id`, `/api/search`, `/api/config`. Uses the same `lib/sessions.js` parser as the CLI.

### Data flow & key files

```
~/.claude.json              ← user's Anthropic OAuth display name (read-only, for auto-detect)
~/.claude/settings.json     ← Claude Code config; install.js adds/removes hook entries here
~/.claude/timecodes.json    ← this tool's config: displayName, homeTimezone, currentModel
~/.claude/timecode.sh       ← copy of hooks/timecode.sh, installed by install.js
~/.claude/projects/*/*.jsonl ← Claude Code's session transcripts (the source of truth)
```

`lib/paths.js` is the single source for those locations — import from there, don't recompute.

### Conventions worth knowing

- **Two model-name formatters exist and must stay in sync:** `formatModelName` in `lib/sessions.js:8` (JS, for CLI/web) and the inline `sed`/`awk` pipeline in `hooks/timecode.sh:41` (bash, for hook output). Both turn `claude-opus-4-6` into `Claude Opus 4.6` and strip a trailing `-YYYYMMDD` date suffix. If you change one, change both.
- **Speaker labels:** user messages render as the configured `displayName` (auto-detected from `~/.claude.json`'s `oauthAccount.display_name`, falls back to `"You"`). Assistant messages render as the formatted model name from the message itself, not the global `currentModel` — the per-message `msg.message?.model` is authoritative.
- **Travel awareness:** `formatTimecode` in `lib/sessions.js` compares system tz vs `homeTimezone` from config. When they differ, output is `"local time (home time)"`. The bash hook reproduces this with `TZ=...date` and a `$Z` abbreviation comparison.
- **Session lookup:** `findSessionFile` in `lib/sessions.js` accepts a full UUID or any prefix/substring — partial matches scan filenames.
- **Hook idempotency:** `installHooks` checks each `HOOK_EVENTS` entry for an existing command containing `"timecode.sh"` before appending. `uninstallHooks` filters by the same substring. If you rename the hook file, the uninstaller will silently leave old entries behind.

## Things to be careful about

- `lib/install.js` writes to `~/.claude/settings.json`, which is shared with every other Claude Code hook the user has installed. Always preserve existing keys; never replace the file wholesale.
- The hook runs on every user prompt, every Stop, every tool call. Keep it fast and avoid forking heavy processes — `jq` and `date` are the budget.
- `~/.claude.json` may not exist or may not contain `oauthAccount` — `detectDisplayName` swallows errors and returns `null`. Don't assume it's available.
- JSONL files contain entries other than `user`/`assistant` (system, summary, etc.). `loadSession` filters to those two types; if you need others, add them explicitly rather than removing the filter.
