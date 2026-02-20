const std = @import("std");
const math = std.math;

const POWERLINE_PILL_LEFT = "\u{e0b6}";
const BRAIN_EMOJI = "🧠";
const MONEY_EMOJI = "💰";
const STOPWATCH_EMOJI = "⏱️";
const PARTIAL_PROGRESS_EMOJI = "⠁⠅⠇⠧⠯⠿";

const PROGRESS_LEFT_EMPTY = '\u{ee00}';
const PROGRESS_LEFT_FULL = '\u{ee03}';
const PROGRESS_INNER_EMPTY = '\u{ee01}';
const PROGRESS_INNER_FULL = '\u{ee04}';
const PROGRESS_RIGHT_EMPTY = '\u{ee02}';
const PROGRESS_RIGHT_FULL = '\u{ee05}';

// Static buffer for accumulating output
var buf: [1024]u8 = undefined;
var len: usize = 0;
var overflow: bool = false;

/// Flushes the buffer to stdout and resets state
pub fn present() void {
    string("\u{001b}[49m\u{001b}[39m\n");
    _ = std.posix.write(std.posix.STDOUT_FILENO, buf[0..len]) catch {};
    len = 0;
    overflow = false;
}

/// Appends a single Unicode codepoint (UTF-8 encoded) to the buffer
pub fn char(c: u21) void {
    if (overflow) return;

    var temp: [4]u8 = undefined;
    const encoded_len = std.unicode.utf8Encode(c, &temp) catch {
        overflow = true;
        return;
    };

    if (len + encoded_len > buf.len) {
        overflow = true;
        return;
    }

    @memcpy(buf[len..][0..encoded_len], temp[0..encoded_len]);
    len += encoded_len;
}

/// Appends a byte slice to the buffer
pub fn string(s: []const u8) void {
    if (overflow) return;

    if (len + s.len > buf.len) {
        overflow = true;
        return;
    }

    @memcpy(buf[len..][0..s.len], s);
    len += s.len;
}

/// Appends a character n times to the buffer
pub fn repeat(c: u21, n: usize) void {
    if (overflow) return;

    var temp: [4]u8 = undefined;
    const encoded_len = std.unicode.utf8Encode(c, &temp) catch {
        overflow = true;
        return;
    };

    const total_len = encoded_len * n;
    if (len + total_len > buf.len) {
        overflow = true;
        return;
    }

    for (0..n) |_| {
        @memcpy(buf[len..][0..encoded_len], temp[0..encoded_len]);
        len += encoded_len;
    }
}

/// Formats and appends a token count to the buffer
/// < 2000: prints as-is (e.g., "1234")
/// 2000-1.2M: prints in thousands with 1 decimal (e.g., "12.5K")
/// 1.2M-10M: prints in millions with 2 decimals (e.g., "1.23M")
/// 10M-100M: prints in millions with 1 decimal (e.g., "12.3M")
/// >= 100M: prints in millions with 0 decimals (e.g., "123M")
pub fn tokens(count: u64) void {
    if (overflow) return;

    var temp_buf: [32]u8 = undefined;

    if (count < 2000) {
        const formatted = std.fmt.bufPrint(&temp_buf, "{d}", .{count}) catch {
            overflow = true;
            return;
        };
        string(formatted);
    } else if (count < 1_200_000) {
        const thousands = @as(f64, @floatFromInt(count)) / 1000.0;
        const formatted = std.fmt.bufPrint(&temp_buf, "{d:.1}K", .{thousands}) catch {
            overflow = true;
            return;
        };
        string(formatted);
    } else if (count < 10_000_000) {
        const millions = @as(f64, @floatFromInt(count)) / 1_000_000.0;
        const formatted = std.fmt.bufPrint(&temp_buf, "{d:.2}M", .{millions}) catch {
            overflow = true;
            return;
        };
        string(formatted);
    } else if (count < 100_000_000) {
        const millions = @as(f64, @floatFromInt(count)) / 1_000_000.0;
        const formatted = std.fmt.bufPrint(&temp_buf, "{d:.1}M", .{millions}) catch {
            overflow = true;
            return;
        };
        string(formatted);
    } else {
        const millions = @as(f64, @floatFromInt(count)) / 1_000_000.0;
        const formatted = std.fmt.bufPrint(&temp_buf, "{d:.0}M", .{millions}) catch {
            overflow = true;
            return;
        };
        string(formatted);
    }
}

