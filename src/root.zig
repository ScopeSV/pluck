const std = @import("std");
const Io = std.Io;

pub const Value = union(enum) {
    Bool: bool,
    Int: usize,
    Str: []const u8,
};

pub const FlagType = enum {
    Bool,
    Int,
    Str,
};

pub const Flags = struct {
    long: []const u8,
    short: []const u8,
    desc: []const u8,
    type: FlagType,
};

pub const Context = struct {
    msg: []const u8 = "Hello from the CLI parser!",
    userArgs: []const []const u8,
    flags: std.StringHashMap(Value),

    pub fn flagBool(self: Context, f: []const u8) bool {
        const val = self.flags.get(f) orelse return false;
        return val.Bool;
    }
    pub fn flagInt(self: Context, f: []const u8) usize {
        const val = self.flags.get(f) orelse return 0;
        return val.Int;
    }
    pub fn flagStr(self: Context, f: []const u8) []const u8 {
        const val = self.flags.get(f) orelse return "";
        return val.Str;
    }
};

pub const Command = struct {
    name: []const u8,
    desc: []const u8,
    flags: []const Flags = &.{},
    run: *const fn (Context) anyerror!void,
};

pub const Positional = struct {
    name: []const u8,
    desc: []const u8,
};

pub const Config = struct {
    name: []const u8,
    desc: []const u8,
    userArgs: []const []const u8,
    flags: []const Flags,
    run: *const fn (Context) anyerror!void,
    positionals: ?[]const Positional = null,
    commands: ?[]const Command = null,
};

fn matchCommands(alloc: std.mem.Allocator, cfg: Config, arg: []const u8, i: usize) anyerror!bool {
    const commands = cfg.commands orelse return false;
    for (commands) |cmd| {
        if (std.mem.eql(u8, cmd.name, arg)) {
            const subConfig = Config{
                .name = cmd.name,
                .desc = cmd.desc,
                .userArgs = cfg.userArgs[i..],
                .flags = cmd.flags,
                .run = cmd.run,
            };
            try parse(alloc, subConfig);
            return true;
        }
    }
    return false;
}

fn matchFlags(cfg: Config, arg: []const u8, i: *usize, flagMap: *std.StringHashMap(Value), matched: *bool) !void {
    for (cfg.flags) |flag| {
        if (std.mem.eql(u8, flag.long, arg) or std.mem.eql(u8, flag.short, arg)) {
            if (flag.type == .Bool) {
                try flagMap.put(flag.long[2..], Value{ .Bool = true });
                matched.* = true;
            } else if (flag.type == .Int) {
                i.* += 1;
                const v = std.fmt.parseInt(usize, cfg.userArgs[i.*], 10) catch 0;
                try flagMap.put(flag.long[2..], Value{ .Int = v });
                matched.* = true;
            } else if (flag.type == .Str) {
                i.* += 1;
                const strArg = cfg.userArgs[i.*];
                try flagMap.put(flag.long[2..], Value{ .Str = strArg });
                matched.* = true;
            }
        }
    }
}

fn handlePositionals(cfg: Config, arg: []const u8, positionalEdx: *usize, flagMap: *std.StringHashMap(Value)) !void {
    if (cfg.positionals) |positionals| {
        if (positionalEdx.* < positionals.len) {
            try flagMap.put(positionals[positionalEdx.*].name, Value{ .Str = arg });
            positionalEdx.* += 1;
        }
    }
}

pub fn parse(
    alloc: std.mem.Allocator,
    cfg: Config,
) !void {
    var flagMap = std.StringHashMap(Value).init(alloc);
    defer flagMap.deinit();

    var i: usize = 1;
    var positionalEdx: usize = 0;
    while (i < cfg.userArgs.len) : (i += 1) {
        const arg = cfg.userArgs[i];

        if (try matchCommands(alloc, cfg, arg, i)) return;

        var matched = false;
        try matchFlags(cfg, arg, &i, &flagMap, &matched);

        if (!matched) {
            try handlePositionals(cfg, arg, &positionalEdx, &flagMap);
        }
    }

    try cfg.run(Context{
        .msg = "Running the CLI parser!",
        .userArgs = cfg.userArgs,
        .flags = flagMap,
    });
}

