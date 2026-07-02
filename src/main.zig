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

fn status_line(io: std.Io, msg: *const message.Message) !void {
    // const POWERLINE_PILL_LEFT = '\u{e0b6}';
    // const BRAIN_EMOJI = "🧠";
    // const MONEY_EMOJI = "💰";
    // const STOPWATCH_EMOJI = "⏱️";

    const pill0 = "#e8e3d6";
    const pill1 = "#b1ada1";

    const ctx_progress_size = 40;
    const wk_bar_size: u32 = 20;
    const used_pct = msg.context_window.used_percentage orelse 0.0;
    const ctx_progress = try calculate_progress_units(used_pct, ctx_progress_size);

    // Right-pill alignment: when both rows render, pre-compute each row's
    // post-middle-chevron visible width and pad the shorter row so the
    // right-pill caps land in the same column. Line 2 always has at least
    // one space between "%" and its right pill (baked into "% "); any
    // extra padding comes from this calculation.
    //
    // Line 1 post-chevron visible width (rate_limits present, so no ⏱ time):
    //   " \u{e0a0} " + "\u{eadc} " + tokens(added) + " \u{eadf} " + tokens(removed)
    //   + " \u{f40a} " + tokens(input) + " \u{f409} " + tokens(output)
    //   = 14 + L_added + L_removed + L_input + L_output
    //
    // Line 2 post-chevron visible width:
    //   " wk " + progress_bar(wk_bar_size) + " " + tokens(sd_pct) + "% "
    //   = 27 + L_sd_pct
    var line1_left_pad: usize = 0;
    var line2_time_pad: usize = 1;
    var line1_right_pad: usize = 0;
    var line2_right_pad: usize = 0;
    if (msg.rate_limits) |rl| {
        // Left-edge alignment: line 1's context bar starts at column
        // (5 + model_len); line 2's 5h bar at (9 + time_len + time_pad).
        // Setting them equal yields the padding. time_pad has a floor of 1
        // (a legible gap between the thinking time and "5h"), so when the
        // model name is short — making line 2's prefix intrinsically wider —
        // we cannot shrink time_pad to compensate and instead pad line 1
        // rightward. With a long model name, line1_left_pad is 0 and time_pad
        // absorbs the difference (the original behavior). Aligning the bars
        // this way also keeps the two middle chevrons chained, since the
        // diagonal invariant reduces to the same equation.
        const model_len = msg.model.display_name.len;
        const time_str_len = buf.time_len(msg.cost.total_api_duration_ms);
        const bar_col: usize = @max(5 + model_len, 10 + time_str_len);
        line1_left_pad = bar_col - (5 + model_len);
        line2_time_pad = bar_col - 9 - time_str_len;

        const sd_pct_for_w = if (rl.seven_day) |w| w.used_percentage else 0.0;
        const sd_pct_int_w = @as(u64, @intFromFloat(@round(math.clamp(sd_pct_for_w, 0.0, 100.0))));
        const line1_w: usize = 14 +
            buf.tokens_len(msg.cost.total_lines_added) +
            buf.tokens_len(msg.cost.total_lines_removed) +
            buf.tokens_len(msg.context_window.total_input_tokens) +
            buf.tokens_len(msg.context_window.total_output_tokens);
        const line2_w: usize = 4 + wk_bar_size + 1 + buf.tokens_len(sd_pct_int_w) + 2;
        // Line 2's middle chevron sits 1 col left of line 1's (diagonal
        // invariant), so line 2 must render 1 col *wider* past the chevron
        // to reach the same final column. Pad both rows up to that target.
        const target: usize = @max(line1_w + 1, line2_w);
        line1_right_pad = target - line1_w - 1;
        line2_right_pad = target - line2_w;
    }

    try buf.style_fg(pill0);
    buf.string("\u{e0b6}");
    try buf.style("#c15f3c", pill0);
    buf.string(" \u{2732} ");
    try buf.style("#3a2e1f", pill0);
    buf.string(msg.model.display_name);
    buf.char(' ');
    buf.repeat(' ', line1_left_pad);
    try buf.style_fg("#c15f3c");
    try buf.progress_bar(ctx_progress, ctx_progress_size);
    try buf.style_fg("#3a2e1f");
    buf.char(' ');
    buf.tokens_padded(msg.estimate_used_tokens(), 7);
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
    buf.repeat(' ', line1_right_pad);
    buf.reset_bg();
    try buf.style_fg(pill1);
    buf.string("\u{e0b4} ");
    buf.present(io);

    if (msg.rate_limits) |rl| {
        const fh_bar_size: u32 = ctx_progress_size;
        const fh_pct = if (rl.five_hour) |w| w.used_percentage else 0.0;
        const sd_pct = if (rl.seven_day) |w| w.used_percentage else 0.0;
        const fh_progress = try calculate_progress_units(fh_pct, fh_bar_size);
        const sd_progress = try calculate_progress_units(sd_pct, wk_bar_size);
        const fh_pct_int = @as(u64, @intFromFloat(@round(math.clamp(fh_pct, 0.0, 100.0))));
        const sd_pct_int = @as(u64, @intFromFloat(@round(math.clamp(sd_pct, 0.0, 100.0))));

        buf.string("\u{00a0}\u{00a0}");
        try buf.style_fg(pill0);
        buf.string("\u{001b}[7m\u{e0b4}\u{001b}[27m");
        try buf.style("#3a2e1f", pill0);
        buf.string("   \u{e641} ");
        buf.time(msg.cost.total_api_duration_ms);
        buf.repeat(' ', line2_time_pad);
        buf.string("5h ");
        try buf.style_fg("#c15f3c");
        try buf.progress_bar(fh_progress, fh_bar_size);
        try buf.style_fg("#3a2e1f");
        buf.char(' ');
        buf.tokens_padded(fh_pct_int, 5);
        buf.string("% ");
        try buf.style(pill0, pill1);
        buf.char('\u{e0bc}');
        try buf.style("#000000", pill1);
        buf.string(" wk ");
        try buf.progress_bar(sd_progress, wk_bar_size);
        buf.char(' ');
        buf.tokens(sd_pct_int);
        buf.string("% ");
        buf.repeat(' ', line2_right_pad);
        buf.reset_bg();
        try buf.style_fg(pill1);
        buf.string("\u{001b}[7m\u{e0b6}\u{001b}[27m");
        buf.present(io);
    }
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var parsed_msg = try message.parse_message_from_stdin(allocator, io);
    defer parsed_msg.deinit();

    try status_line(io, &parsed_msg.parsed.value);
}
