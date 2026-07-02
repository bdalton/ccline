---
name: install
description: Build ccline from source with ReleaseSmall optimization and install it as the Claude Code statusline. Detects the active Claude config dir (CLAUDE_CONFIG_DIR, else ~/.claude) and the current install path from its settings.json; overwrites the existing binary if ccline is already configured, or installs fresh to ~/.local/bin/ccline and updates settings.json. Same command handles first-time install and upgrade.
---

# /install — build ccline and install as statusline

Build ccline with smallest-size optimization and install it as the user's
Claude Code statusline. Idempotent: the same command does a first-time install
or an in-place upgrade.

## Preconditions

- `zig` and `jq` must be on `PATH`. If either is missing, stop and tell the
  user which one — do not try to work around it.
- The current working directory must contain `build.zig` (the ccline repo
  root). If not, stop and ask the user to `cd` into the repo.

## Step 0 — Resolve the active config directory

Claude Code stores per-user config under `~/.claude` by default, but a session
run against a non-default account (e.g. work vs. personal) points
`CLAUDE_CONFIG_DIR` at a different directory (such as `~/.claude-work`). Resolve
it once and use `$CFG` everywhere below — never hardcode `~/.claude`:

```bash
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

Targeting the wrong settings file is silent: the install "succeeds" but the
running session never reads that file, so the statusline never appears.

## Step 1 — Detect the current install

Read the statusline command from the active settings file:

```bash
CMD=$(jq -r '.statusLine.command // empty' "$CFG/settings.json" 2>/dev/null)
```

Classify the result:

- **Empty** (file missing, key absent, or value null) → **fresh install**.
- **Contains `ccline`** → **upgrade**. The install path is the first
  whitespace-separated token of `$CMD` with `~` expanded to `$HOME`. If the
  token is a bare name (e.g. just `ccline`), resolve it with
  `command -v ccline`.
- **Non-ccline command present** (e.g. an existing `jq`-based inline
  statusline or a different script) → stop and ask the user whether to
  replace it before touching settings. If they decline, exit cleanly.

## Step 2 — Build

```bash
zig build -Doptimize=ReleaseSmall
```

The binary is produced at `zig-out/bin/ccline`. If the build fails, surface
the error and stop — do not copy a stale binary from a prior build.

## Step 3 — Install

### Upgrade path (ccline already configured)

```bash
cp zig-out/bin/ccline "$INSTALL_PATH"
```

Report the path and the new binary size (`ls -lh "$INSTALL_PATH"`) in one
short line.

### Fresh install path (no ccline configured)

Before writing anything, tell the user in plain language:

- The binary will be installed to `~/.local/bin/ccline`.
- The active settings file (`$CFG/settings.json`, where `$CFG` is
  `$CLAUDE_CONFIG_DIR` or `~/.claude`) will be updated to set
  `statusLine.command` to the **absolute** path of that binary (with
  `type: "command"`).
- To uninstall later: delete `~/.local/bin/ccline` and remove the
  `statusLine` key from `$CFG/settings.json`.

Then perform the install:

```bash
mkdir -p ~/.local/bin
cp zig-out/bin/ccline ~/.local/bin/ccline

# Ensure the config dir and settings.json exist (create with empty object if not).
mkdir -p "$CFG"
[ -f "$CFG/settings.json" ] || printf '{}\n' > "$CFG/settings.json"

# Atomic update: write to a temp file, then rename. Preserves other keys.
# Write an ABSOLUTE path — Claude Code exec's the command without shell
# tilde-expansion, so a literal "~/..." path fails with "No such file".
tmp=$(mktemp)
jq --arg p "$HOME/.local/bin/ccline" \
  '.statusLine = {"type":"command","command":$p}' \
  "$CFG/settings.json" > "$tmp" && mv "$tmp" "$CFG/settings.json"
```

Never edit `$CFG/settings.json` with `sed` or inline string munging —
it contains unrelated user config that must be preserved exactly.

## Step 4 — Verify

Smoke-test the installed binary against the repo's sample payload:

```bash
"$INSTALL_PATH" < testdata/sample.json
```

It should print a single non-empty line of ANSI output. Report that line
to the user so they can confirm it looks right. If the binary errors or
produces nothing, surface the error — do not claim success.

## Notes

- Only the active user-global settings file (`$CFG/settings.json`) is touched.
  `$CFG` follows `CLAUDE_CONFIG_DIR` when set (so a work vs. personal account
  each get their own statusline) and falls back to `~/.claude` otherwise.
  Project-level `.claude/settings.json` is left alone; a statusline is
  typically a per-user preference.
- `ReleaseSmall` trades runtime speed for binary size. For a statusline that
  runs on every assistant message and does very little work, startup cost
  dominates, so the smaller binary is the right tradeoff.
- On the **upgrade** path (binary swapped in place at the same configured
  path), Claude Code picks up the new binary on the next statusline
  invocation — no restart required.
- On the **fresh install** path (the `statusLine` key was just added to
  settings.json), the running session won't show the statusline: Claude Code
  reads `statusLine` config at session startup, not per-render. Tell the user
  to relaunch Claude Code for it to appear.
- The `statusLine.command` must be an **absolute path**. Claude Code exec's
  the command directly rather than through a shell, so a literal `~` is not
  expanded and a `~/.local/bin/ccline` value silently fails (the statusline
  just never appears). The fresh-install `jq` step above writes
  `$HOME/.local/bin/ccline` for this reason.