const testFlags = &[_]Flags{
    .{ .long = "--all", .short = "-a", .desc = "Show hidden files", .type = .Bool },
    .{ .long = "--depth", .short = "-d", .desc = "Max depth", .type = .Int },
    .{ .long = "--name", .short = "-n", .desc = "Name", .type = .Str },
};

fn testAssertFlags(ctx: Context) !void {
    try std.testing.expect(ctx.flagBool("all") == true);
    try std.testing.expect(ctx.flagInt("depth") == 4);
    try std.testing.expect(std.mem.eql(u8, ctx.flagStr("name"), "Zig"));
}

test "parses long flags" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "--all", "--depth", "4", "--name", "Zig" },
        .run = &testAssertFlags,
        .flags = testFlags,
    };
    try parse(std.testing.allocator, config);
}

test "parses short flags" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "-a", "-d", "4", "-n", "Zig" },
        .run = &testAssertFlags,
        .flags = testFlags,
    };
    try parse(std.testing.allocator, config);
}

fn testDefaults(ctx: Context) !void {
    try std.testing.expect(ctx.flagBool("all") == false);
    try std.testing.expect(ctx.flagInt("depth") == 0);
    try std.testing.expect(std.mem.eql(u8, ctx.flagStr("name"), ""));
}

test "unset flags return defaults" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{"test"},
        .run = &testDefaults,
        .flags = testFlags,
    };
    try parse(std.testing.allocator, config);
}

fn testPositionals(ctx: Context) !void {
    try std.testing.expect(std.mem.eql(u8, ctx.flagStr("path"), "/some/path"));
}

test "parses positionals" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "/some/path" },
        .run = &testPositionals,
        .flags = testFlags,
        .positionals = &.{.{ .name = "path", .desc = "Some path" }},
    };
    try parse(std.testing.allocator, config);
}

fn testMultiplePositionals(ctx: Context) !void {
    try std.testing.expect(std.mem.eql(u8, ctx.flagStr("src"), "from"));
    try std.testing.expect(std.mem.eql(u8, ctx.flagStr("dst"), "to"));
}

test "parses multiple positionals in order" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "from", "to" },
        .run = &testMultiplePositionals,
        .flags = testFlags,
        .positionals = &.{
            .{ .name = "src", .desc = "Source" },
            .{ .name = "dst", .desc = "Destination" },
        },
    };
    try parse(std.testing.allocator, config);
}

fn testCommandRan(ctx: Context) !void {
    try std.testing.expect(ctx.flagBool("amend") == true);
    try std.testing.expect(std.mem.eql(u8, ctx.flagStr("message"), "hi"));
}

fn testShouldNotRun(_: Context) !void {
    try std.testing.expect(false);
}

test "runs subcommand with its own flags" {
    const commitFlags = &[_]Flags{
        .{ .long = "--amend", .short = "-A", .desc = "Amend", .type = .Bool },
        .{ .long = "--message", .short = "-m", .desc = "Message", .type = .Str },
    };
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "commit", "--amend", "--message", "hi" },
        .run = &testShouldNotRun,
        .flags = testFlags,
        .commands = &.{
            .{ .name = "commit", .desc = "Commit", .flags = commitFlags, .run = &testCommandRan },
        },
    };
    try parse(std.testing.allocator, config);
}

fn testRootRan(ctx: Context) !void {
    try std.testing.expect(ctx.flagBool("all") == true);
}

test "falls through to root when no command matches" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "--all" },
        .run = &testRootRan,
        .flags = testFlags,
        .commands = &.{
            .{ .name = "commit", .desc = "Commit", .run = &testShouldNotRun },
        },
    };
    try parse(std.testing.allocator, config);
}

fn testPushRan(ctx: Context) !void {
    try std.testing.expect(ctx.flagBool("force") == true);
}

