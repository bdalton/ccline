const std = @import("std");

/// Nested struct for model information
pub const Model = struct {
    id: []const u8,
    display_name: []const u8,
};

/// Nested struct for workspace information
pub const Workspace = struct {
    current_dir: []const u8,
    project_dir: ?[]const u8 = null,
    /// Directories added via `/add-dir` or `--add-dir`. Empty array if none.
    added_dirs: []const []const u8 = &.{},
    /// Git worktree name when inside a linked worktree created with `git worktree add`.
    /// Absent in the main working tree.
    git_worktree: ?[]const u8 = null,
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

/// Token counts from the last API call
pub const CurrentUsage = struct {
    input_tokens: u64,
    output_tokens: u64,
    cache_creation_input_tokens: u64,
    cache_read_input_tokens: u64,
};

/// Nested struct for context window information.
/// `used_percentage`, `remaining_percentage`, and `current_usage` are null
/// before the first API call in a session.
pub const ContextWindow = struct {
    total_input_tokens: u64,
    total_output_tokens: u64,
    context_window_size: u64,
    used_percentage: ?f64 = null,
    remaining_percentage: ?f64 = null,
    current_usage: ?CurrentUsage = null,
};

/// A single rate limit window (five_hour or seven_day)
pub const RateLimitWindow = struct {
    used_percentage: f64,
    resets_at: u64,
};

/// Rate limit usage for Claude.ai Pro/Max subscribers.
/// Each window may be independently absent.
pub const RateLimits = struct {
    five_hour: ?RateLimitWindow = null,
    seven_day: ?RateLimitWindow = null,
};

/// Vim editor mode ("NORMAL" or "INSERT")
pub const Vim = struct {
    mode: ?[]const u8 = null,
};

/// Agent information when running with --agent
pub const Agent = struct {
    name: ?[]const u8 = null,
};

/// Active `--worktree` session info. `branch` and `original_branch`
/// may be absent for hook-based worktrees.
pub const Worktree = struct {
    name: []const u8,
    path: []const u8,
    branch: ?[]const u8 = null,
    original_cwd: []const u8,
    original_branch: ?[]const u8 = null,
};

/// Top-level message struct matching Claude Code's status line JSON payload.
/// Reference: https://code.claude.com/docs/en/statusline
pub const Message = struct {
    cwd: []const u8,
    session_id: []const u8,
    /// Custom name set with `--name` or `/rename`. Absent if unset.
    session_name: ?[]const u8 = null,
    transcript_path: []const u8,
    model: Model,
    workspace: Workspace,
    version: []const u8,
    output_style: OutputStyle,
    cost: Cost,
    context_window: ContextWindow,
    exceeds_200k_tokens: bool,
    rate_limits: ?RateLimits = null,
    vim: ?Vim = null,
    agent: ?Agent = null,
    worktree: ?Worktree = null,

    /// Estimates tokens used based on used_percentage and context_window_size.
    /// Returns 0 when used_percentage is null (pre-first-API-response).
    pub fn estimate_used_tokens(self: *const Message) u64 {
        const used_pct = self.context_window.used_percentage orelse return 0;
        const window_size = @as(f64, @floatFromInt(self.context_window.context_window_size));
        const used_tokens = (used_pct / 100.0) * window_size;
        return @as(u64, @intFromFloat(@round(used_tokens)));
    }
};

/// Parse a JSON string into a Message struct.
/// Caller must call .deinit() on the returned Parsed(Message) when done.
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

/// Read JSON from stdin and parse into a Message struct.
/// Caller must call .deinit() on the returned ParsedMessage when done.
pub fn parse_message_from_stdin(allocator: std.mem.Allocator, io: std.Io) !ParsedMessage {
    var read_buffer: [4096]u8 = undefined;
    var file_reader = std.Io.File.stdin().reader(io, &read_buffer);
    const json_data = try file_reader.interface.allocRemaining(allocator, .limited(32768)); // 32KB max
    errdefer allocator.free(json_data);

    const parsed = try parse_message(allocator, json_data);
    errdefer parsed.deinit();

    return ParsedMessage{
        .json_data = json_data,
        .parsed = parsed,
        .allocator = allocator,
    };
}

test "parse full message from JSON" {
    const allocator = std.testing.allocator;

    const json_string =
        \\{
        \\  "cwd": "/Users/test/project",
        \\  "session_id": "abc123",
        \\  "session_name": "my-session",
        \\  "transcript_path": "/path/to/transcript.jsonl",
        \\  "model": {
        \\    "id": "claude-opus-4-7",
        \\    "display_name": "Opus"
        \\  },
        \\  "workspace": {
        \\    "current_dir": "/Users/test/project",
        \\    "project_dir": "/Users/test/project",
        \\    "added_dirs": ["/Users/test/extra"],
        \\    "git_worktree": "feature-xyz"
        \\  },
        \\  "version": "2.1.90",
        \\  "output_style": { "name": "default" },
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
        \\  "rate_limits": {
        \\    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
        \\    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
        \\  },
        \\  "vim": { "mode": "NORMAL" },
        \\  "agent": { "name": "security-reviewer" },
        \\  "worktree": {
        \\    "name": "my-feature",
        \\    "path": "/path/to/.claude/worktrees/my-feature",
        \\    "branch": "worktree-my-feature",
        \\    "original_cwd": "/path/to/project",
        \\    "original_branch": "main"
        \\  }
        \\}
    ;

    const parsed = try parse_message(allocator, json_string);
    defer parsed.deinit();

    const msg = parsed.value;

    try std.testing.expectEqualStrings("/Users/test/project", msg.cwd);
    try std.testing.expectEqualStrings("abc123", msg.session_id);
    try std.testing.expectEqualStrings("my-session", msg.session_name.?);
    try std.testing.expectEqualStrings("claude-opus-4-7", msg.model.id);
    try std.testing.expectEqualStrings("Opus", msg.model.display_name);
    try std.testing.expectEqualStrings("/Users/test/project", msg.workspace.current_dir);
    try std.testing.expectEqualStrings("/Users/test/project", msg.workspace.project_dir.?);
    try std.testing.expectEqual(@as(usize, 1), msg.workspace.added_dirs.len);
    try std.testing.expectEqualStrings("/Users/test/extra", msg.workspace.added_dirs[0]);
    try std.testing.expectEqualStrings("feature-xyz", msg.workspace.git_worktree.?);
    try std.testing.expectEqualStrings("2.1.90", msg.version);
    try std.testing.expectEqualStrings("default", msg.output_style.name);
    try std.testing.expectEqual(@as(f64, 0.05), msg.cost.total_cost_usd);
    try std.testing.expectEqual(@as(u64, 1500), msg.cost.total_duration_ms);
    try std.testing.expectEqual(@as(u64, 100), msg.cost.total_lines_added);
    try std.testing.expectEqual(@as(u64, 5000), msg.context_window.total_input_tokens);
    try std.testing.expectEqual(@as(u64, 200000), msg.context_window.context_window_size);
    try std.testing.expectEqual(@as(f64, 3.5), msg.context_window.used_percentage.?);
    try std.testing.expectEqual(@as(u64, 1000), msg.context_window.current_usage.?.input_tokens);
    try std.testing.expectEqual(false, msg.exceeds_200k_tokens);
    try std.testing.expectEqual(@as(f64, 23.5), msg.rate_limits.?.five_hour.?.used_percentage);
    try std.testing.expectEqual(@as(u64, 1738857600), msg.rate_limits.?.seven_day.?.resets_at);
    try std.testing.expectEqualStrings("NORMAL", msg.vim.?.mode.?);
    try std.testing.expectEqualStrings("security-reviewer", msg.agent.?.name.?);
    try std.testing.expectEqualStrings("my-feature", msg.worktree.?.name);
    try std.testing.expectEqualStrings("worktree-my-feature", msg.worktree.?.branch.?);
    try std.testing.expectEqualStrings("main", msg.worktree.?.original_branch.?);
}

test "parse minimal message (pre-first-API-response)" {
    const allocator = std.testing.allocator;

    // context_window values may be null before the first API response;
    // optional top-level blocks (rate_limits, vim, agent, worktree, session_name) are absent.
    const json_string =
        \\{
        \\  "cwd": "/tmp/p",
        \\  "session_id": "s",
        \\  "transcript_path": "/tmp/t.jsonl",
        \\  "model": { "id": "claude-opus-4-7", "display_name": "Opus" },
        \\  "workspace": { "current_dir": "/tmp/p", "project_dir": "/tmp/p", "added_dirs": [] },
        \\  "version": "2.1.90",
        \\  "output_style": { "name": "default" },
        \\  "cost": {
        \\    "total_cost_usd": 0.0, "total_duration_ms": 0, "total_api_duration_ms": 0,
        \\    "total_lines_added": 0, "total_lines_removed": 0
        \\  },
        \\  "context_window": {
        \\    "total_input_tokens": 0, "total_output_tokens": 0, "context_window_size": 200000,
        \\    "used_percentage": null, "remaining_percentage": null, "current_usage": null
        \\  },
        \\  "exceeds_200k_tokens": false
        \\}
    ;

    const parsed = try parse_message(allocator, json_string);
    defer parsed.deinit();

    const msg = parsed.value;
    try std.testing.expect(msg.context_window.used_percentage == null);
    try std.testing.expect(msg.context_window.current_usage == null);
    try std.testing.expect(msg.rate_limits == null);
    try std.testing.expect(msg.vim == null);
    try std.testing.expect(msg.worktree == null);
    try std.testing.expectEqual(@as(u64, 0), msg.estimate_used_tokens());
}

test "estimate_used_tokens calculates correctly" {
    const msg = Message{
        .cwd = "/test",
        .session_id = "test",
        .transcript_path = "/test",
        .model = .{ .id = "test", .display_name = "Test" },
        .workspace = .{ .current_dir = "/test" },
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
    };

    // 3.5% of 200,000 = 7,000
    try std.testing.expectEqual(@as(u64, 7000), msg.estimate_used_tokens());
}
