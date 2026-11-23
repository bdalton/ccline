//! Colour palettes and light/dark detection.
//!
//! Claude Code gives a statusline command no information about the terminal
//! background, and the command's stdout is a pipe, so ccline cannot query the
//! terminal (OSC 11) either. Detection is therefore opt-in and degrades
//! gracefully:
//!
//!   --theme=dark   (default) the original palette, on every platform
//!   --theme=light  the light palette, on every platform
//!   --theme=frappe the Catppuccin Frappé palette, on every platform
//!   --theme=auto   COLORFGBG if the terminal sets it, else the macOS system
//!                  appearance (macOS only), else dark
//!
//! `auto` is opt-in because the OS appearance is only a proxy for the
//! terminal's background: a terminal with a fixed dark theme on a Mac in
//! light mode would otherwise get the wrong palette.

const std = @import("std");
const builtin = @import("builtin");

pub const Palette = struct {
    /// Left pill background (primary).
    pill0: []const u8,
    /// Right pill background (secondary).
    pill1: []const u8,
    /// Sparkle and the context / 5h progress bars.
    accent: []const u8,
    /// Text on the left pill.
    text0: []const u8,
    /// Text (and the weekly bar) on the right pill.
    text1: []const u8,
};

/// Tuned for a dark terminal background: the bone left pill is the brightest
/// thing on the line, and the beige right pill recedes.
pub const dark: Palette = .{
    .pill0 = "#e8e3d6",
    .pill1 = "#b1ada1",
    .accent = "#c15f3c",
    .text0 = "#3a2e1f",
    .text1 = "#000000",
};

/// Tuned for a light (ivory, #faf9f5) terminal background. The left pill keeps
/// its bone colour, which is a gentle step darker than the background; the
/// right pill sits between the two so it recedes instead of standing out.
/// Left text is near-black for emphasis and right text is a mid grey.
pub const light: Palette = .{
    .pill0 = "#e8e3d6",
    .pill1 = "#f0eee6",
    .accent = "#c15f3c",
    .text0 = "#141413",
    .text1 = "#73726c",
};

/// Catppuccin Frappé (https://catppuccin.com/palette), tuned for a terminal
/// whose background is Frappé mantle (#292c3c). The left pill is surface0, one
/// step up from mantle, and carries the mauve accent; the right pill is base,
/// half a step up, so it recedes like the other palettes' right pill does.
pub const frappe: Palette = .{
    .pill0 = "#414559", // surface0
    .pill1 = "#303446", // base
    .accent = "#ca9ee6", // mauve
    .text0 = "#c6d0f5", // text
    .text1 = "#a5adce", // subtext0
};

pub const Mode = enum { dark, light, frappe, auto };
pub const Variant = enum { dark, light, frappe };

/// Parses one command-line argument. Returns null for anything that is not a
/// recognised `--theme=` value, so unknown input falls back to the default
/// rather than breaking the statusline.
pub fn parse_arg(arg: []const u8) ?Mode {
    const prefix = "--theme=";
    if (!std.mem.startsWith(u8, arg, prefix)) return null;
    return std.meta.stringToEnum(Mode, arg[prefix.len..]);
}

/// Interprets a COLORFGBG value ("fg;bg" or "fg;default;bg"), using the same
/// convention as Vim: background colours 0-6 and 8 are dark, 7 and 9-15 light.
pub fn colorfgbg_variant(value: []const u8) ?Variant {
    const sep = std.mem.lastIndexOfScalar(u8, value, ';') orelse return null;
    const bg = std.fmt.parseInt(u8, value[sep + 1 ..], 10) catch return null;
    return switch (bg) {
        0...6, 8 => .dark,
        7, 9...15 => .light,
        else => null,
    };
}

/// Asks macOS for the system appearance. `defaults` prints "Dark" in dark
/// mode and fails (the key is absent) in light mode. Returns null on other
/// platforms or if `defaults` cannot be run.
fn macos_variant(gpa: std.mem.Allocator, io: std.Io) ?Variant {
    if (builtin.os.tag != .macos) return null;
    const result = std.process.run(gpa, io, .{
        .argv = &.{ "/usr/bin/defaults", "read", "-g", "AppleInterfaceStyle" },
        .stdout_limit = .limited(64),
        .stderr_limit = .limited(1024),
        // Normally ~15ms, but the first call after the preferences daemon
        // has gone idle can be much slower; 250ms was observed to time out.
        .timeout = .{ .duration = .{
            .raw = .fromMilliseconds(1000),
            .clock = .awake,
        } },
    }) catch return null;
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    return switch (result.term) {
        .exited => |code| if (code != 0)
            .light
        else if (std.mem.eql(u8, std.mem.trim(u8, result.stdout, " \t\r\n"), "Dark"))
            .dark
        else
            .light,
        else => null,
    };
}

pub fn resolve(mode: Mode, gpa: std.mem.Allocator, io: std.Io, environ: std.process.Environ) Variant {
    return switch (mode) {
        .dark => .dark,
        .light => .light,
        .frappe => .frappe,
        .auto => blk: {
            if (environ.getAlloc(gpa, "COLORFGBG")) |value| {
                defer gpa.free(value);
                if (colorfgbg_variant(value)) |v| break :blk v;
            } else |_| {}
            break :blk macos_variant(gpa, io) orelse .dark;
        },
    };
}

test "parse_arg" {
    try std.testing.expectEqual(Mode.dark, parse_arg("--theme=dark").?);
    try std.testing.expectEqual(Mode.light, parse_arg("--theme=light").?);
    try std.testing.expectEqual(Mode.frappe, parse_arg("--theme=frappe").?);
    try std.testing.expectEqual(Mode.auto, parse_arg("--theme=auto").?);
    try std.testing.expectEqual(@as(?Mode, null), parse_arg("--theme=sepia"));
    try std.testing.expectEqual(@as(?Mode, null), parse_arg("--theme"));
    try std.testing.expectEqual(@as(?Mode, null), parse_arg("auto"));
}

test "colorfgbg_variant" {
    try std.testing.expectEqual(Variant.dark, colorfgbg_variant("15;0").?);
    try std.testing.expectEqual(Variant.dark, colorfgbg_variant("7;8").?);
    try std.testing.expectEqual(Variant.light, colorfgbg_variant("0;15").?);
    try std.testing.expectEqual(Variant.light, colorfgbg_variant("0;7").?);
    try std.testing.expectEqual(Variant.light, colorfgbg_variant("0;default;15").?);
    try std.testing.expectEqual(@as(?Variant, null), colorfgbg_variant("0;default"));
    try std.testing.expectEqual(@as(?Variant, null), colorfgbg_variant("0;200"));
    try std.testing.expectEqual(@as(?Variant, null), colorfgbg_variant(""));
}
