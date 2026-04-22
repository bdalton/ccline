# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

- `zig build` — compile executable to `zig-out/bin/ccline`
- `zig build run` — build and run (pass args after `--`)
- `zig build test` — run all tests (library + executable module tests in parallel)
- `zig build -Doptimize=ReleaseSmall` — optimized release build (smallest binary; preferred for install)
- `zig fmt src/` — format all source files

Requires Zig >= 0.15.2. No external dependencies.

## Architecture

ccline is a status line renderer for Claude Code CLI. It reads a JSON message from stdin containing session metadata and renders a Powerline-themed status bar to stdout using ANSI true-color escape codes and Nerd Font glyphs.

Pipeline: `stdin (JSON) → message.zig (parse) → main.zig (orchestrate) → renderer.zig (format) → stdout (ANSI)`

- **src/main.zig** — Entry point. Parses stdin via message module and emits one or two Powerline rows:
  - **Line 1** (always): bone-colored pill with `✲` sparkle, model name, terracotta context progress bar, and estimated tokens; then a beige pill with git branch, diff counts, and token I/O. Thinking time is appended to line 1 *only* when `rate_limits` is absent.
  - **Line 2** (only when `msg.rate_limits` is present): inverted (concave) bone pill with stopwatch, thinking time, and terracotta 5h progress bar; beige pill with 7d/weekly bar. The 5h bar's start column is padded dynamically so it sits directly beneath line 1's context bar.
- **src/message.zig** — JSON deserialization into nested Zig structs (`Message`, `Model`, `Cost`, `ContextWindow`, `RateLimits`, etc.) using `std.json.parseFromSlice`. Reads up to 32KB from stdin.
- **src/renderer.zig** — Zero-allocation rendering engine. Static 1024-byte buffer with overflow protection. Provides ANSI color primitives (`style`, `style_fg`, `style_bg` with compile-time hex color parsing) and formatters for tokens, time (with companion `time_len` for pre-computing width without emitting), cost, and progress bars.
- **src/root.zig** — Library module root (placeholder, not meaningfully used yet).

### Color palette

Claude-brand adjacent:

- `pill0 = #e8e3d6` (bone) — line 1 left pill, line 2 left pill
- `pill1 = #b1ada1` (warm beige) — line 1 right pill, line 2 right pill
- `#3a2e1f` (dark bark) — body text on bone
- `#c15f3c` (terracotta) — `✲` sparkle accent and both progress-bar fills
- `#000000` (black) — body text on beige

### Key design constraints

- **No heap allocation in renderer** — all output built in a fixed stack buffer.
- **Compile-time color parsing** — hex color codes (e.g., `"#c15f3c"`) validated and converted to ANSI sequences via `comptime`.
- **Overflow-safe** — buffer writes silently drop when full (no crashes or truncation mid-character).
- **Cross-line alignment is runtime-computed.** When line 2 is active, the padding between the thinking time and the `5h` label is `display_name.len - time_len - 4`, clamped to ≥ 1. This puts the 5h bar start at the same column as the context bar above.

### Gotchas (undocumented behavior discovered empirically)

- **Claude Code strips leading ASCII 0x20 spaces on lines 2+** of multi-line statuslines. Line 1 leading spaces are honored; later rows lose them silently. Workarounds: `U+00A0` NBSP (whitespace-category but not `0x20`) or ANSI `ESC[NC` cursor-forward escape. Line 2 currently uses two NBSPs for its leading indent.
- **Powerline/box-drawing glyphs (U+E0A0–U+E0BF) bypass Ghostty's `minimum-contrast` remap** — they're rendered via Ghostty's own shape pipeline, not the font. The chevron between pills can have intrinsically low fg/bg contrast without being force-adjusted. All other glyphs (text, Nerd Font progress cells `U+EE00`–`U+EE05`, Codicon diff icons, etc.) *are* subject to the remap — keep any fg/bg pair above 3:1 to prevent surprise recoloring.
- **Concave pill shape trick.** Line 2's inverted flourishes are drawn with `ESC[7m` / `ESC[27m` (ANSI reverse-video) bracketing the Powerline half-circle glyphs. Inverse swaps the intended fg/bg at render time, letting the terminal's default background paint the "scoop" without hardcoding a dark color — the scoop auto-matches any Ghostty theme.
