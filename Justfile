# Build the release binary
build:
    zig build -Doptimize=ReleaseFast

# Run all tests
test:
    zig build test

# Regenerate the README screenshot (requires freeze and a Nerd Font)
#
# ccline pads the start of line 2 with U+00A0 NBSPs so Claude Code's own
# line-2 handler doesn't strip the row (see CLAUDE.md); inside Claude Code
# they render as zero-width, but freeze is a plain terminal renderer and
# would draw them as two real blank columns, throwing off line 2's
# alignment. Strip them here so the screenshot matches what Claude Code
# actually shows.
screenshot: build
    cat testdata/sample.json \
        | ./zig-out/bin/ccline \
        | perl -CSD -pe 's/\x{00a0}//g if $. == 2' \
        | freeze \
            --font.family "SauceCodePro Nerd Font Mono" \
            --font.size 16 \
            --background "#1e1e1e" \
            --padding 20 \
            --margin 0 \
            --window=false \
            -o screenshot.png