/// Formats and appends a time duration to the buffer
/// < 1200ms: prints as milliseconds (e.g., "1150ms")
/// 1200ms-10s: prints as seconds with 1 decimal (e.g., "5.2s")
/// 10s-60s: prints as seconds (e.g., "45s")
/// >= 60s: prints as minutes and seconds (e.g., "1m 30s")
pub fn time(ms: u64) void {
    if (overflow) return;

    var temp_buf: [32]u8 = undefined;

    if (ms < 1200) {
        const formatted = std.fmt.bufPrint(&temp_buf, "{d}ms", .{ms}) catch {
            overflow = true;
            return;
        };
        string(formatted);
    } else if (ms < 10_000) {
        const seconds = @as(f64, @floatFromInt(ms)) / 1000.0;
        const formatted = std.fmt.bufPrint(&temp_buf, "{d:.1}s", .{seconds}) catch {
            overflow = true;
            return;
        };
        string(formatted);
    } else if (ms < 60_000) {
        const seconds = ms / 1000;
        const formatted = std.fmt.bufPrint(&temp_buf, "{d}s", .{seconds}) catch {
            overflow = true;
            return;
        };
        string(formatted);
    } else {
        const total_seconds = ms / 1000;
        const minutes = total_seconds / 60;
        const seconds = total_seconds % 60;
        const formatted = std.fmt.bufPrint(&temp_buf, "{d}m {d}s", .{ minutes, seconds }) catch {
            overflow = true;
            return;
        };
        string(formatted);
    }
}

/// Formats and appends a cost/money amount to the buffer
/// Always prints with exactly 2 decimal places (e.g., "0.05", "12.00", "1234.56")
/// Does not include currency symbol - caller should append that separately
pub fn cost(amount: f64) void {
    if (overflow) return;

    var temp_buf: [32]u8 = undefined;
    const formatted = std.fmt.bufPrint(&temp_buf, "{d:.2}", .{amount}) catch {
        overflow = true;
        return;
    };
    string(formatted);
}

pub fn progress_bar(volume: u32, capacity: u32) error{InvalidInput}!void {
    if (capacity < 2 or volume > capacity) return error.InvalidInput;

    if (volume == 0) {
        char(PROGRESS_LEFT_EMPTY);
    } else {
        char(PROGRESS_LEFT_FULL);
    }

    const inner_progress = math.clamp(volume, 1, capacity - 1) - 1;
    const inner_remaining = (capacity - 2) - inner_progress;

    repeat(PROGRESS_INNER_FULL, inner_progress);
    repeat(PROGRESS_INNER_EMPTY, inner_remaining);

    if (volume == capacity) {
        char(PROGRESS_RIGHT_FULL);
    } else {
        char(PROGRESS_RIGHT_EMPTY);
    }
}

pub fn style(comptime fg: []const u8, comptime bg: []const u8) !void {
    string(try hexcode_to_ansi(38, fg));
    string(try hexcode_to_ansi(48, bg));
}

pub fn style_fg(comptime fg: []const u8) !void {
    string(try hexcode_to_ansi(38, fg));
}

pub fn style_bg(comptime bg: []const u8) !void {
    string(try hexcode_to_ansi(48, bg));
}

pub fn reset_bg() void {
    string("\u{001b}[49m");
}

pub fn reset_fg() void {
    string("\u{001b}[39m");
}

