const std = @import("std");

/// Nested struct for model information
pub const Model = struct {
    id: []const u8,
    display_name: []const u8,
};

/// Nested struct for workspace information
pub const Workspace = struct {
    current_dir: []const u8,
    project_dir: ?[]const u8,
};

/// Nested struct for output style
pub const OutputStyle = struct {
    name: []const u8,
};

/// Nested struct for cost tracking
pub const Cost = struct {
    total_cost_usd: f64,
    total_duration_ms: u64,
    total_api_duration_ms: u64,
    total_lines_added: u64,
    total_lines_removed: u64,
};

/// Nested struct for current token usage
pub const CurrentUsage = struct {
    input_tokens: u64,
    output_tokens: u64,
    cache_creation_input_tokens: u64,
    cache_read_input_tokens: u64,
};

/// Nested struct for context window information
pub const ContextWindow = struct {
    total_input_tokens: u64,
    total_output_tokens: u64,
    context_window_size: u64,
    used_percentage: f64,
    remaining_percentage: f64,
    current_usage: CurrentUsage,
};

/// Nested struct for vim mode
pub const Vim = struct {
    mode: ?[]const u8,
};

/// Nested struct for agent information
pub const Agent = struct {
    name: ?[]const u8,
};

/// Top-level message struct matching Claude Code's status line/session data
pub const Message = struct {
    cwd: []const u8,
    session_id: []const u8,
    transcript_path: []const u8,
    model: Model,
    workspace: Workspace,
    version: []const u8,
    output_style: OutputStyle,
    cost: Cost,
    context_window: ContextWindow,
    exceeds_200k_tokens: bool,
    vim: ?Vim = null,
    agent: ?Agent = null,

    /// Estimates the number of tokens used based on used_percentage and context_window_size
    pub fn estimate_used_tokens(self: *const Message) u64 {
        const used_pct = self.context_window.used_percentage;
        const window_size = @as(f64, @floatFromInt(self.context_window.context_window_size));
        const used_tokens = (used_pct / 100.0) * window_size;
        return @as(u64, @intFromFloat(@round(used_tokens)));
    }
};

/// Parse a JSON string into a Message struct
/// Caller must call .deinit() on the returned Parsed(Message) when done
pub fn parse_message(allocator: std.mem.Allocator, json_string: []const u8) !std.json.Parsed(Message) {
    return std.json.parseFromSlice(Message, allocator, json_string, .{ .ignore_unknown_fields = true });
}

/// Wrapper that owns both the JSON data and the parsed result
pub const ParsedMessage = struct {
    json_data: []const u8,
    parsed: std.json.Parsed(Message),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParsedMessage) void {
        self.parsed.deinit();
        self.allocator.free(self.json_data);
    }
};

/// Read JSON from stdin and parse into a Message struct
/// Caller must call .deinit() on the returned ParsedMessage when done
pub fn parse_message_from_stdin(allocator: std.mem.Allocator) !ParsedMessage {
    const stdin_file = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    const json_data = try stdin_file.readToEndAlloc(allocator, 32768); // 32KB max
    errdefer allocator.free(json_data);

    const parsed = try parse_message(allocator, json_data);
    errdefer parsed.deinit();

    return ParsedMessage{
        .json_data = json_data,
        .parsed = parsed,
        .allocator = allocator,
    };
}

