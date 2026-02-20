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

    const pill0 = "#777755";
    const pill1 = "#555533";
    const pill2 = "#333311";

    const ctx_progress_size = 50;
    const ctx_progress = try calculate_progress_units(msg.context_window.used_percentage, ctx_progress_size);

    try buf.style_fg(pill0);
    buf.string("  \u{e0b6}");
    try buf.style("#ffffff", pill0);
    buf.string(" 🧠 ");
    buf.string(msg.model.display_name);
    buf.char(' ');
    try buf.progress_bar(ctx_progress, ctx_progress_size);
    buf.char(' ');
    buf.tokens(msg.estimate_used_tokens());
    buf.char(' ');
    try buf.style(pill0, pill1);
    buf.char('\u{e0bc}');
    try buf.style("#ffffff", pill1);
    buf.string(" \u{e0a0} ");
    try buf.style("#77ee77", pill1);
    buf.string("\u{eadc} ");
    buf.tokens(msg.cost.total_lines_added);
    try buf.style("#ee7799", pill1);
    buf.string(" \u{eadf} ");
    buf.tokens(msg.cost.total_lines_removed);
    buf.char(' ');
    try buf.style(pill1, pill2);
    buf.string("\u{e0bc} ");
    try buf.style("#aaaa99", pill2);
    buf.string("\u{f40a} ");
    buf.tokens(msg.context_window.total_input_tokens);
    buf.string(" \u{f409} ");
    buf.tokens(msg.context_window.total_output_tokens);
    buf.string(" \u{e641} ");
    buf.time(msg.cost.total_api_duration_ms);
    // buf.string(" 💰 ");
    buf.string(" \u{ef8d} ");
    buf.cost(msg.cost.total_cost_usd);
    buf.reset_bg();
    try buf.style_fg(pill2);
    buf.string("\u{e0b4} ");
    buf.present();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parsed_msg = try message.parse_message_from_stdin(allocator);
    defer parsed_msg.deinit();

    try status_line(&parsed_msg.parsed.value);
}
