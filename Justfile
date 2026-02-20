# Build the release binary
build:
    zig build -Doptimize=ReleaseFast

# Run all tests
test:
    zig build test

# Regenerate the README screenshot (requires freeze and a Nerd Font)
screenshot: build
    cat testdata/sample.json \
        | ./zig-out/bin/ccline \
        | freeze \
            --font.family "SauceCodePro Nerd Font Mono" \
            --font.size 16 \
            --background "#1e1e1e" \
            --padding 20 \
            --margin 0 \
            --window=false \
            -o screenshot.png