test "parse message from JSON" {
    const allocator = std.testing.allocator;

    const json_string =
        \\{
        \\  "cwd": "/Users/test/project",
        \\  "session_id": "abc123",
        \\  "transcript_path": "/path/to/transcript.jsonl",
        \\  "model": {
        \\    "id": "claude-sonnet-4-5-20250929",
        \\    "display_name": "Sonnet 4.5"
        \\  },
        \\  "workspace": {
        \\    "current_dir": "/Users/test/project",
        \\    "project_dir": "/Users/test/project"
        \\  },
        \\  "version": "1.0.0",
        \\  "output_style": {
        \\    "name": "standard"
        \\  },
        \\  "cost": {
        \\    "total_cost_usd": 0.05,
        \\    "total_duration_ms": 1500,
        \\    "total_api_duration_ms": 1200,
        \\    "total_lines_added": 100,
        \\    "total_lines_removed": 50
        \\  },
        \\  "context_window": {
        \\    "total_input_tokens": 5000,
        \\    "total_output_tokens": 2000,
        \\    "context_window_size": 200000,
        \\    "used_percentage": 3.5,
        \\    "remaining_percentage": 96.5,
        \\    "current_usage": {
        \\      "input_tokens": 1000,
        \\      "output_tokens": 500,
        \\      "cache_creation_input_tokens": 100,
        \\      "cache_read_input_tokens": 50
        \\    }
        \\  },
        \\  "exceeds_200k_tokens": false,
        \\  "vim": {
        \\    "mode": "normal"
        \\  },
        \\  "agent": {
        \\    "name": "test-agent"
        \\  }
        \\}
    ;

    const parsed = try parse_message(allocator, json_string);
    defer parsed.deinit();

    const msg = parsed.value;

    // Assert key field values
    try std.testing.expectEqualStrings("/Users/test/project", msg.cwd);
    try std.testing.expectEqualStrings("abc123", msg.session_id);
    try std.testing.expectEqualStrings("claude-sonnet-4-5-20250929", msg.model.id);
    try std.testing.expectEqualStrings("Sonnet 4.5", msg.model.display_name);
    try std.testing.expectEqualStrings("/Users/test/project", msg.workspace.current_dir);
    try std.testing.expectEqualStrings("/Users/test/project", msg.workspace.project_dir.?);
    try std.testing.expectEqualStrings("1.0.0", msg.version);
    try std.testing.expectEqualStrings("standard", msg.output_style.name);
    try std.testing.expectEqual(@as(f64, 0.05), msg.cost.total_cost_usd);
    try std.testing.expectEqual(@as(u64, 1500), msg.cost.total_duration_ms);
    try std.testing.expectEqual(@as(u64, 100), msg.cost.total_lines_added);
    try std.testing.expectEqual(@as(u64, 5000), msg.context_window.total_input_tokens);
    try std.testing.expectEqual(@as(u64, 200000), msg.context_window.context_window_size);
    try std.testing.expectEqual(@as(f64, 3.5), msg.context_window.used_percentage);
    try std.testing.expectEqual(@as(u64, 1000), msg.context_window.current_usage.input_tokens);
    try std.testing.expectEqual(false, msg.exceeds_200k_tokens);
    try std.testing.expectEqualStrings("normal", msg.vim.mode.?);
    try std.testing.expectEqualStrings("test-agent", msg.agent.name.?);
}

test "estimate_used_tokens calculates correctly" {
    const msg = Message{
        .cwd = "/test",
        .session_id = "test",
        .transcript_path = "/test",
        .model = .{ .id = "test", .display_name = "Test" },
        .workspace = .{ .current_dir = "/test", .project_dir = null },
        .version = "1.0.0",
        .output_style = .{ .name = "standard" },
        .cost = .{
            .total_cost_usd = 0.0,
            .total_duration_ms = 0,
            .total_api_duration_ms = 0,
            .total_lines_added = 0,
            .total_lines_removed = 0,
        },
        .context_window = .{
            .total_input_tokens = 0,
            .total_output_tokens = 0,
            .context_window_size = 200000,
            .used_percentage = 3.5,
            .remaining_percentage = 96.5,
            .current_usage = .{
                .input_tokens = 0,
                .output_tokens = 0,
                .cache_creation_input_tokens = 0,
                .cache_read_input_tokens = 0,
            },
        },
        .exceeds_200k_tokens = false,
        .vim = .{ .mode = null },
        .agent = .{ .name = null },
    };

    // 3.5% of 200,000 = 7,000
    const used_tokens = msg.estimate_used_tokens();
    try std.testing.expectEqual(@as(u64, 7000), used_tokens);
}