inline fn to_string(num: comptime_int) []const u8 {
    return std.fmt.comptimePrint("{}", .{num});
}

inline fn hexcode_to_ansi(ctl: comptime_int, hexcode: []const u8) ![]const u8 {
    if (hexcode[0] != '#' or hexcode.len != 7) @compileError("malformed colour code");
    const c = comptime std.fmt.parseInt(u32, hexcode[1..], 16) catch |err| @compileError("malformed colour code: " ++ @errorName(err));
    const r = @as(u8, (c >> 16) & 0xff);
    const g = @as(u8, (c >> 8) & 0xff);
    const b = @as(u8, c & 0xff);

    return "\u{001b}[" ++ to_string(ctl) ++ ";2;" ++ to_string(r) ++ ";" ++ to_string(g) ++ ";" ++ to_string(b) ++ "m";
}

test "string appends to buffer" {
    len = 0;
    overflow = false;

    string("hello");
    try std.testing.expectEqualStrings("hello", buf[0..len]);
    try std.testing.expectEqual(@as(usize, 5), len);
    try std.testing.expectEqual(false, overflow);

    string(" world");
    try std.testing.expectEqualStrings("hello world", buf[0..len]);
    try std.testing.expectEqual(@as(usize, 11), len);
}

test "char appends UTF-8 codepoints" {
    len = 0;
    overflow = false;

    char('A');
    try std.testing.expectEqual(@as(usize, 1), len);
    try std.testing.expectEqual(@as(u8, 'A'), buf[0]);

    char('🧠');
    try std.testing.expectEqual(@as(usize, 5), len);
    try std.testing.expectEqualStrings("A🧠", buf[0..len]);
}

test "overflow behavior" {
    len = 0;
    overflow = false;

    // Fill buffer to near capacity
    const large_str = "x" ** 500;
    string(large_str);
    try std.testing.expectEqual(@as(usize, 500), len);
    try std.testing.expectEqual(false, overflow);

    // This should trigger overflow
    string("this will overflow");
    try std.testing.expectEqual(true, overflow);
    try std.testing.expectEqual(@as(usize, 500), len); // len unchanged

    // Further appends should be no-ops
    string("more");
    try std.testing.expectEqual(@as(usize, 500), len);

    char('x');
    try std.testing.expectEqual(@as(usize, 500), len);

    repeat('y', 5);
    try std.testing.expectEqual(@as(usize, 500), len);
}

test "repeat with ASCII character" {
    len = 0;
    overflow = false;

    repeat('*', 10);
    try std.testing.expectEqualStrings("**********", buf[0..len]);
    try std.testing.expectEqual(@as(usize, 10), len);
}

test "repeat with multi-byte codepoint" {
    len = 0;
    overflow = false;

    repeat('🧠', 3);
    try std.testing.expectEqualStrings("🧠🧠🧠", buf[0..len]);
    try std.testing.expectEqual(@as(usize, 12), len); // 4 bytes * 3
}

test "present resets state" {
    len = 100;
    overflow = true;

    present();

    try std.testing.expectEqual(@as(usize, 0), len);
    try std.testing.expectEqual(false, overflow);
}

test "tokens formats small counts" {
    len = 0;
    overflow = false;

    tokens(1234);
    try std.testing.expectEqualStrings("1234", buf[0..len]);

    len = 0;
    tokens(1999);
    try std.testing.expectEqualStrings("1999", buf[0..len]);

    len = 0;
    tokens(0);
    try std.testing.expectEqualStrings("0", buf[0..len]);
}

test "tokens formats thousands with 1 decimal" {
    len = 0;
    overflow = false;

    tokens(2000);
    try std.testing.expectEqualStrings("2.0K", buf[0..len]);

    len = 0;
    tokens(12500);
    try std.testing.expectEqualStrings("12.5K", buf[0..len]);

    len = 0;
    tokens(1_199_999);
    try std.testing.expectEqualStrings("1200.0K", buf[0..len]);
}

