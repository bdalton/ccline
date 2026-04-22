const std = @import("std");
const buf = @import("renderer.zig");
const message = @import("message.zig");
const math = std.math;

fn calculate_progress_units(percentage: f64, progress_bar_size: u32) !u32 {
    if (progress_bar_size < 2) return error.InvalidProgressBarSize;

    const clamped_pct = math.clamp(percentage, 0.0, 100.0);

    if (clamped_pct == 0.0) {
        return 0;
    }

    const scaled = clamped_pct / 100.0 * @as(f64, @floatFromInt(progress_bar_size));
    const rounded_up = @ceil(scaled);
    const n = @as(u32, @intFromFloat(rounded_up));

    // Ensure n < progress_bar_size
    return @min(n, progress_bar_size - 1);
}

fn status_line(msg: *const message.Message) !void {
    // const POWERLINE_PILL_LEFT = '\u{e0b6}';
    // const BRAIN_EMOJI = "🧠";
    // const MONEY_EMOJI = "💰";
    // const STOPWATCH_EMOJI = "⏱️";

    const pill0 = "#e8e3d6";
    const pill1 = "#b1ada1";

    const ctx_progress_size = 40;
    const used_pct = msg.context_window.used_percentage orelse 0.0;
    const ctx_progress = try calculate_progress_units(used_pct, ctx_progress_size);

    try buf.style_fg(pill0);
    buf.string("\u{e0b6}");
    try buf.style("#c15f3c", pill0);
    buf.string(" \u{2732} ");
    try buf.style("#3a2e1f", pill0);
    buf.string(msg.model.display_name);
    buf.char(' ');
    try buf.style_fg("#c15f3c");
    try buf.progress_bar(ctx_progress, ctx_progress_size);
    try buf.style_fg("#3a2e1f");
    buf.char(' ');
    buf.tokens(msg.estimate_used_tokens());
    buf.char(' ');
    try buf.style(pill0, pill1);
    buf.char('\u{e0bc}');
    try buf.style("#000000", pill1);
    buf.string(" \u{e0a0} ");
    buf.string("\u{eadc} ");
    buf.tokens(msg.cost.total_lines_added);
    buf.string(" \u{eadf} ");
    buf.tokens(msg.cost.total_lines_removed);
    buf.string(" \u{f40a} ");
    buf.tokens(msg.context_window.total_input_tokens);
    buf.string(" \u{f409} ");
    buf.tokens(msg.context_window.total_output_tokens);
    if (msg.rate_limits == null) {
        buf.string(" \u{e641} ");
        buf.time(msg.cost.total_api_duration_ms);
    }
    buf.reset_bg();
    try buf.style_fg(pill1);
    buf.string("\u{e0b4} ");
    buf.present();

    if (msg.rate_limits) |rl| {
        const fh_bar_size: u32 = ctx_progress_size;
        const wk_bar_size: u32 = 20;
        const fh_pct = if (rl.five_hour) |w| w.used_percentage else 0.0;
        const sd_pct = if (rl.seven_day) |w| w.used_percentage else 0.0;
        const fh_progress = try calculate_progress_units(fh_pct, fh_bar_size);
        const sd_progress = try calculate_progress_units(sd_pct, wk_bar_size);
        const fh_pct_int = @as(u64, @intFromFloat(@round(math.clamp(fh_pct, 0.0, 100.0))));
        const sd_pct_int = @as(u64, @intFromFloat(@round(math.clamp(sd_pct, 0.0, 100.0))));

        const model_len = msg.model.display_name.len;
        const time_str_len = buf.time_len(msg.cost.total_api_duration_ms);
        const padding_raw: i64 = @as(i64, @intCast(model_len)) - @as(i64, @intCast(time_str_len)) - 4;
        const padding: usize = if (padding_raw > 1) @as(usize, @intCast(padding_raw)) else 1;

        buf.string("\u{00a0}\u{00a0}");
        try buf.style_fg(pill0);
        buf.string("\u{001b}[7m\u{e0b4}\u{001b}[27m");
        try buf.style("#3a2e1f", pill0);
        buf.string("   \u{e641} ");
        buf.time(msg.cost.total_api_duration_ms);
        for (0..padding) |_| buf.char(' ');
        buf.string("5h ");
        try buf.style_fg("#c15f3c");
        try buf.progress_bar(fh_progress, fh_bar_size);
        try buf.style_fg("#3a2e1f");
        buf.char(' ');
        buf.tokens(fh_pct_int);
        buf.string("% ");
        try buf.style(pill0, pill1);
        buf.char('\u{e0bc}');
        try buf.style("#000000", pill1);
        buf.string(" wk ");
        try buf.progress_bar(sd_progress, wk_bar_size);
        buf.char(' ');
        buf.tokens(sd_pct_int);
        buf.string("%");
        buf.reset_bg();
        try buf.style_fg(pill1);
        buf.string("\u{001b}[7m\u{e0b6}\u{001b}[27m");
        buf.present();
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed_msg = try message.parse_message_from_stdin(allocator);
    defer parsed_msg.deinit();

    try status_line(&parsed_msg.parsed.value);
}
