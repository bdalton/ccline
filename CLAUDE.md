# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

- `zig build` — compile executable to `zig-out/bin/ccline`
- `zig build run` — build and run (pass args after `--`)
- `zig build test` — run all tests (library + executable module tests in parallel)
- `zig build -Doptimize=ReleaseFast` — optimized release build
- `zig fmt src/` — format all source files

Requires Zig >= 0.15.2. No external dependencies.

## Architecture

ccline is a status line renderer for Claude Code CLI. It reads a JSON message from stdin containing session metadata and renders a Powerline-themed status bar to stdout using ANSI true-color escape codes and Nerd Font glyphs.

Pipeline: `stdin (JSON) → message.zig (parse) → main.zig (orchestrate) → renderer.zig (format) → stdout (ANSI)`

- **src/main.zig** — Entry point. Parses stdin via message module, composes a three-segment Powerline status bar (model/context, git diff stats, token/cost summary) using the renderer.
- **src/message.zig** — JSON deserialization into nested Zig structs (`Message`, `Model`, `Cost`, `ContextWindow`, etc.) using `std.json.parseFromSlice`. Reads up to 32KB from stdin.
- **src/renderer.zig** — Zero-allocation rendering engine. Uses a static 1024-byte buffer with overflow protection. Provides ANSI color primitives (`style`, `style_fg`, `style_bg` with compile-time hex color parsing), and formatters for tokens, time, cost, and progress bars.
- **src/root.zig** — Library module root (placeholder, not meaningfully used yet).

### Key Design Constraints

- **No heap allocation in renderer** — all output built in a fixed stack buffer
- **Compile-time color parsing** — hex color codes (e.g., `"#777755"`) validated and converted to ANSI sequences via `comptime`
- **Overflow-safe** — buffer writes silently drop when full (no crashes or truncation mid-character)