test "tokens formats millions with 2 decimals (1.2M-10M)" {
    len = 0;
    overflow = false;

    tokens(1_200_000);
    try std.testing.expectEqualStrings("1.20M", buf[0..len]);

    len = 0;
    tokens(1_234_567);
    try std.testing.expectEqualStrings("1.23M", buf[0..len]);

    len = 0;
    tokens(9_999_999);
    try std.testing.expectEqualStrings("10.00M", buf[0..len]);
}

test "tokens formats millions with 1 decimal (10M-100M)" {
    len = 0;
    overflow = false;

    tokens(10_000_000);
    try std.testing.expectEqualStrings("10.0M", buf[0..len]);

    len = 0;
    tokens(12_345_678);
    try std.testing.expectEqualStrings("12.3M", buf[0..len]);

    len = 0;
    tokens(99_999_999);
    try std.testing.expectEqualStrings("100.0M", buf[0..len]);
}

test "tokens formats millions with 0 decimals (>=100M)" {
    len = 0;
    overflow = false;

    tokens(100_000_000);
    try std.testing.expectEqualStrings("100M", buf[0..len]);

    len = 0;
    tokens(123_456_789);
    try std.testing.expectEqualStrings("123M", buf[0..len]);

    len = 0;
    tokens(1_000_000_000);
    try std.testing.expectEqualStrings("1000M", buf[0..len]);
}

test "time formats milliseconds (<1200ms)" {
    len = 0;
    overflow = false;

    time(500);
    try std.testing.expectEqualStrings("500ms", buf[0..len]);

    len = 0;
    time(1150);
    try std.testing.expectEqualStrings("1150ms", buf[0..len]);

    len = 0;
    time(0);
    try std.testing.expectEqualStrings("0ms", buf[0..len]);
}

test "time formats seconds with 1 decimal (1200ms-10s)" {
    len = 0;
    overflow = false;

    time(1200);
    try std.testing.expectEqualStrings("1.2s", buf[0..len]);

    len = 0;
    time(5234);
    try std.testing.expectEqualStrings("5.2s", buf[0..len]);

    len = 0;
    time(9999);
    try std.testing.expectEqualStrings("10.0s", buf[0..len]);
}

test "time formats seconds (10s-60s)" {
    len = 0;
    overflow = false;

    time(10_000);
    try std.testing.expectEqualStrings("10s", buf[0..len]);

    len = 0;
    time(45_678);
    try std.testing.expectEqualStrings("45s", buf[0..len]);

    len = 0;
    time(59_999);
    try std.testing.expectEqualStrings("59s", buf[0..len]);
}

test "time formats minutes and seconds (>=60s)" {
    len = 0;
    overflow = false;

    time(60_000);
    try std.testing.expectEqualStrings("1m 0s", buf[0..len]);

    len = 0;
    time(90_000);
    try std.testing.expectEqualStrings("1m 30s", buf[0..len]);

    len = 0;
    time(125_000);
    try std.testing.expectEqualStrings("2m 5s", buf[0..len]);

    len = 0;
    time(3_661_000);
    try std.testing.expectEqualStrings("61m 1s", buf[0..len]);
}

test "cost formats with exactly 2 decimal places" {
    len = 0;
    overflow = false;

    cost(0.05);
    try std.testing.expectEqualStrings("0.05", buf[0..len]);

    len = 0;
    cost(12.00);
    try std.testing.expectEqualStrings("12.00", buf[0..len]);

    len = 0;
    cost(1234.56);
    try std.testing.expectEqualStrings("1234.56", buf[0..len]);

    len = 0;
    cost(0.00);
    try std.testing.expectEqualStrings("0.00", buf[0..len]);

    len = 0;
    cost(999.99);
    try std.testing.expectEqualStrings("999.99", buf[0..len]);

    len = 0;
    cost(0.1);
    try std.testing.expectEqualStrings("0.10", buf[0..len]);
}
