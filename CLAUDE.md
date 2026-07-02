# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

- `zig build` — compile executable to `zig-out/bin/ccline`
- `zig build run` — build and run (pass args after `--`)
- `zig build test` — run all tests (library + executable module tests in parallel)
- `zig build -Doptimize=ReleaseSmall` — optimized release build (smallest binary; preferred for install)
- `zig fmt src/` — format all source files

Requires Zig >= 0.16.0. No external dependencies.

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
- **Cross-line alignment is runtime-computed, and symmetric.** When line 2 is active, line 1's context bar starts at column `5 + model_len` and line 2's 5h bar starts at `9 + time_len + time_pad`. We align them by targeting a common `bar_col = max(5 + model_len, 10 + time_len)` and padding *whichever side is short*: `line1_left_pad = bar_col − (5 + model_len)` (extra spaces emitted after the model name) and `time_pad = bar_col − 9 − time_len` (spaces between the thinking time and the `5h` label). The `10 + time_len` term encodes a **floor of 1** on `time_pad` — a legible gap between the thinking time and `5h`. This floor is why the padding must be two-sided: when the model name is **long**, `line1_left_pad` is 0 and `time_pad` absorbs the difference (this reduces to the historical `time_pad = model_len − time_len − 4`); when the model name is **short**, line 2's prefix is intrinsically wider than line 1's and `time_pad` can't go below 1, so line 1 is padded rightward instead. A one-sided formula (`time_pad = model_len − time_len − 4` clamped to ≥ 1) silently mis-aligns for short model names — that was the bug. The `5 + model_len` / `9 + time_len` column math assumes the 2 leading NBSPs on line 2 contribute 0 visible columns in Claude Code's rendered statusline (see NBSP gotcha below — they're structural, not indent). **Do not "fix" the NBSP term by codepoint-counting** — a Python-side ANSI stripper that tallies codepoints will reliably mislead you into treating the NBSPs as 2 cols and leave the real terminal 2 cols off. Aligning the bars this way is equivalent to satisfying the middle-chevron diagonal invariant below: both reduce to the same padding equation, so bar alignment and chevron chaining hold together automatically.
- **Right-pill caps are dynamically aligned.** When both rows render (`rate_limits` present), `status_line` pre-computes each row's post-middle-chevron visible width from the `Message` — line 1 = `14 + L_added + L_removed + L_input + L_output` (each `L_x` = `tokens_len(x)`); line 2 = `27 + L_sd_pct` — and pads both rows up to a common target so the right pill caps line up. **The target accounts for the 1-col leftward offset of line 2's middle chevron** (see the diagonal invariant below): with `T = max(line1_w + 1, line2_w)`, we emit `T − line1_w − 1` trailing spaces before line 1's `\u{e0b4}` and `T − line2_w` before line 2's inverted `\u{e0b6}`. The `+1` term reflects that line 2's content needs to span one extra column past the chevron to finish at the same terminal column as line 1. Line 2's baseline emits `"% "` (not `"%"`) to guarantee ≥1 col between the rate percent and the pill; dynamic padding is additional on top.
- **Fixed-width post-bar fields chain the two middle chevrons into one continuous diagonal.** The middle separator `\u{e0bc}` is an *upper-left triangle* — its diagonal edge runs from the top-right corner of its cell to the bottom-left. For the diagonal on line 1 to continue seamlessly into the diagonal on line 2, line 2's chevron must sit exactly **one column to the left** of line 1's chevron (so line 1's bottom-of-diagonal and line 2's top-of-diagonal share a column). Post-bar widths therefore must satisfy `line1 = line2 + 1`. Both rows emit `" "` leading + trailing space around the numeric block, so with the `%` glyph only on line 2 we get `1 + N + 1 = 1 + M + 1 + 1 + 1` → `N = M + 2`. We use `N = 7` (token value via `buf.tokens_padded(_, 7)`) and `M = 5` (percent value via `buf.tokens_padded(_, 5)` followed by `"% "`). The `N = 7` is sized to the widest output of `format_tokens_into` for realistic values: `{d:.1}K` produces up to `1000.0K` / `1200.0K` (7 chars) near the upper end of a 1M-token context window; every other branch produces ≤ 5 chars. If the context window ever exceeds ~1.2M tokens, recheck the worst-case token-string width and bump both `N` and `M` in lockstep (`M = N − 2`). Do not "fix" the apparent off-by-one between `N` and `M`; the offset is load-bearing.

### Gotchas (undocumented behavior discovered empirically)

- **Claude Code strips leading `0x20` ASCII spaces on lines 2+** of multi-line statuslines, but `U+00A0` NBSPs survive the stripper and keep the line from being swallowed. Counter-intuitively the NBSPs are **required but produce zero visible columns** in the rendered statusline: drop them and Claude Code eats the entire line-2 prefix; keep them and line 2 renders — but the visible column count is as if they weren't there. You can verify this by noting that the line-2 bar-start column (`9 + time_len + time_pad`, see the alignment constraint above) balances against line 1's `5 + model_len` only when the 2 NBSPs contribute 0 cols, not 2. Treat them as a structural marker for Claude Code's line handler, not as indent. If you want real leading indent, use an `ESC[NC` cursor-forward escape.
- **Powerline/box-drawing glyphs (U+E0A0–U+E0BF) bypass Ghostty's `minimum-contrast` remap** — they're rendered via Ghostty's own shape pipeline, not the font. The chevron between pills can have intrinsically low fg/bg contrast without being force-adjusted. All other glyphs (text, Nerd Font progress cells `U+EE00`–`U+EE05`, Codicon diff icons, etc.) *are* subject to the remap — keep any fg/bg pair above 3:1 to prevent surprise recoloring.
- **Concave pill shape trick.** Line 2's inverted flourishes are drawn with `ESC[7m` / `ESC[27m` (ANSI reverse-video) bracketing the Powerline half-circle glyphs. Inverse swaps the intended fg/bg at render time, letting the terminal's default background paint the "scoop" without hardcoding a dark color — the scoop auto-matches any Ghostty theme.
