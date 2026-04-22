---
name: install
description: Build ccline from source with ReleaseSmall optimization and install it as the Claude Code statusline. Detects the current install path from ~/.claude/settings.json; overwrites the existing binary if ccline is already configured, or installs fresh to ~/.local/bin/ccline and updates settings.json. Same command handles first-time install and upgrade.
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

## Step 1 — Detect the current install

Read the statusline command from the user-global settings file:

```bash
CMD=$(jq -r '.statusLine.command // empty' ~/.claude/settings.json 2>/dev/null)
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
- `~/.claude/settings.json` will be updated to set
  `statusLine.command` to `~/.local/bin/ccline` (with `type: "command"`).
- To uninstall later: delete `~/.local/bin/ccline` and remove the
  `statusLine` key from `~/.claude/settings.json`.

Then perform the install:

```bash
mkdir -p ~/.local/bin
cp zig-out/bin/ccline ~/.local/bin/ccline

# Ensure settings.json exists (create with empty object if not).
[ -f ~/.claude/settings.json ] || printf '{}\n' > ~/.claude/settings.json

# Atomic update: write to a temp file, then rename. Preserves other keys.
tmp=$(mktemp)
jq '.statusLine = {"type":"command","command":"~/.local/bin/ccline"}' \
  ~/.claude/settings.json > "$tmp" && mv "$tmp" ~/.claude/settings.json
```

Never edit `~/.claude/settings.json` with `sed` or inline string munging —
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

- Only the user-global settings file (`~/.claude/settings.json`) is touched.
  Project-level `.claude/settings.json` is left alone; a statusline is
  typically a per-user preference.
- `ReleaseSmall` trades runtime speed for binary size. For a statusline that
  runs on every assistant message and does very little work, startup cost
  dominates, so the smaller binary is the right tradeoff.
- Claude Code picks up the new binary on the next statusline invocation;
  no restart is required.
