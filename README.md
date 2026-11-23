# ccline

![ccline status bar](screenshot.png)

A Powerline-themed status line renderer for [Claude Code](https://claude.ai/code). Reads session metadata from stdin as JSON and renders a styled status bar to stdout using ANSI true-color escape codes and Nerd Font glyphs.

The status bar displays three segments:
- **Model / context** — active model name, context window progress bar, and estimated token usage
- **Git diff** — lines added and removed in the current session
- **Token / cost summary** — total input/output tokens, API time, and estimated cost

## Requirements

Zig 0.17.1 or later.

**macOS (Homebrew):**
```sh
brew install zig
```

**Other systems:** download from [ziglang.org/download](https://ziglang.org/download/).

A terminal with [Nerd Font](https://www.nerdfonts.com/) support is required for the Powerline glyphs to render correctly. [Ghostty](https://ghostty.org/) is recommended — it ships with built-in Nerd Font glyph support and requires no additional font installation. Other terminals will need a [patched Nerd Font](https://www.nerdfonts.com/font-downloads) installed and configured.

## Build

```sh
zig build -Doptimize=ReleaseFast
```

The binary is written to `zig-out/bin/ccline`. Copy it somewhere on your `PATH`:

```sh
cp zig-out/bin/ccline ~/.local/bin/ccline
```

## Configure Claude Code

Add a `statusLine` entry to `~/.claude/settings.json` pointing to the installed binary:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/you/.local/bin/ccline"
  }
}
```

Replace the path with wherever you copied the binary.

### Light and dark terminals

The default palette is tuned for a dark terminal background. Pass `--theme` to change it:

- `--theme=dark` (default) — the dark-background palette.
- `--theme=light` — a palette tuned for a light background.
- `--theme=frappe` — the [Catppuccin Frappé](https://catppuccin.com/palette) palette, for terminals using that theme.
- `--theme=auto` — uses `COLORFGBG` if your terminal sets it, otherwise the macOS system appearance (macOS only), otherwise dark.

Claude Code tells a statusline command nothing about the terminal's colours, so `auto` relies on these hints. It is not the default because the OS appearance only reflects the terminal if the terminal follows it (as Ghostty does with `theme = light:…,dark:…`).

```json
"command": "/Users/you/.local/bin/ccline --theme=auto"
```