test "selects the right command among multiple" {
    const pushFlags = &[_]Flags{
        .{ .long = "--force", .short = "-f", .desc = "Force", .type = .Bool },
    };
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "push", "--force" },
        .run = &testShouldNotRun,
        .flags = testFlags,
        .commands = &.{
            .{ .name = "commit", .desc = "Commit", .run = &testShouldNotRun },
            .{ .name = "push", .desc = "Push", .flags = pushFlags, .run = &testPushRan },
        },
    };
    try parse(std.testing.allocator, config);
}

test "matchFlags sets bool flag and marks matched" {
    const alloc = std.testing.allocator;
    var flagMap = std.StringHashMap(Value).init(alloc);
    defer flagMap.deinit();

    const cfg = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "--all" },
        .flags = testFlags,
        .run = &testDefaults,
    };

    var i: usize = 1;
    var matched = false;
    try matchFlags(cfg, "--all", &i, &flagMap, &matched);

    try std.testing.expect(matched == true);
    try std.testing.expect(flagMap.get("all").?.Bool == true);
}

test "matchFlags parses int flag and advances i" {
    const alloc = std.testing.allocator;
    var flagMap = std.StringHashMap(Value).init(alloc);
    defer flagMap.deinit();

    const cfg = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "--depth", "7" },
        .flags = testFlags,
        .run = &testDefaults,
    };

    var i: usize = 1;
    var matched = false;
    try matchFlags(cfg, "--depth", &i, &flagMap, &matched);

    try std.testing.expect(matched == true);
    try std.testing.expect(flagMap.get("depth").?.Int == 7);
    try std.testing.expect(i == 2);
}

test "matchFlags leaves matched false for unknown arg" {
    const alloc = std.testing.allocator;
    var flagMap = std.StringHashMap(Value).init(alloc);
    defer flagMap.deinit();

    const cfg = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "--unknown" },
        .flags = testFlags,
        .run = &testDefaults,
    };

    var i: usize = 1;
    var matched = false;
    try matchFlags(cfg, "--unknown", &i, &flagMap, &matched);

    try std.testing.expect(matched == false);
    try std.testing.expect(flagMap.count() == 0);
}

test "handlePositionals stores and advances index" {
    const alloc = std.testing.allocator;
    var flagMap = std.StringHashMap(Value).init(alloc);
    defer flagMap.deinit();

    const cfg = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{"test"},
        .flags = testFlags,
        .run = &testDefaults,
        .positionals = &.{ .{ .name = "a", .desc = "" }, .{ .name = "b", .desc = "" } },
    };

    var idx: usize = 0;
    try handlePositionals(cfg, "first", &idx, &flagMap);
    try handlePositionals(cfg, "second", &idx, &flagMap);

    try std.testing.expect(std.mem.eql(u8, flagMap.get("a").?.Str, "first"));
    try std.testing.expect(std.mem.eql(u8, flagMap.get("b").?.Str, "second"));
    try std.testing.expect(idx == 2);
}

test "handlePositionals ignores overflow" {
    const alloc = std.testing.allocator;
    var flagMap = std.StringHashMap(Value).init(alloc);
    defer flagMap.deinit();

    const cfg = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{"test"},
        .flags = testFlags,
        .run = &testDefaults,
        .positionals = &.{.{ .name = "only", .desc = "" }},
    };

    var idx: usize = 0;
    try handlePositionals(cfg, "first", &idx, &flagMap);
    try handlePositionals(cfg, "ignored", &idx, &flagMap);

    try std.testing.expect(flagMap.count() == 1);
    try std.testing.expect(idx == 1);
}

test "matchCommands returns false when no commands defined" {
    const cfg = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "anything" },
        .flags = testFlags,
        .run = &testDefaults,
    };

    const matched = try matchCommands(std.testing.allocator, cfg, "anything", 1);
    try std.testing.expect(matched == false);
}

test "matchCommands returns false when arg doesn't match any command" {
    const cfg = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "unknown" },
        .flags = testFlags,
        .run = &testDefaults,
        .commands = &.{
            .{ .name = "commit", .desc = "Commit", .run = &testShouldNotRun },
        },
    };

    const matched = try matchCommands(std.testing.allocator, cfg, "unknown", 1);
    try std.testing.expect(matched == false);
}
