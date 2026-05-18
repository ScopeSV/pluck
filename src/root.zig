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

pub const RunError = error{
    MissingValue,
    UnknownArg,
};

pub const Flag = struct {
    long: []const u8,
    short: []const u8,
    desc: []const u8,
    type: FlagType,
};

pub const Context = struct {
    alloc: std.mem.Allocator,
    io: Io,
    msg: []const u8 = "Hello from the CLI parser!",
    userArgs: []const []const u8,
    flags: std.StringHashMap(Value),

    pub fn argBool(self: Context, f: []const u8) bool {
        const val = self.flags.get(f) orelse return false;
        return val.Bool;
    }
    pub fn argInt(self: Context, f: []const u8) usize {
        const val = self.flags.get(f) orelse return 0;
        return val.Int;
    }
    pub fn argStr(self: Context, f: []const u8) []const u8 {
        const val = self.flags.get(f) orelse return "";
        return val.Str;
    }
};

pub const Command = struct {
    name: []const u8,
    desc: []const u8,
    flags: []const Flag = &.{},
    run: *const fn (Context) anyerror!void,
};

pub const Positional = struct {
    name: []const u8,
    desc: []const u8,
};

pub const Config = struct {
    name: []const u8,
    desc: []const u8,
    version: []const u8 = "",
    userArgs: []const []const u8,
    flags: []const Flag,
    run: *const fn (Context) anyerror!void,
    positionals: ?[]const Positional = null,
    commands: ?[]const Command = null,
};

fn matchCommands(alloc: std.mem.Allocator, io: Io, cfg: Config, arg: []const u8, i: usize) anyerror!bool {
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
            try run(alloc, io, subConfig);
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
                if (i.* >= cfg.userArgs.len) {
                    return RunError.MissingValue;
                }

                const v = std.fmt.parseInt(usize, cfg.userArgs[i.*], 10) catch 0;
                try flagMap.put(flag.long[2..], Value{ .Int = v });
                matched.* = true;
            } else if (flag.type == .Str) {
                i.* += 1;
                if (i.* >= cfg.userArgs.len) {
                    return RunError.MissingValue;
                }
                const strArg = cfg.userArgs[i.*];
                try flagMap.put(flag.long[2..], Value{ .Str = strArg });
                matched.* = true;
            }
        }
    }
}

fn matchPositional(cfg: Config, arg: []const u8, positionalEdx: *usize, flagMap: *std.StringHashMap(Value)) !bool {
    if (cfg.positionals) |positionals| {
        if (positionalEdx.* < positionals.len) {
            try flagMap.put(positionals[positionalEdx.*].name, Value{ .Str = arg });
            positionalEdx.* += 1;
            return true;
        }
    }
    return false;
}

fn printHelp(cfg: Config) void {
    if (cfg.desc.len > 0) {
        std.debug.print("{s} - {s}\n", .{ cfg.name, cfg.desc });
    } else {
        std.debug.print("{s}\n", .{cfg.name});
    }
    if (cfg.version.len > 0) {
        std.debug.print("Version: {s}\n\n", .{cfg.version});
    } else {
        std.debug.print("\n", .{});
    }

    std.debug.print("Usage:\n", .{});
    std.debug.print("  {s} [flags] [positionals] [command]\n\n", .{cfg.name});

    for (cfg.flags) |flag| {
        if (flag.short.len > 0) {
            std.debug.print("  {s}, {s}: {s}\n", .{ flag.short, flag.long, flag.desc });
        } else {
            std.debug.print("  {s}: {s}\n", .{ flag.long, flag.desc });
        }
    }

    if (cfg.positionals) |positionals| {
        std.debug.print("Positionals:\n", .{});
        for (positionals) |pos| {
            std.debug.print("  {s}: {s}\n", .{ pos.name, pos.desc });
        }
        std.debug.print("\n", .{});
    }

    if (cfg.commands) |commands| {
        std.debug.print("Commands:\n", .{});
        for (commands) |cmd| {
            std.debug.print("  {s}: {s}\n", .{ cmd.name, cmd.desc });
        }
        std.debug.print("\n", .{});
    }
}

fn matchStandardArgs(cfg: Config) bool {
    for (cfg.userArgs) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp(cfg);
            return true;
        }
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            if (cfg.version.len > 0) {
                std.debug.print("{s}\n", .{cfg.version});
            }
            return true;
        }
    }
    return false;
}

pub fn run(
    alloc: std.mem.Allocator,
    io: Io,
    cfg: Config,
) anyerror!void {
    var flagMap = std.StringHashMap(Value).init(alloc);
    defer flagMap.deinit();

    if (matchStandardArgs(cfg)) return;

    var i: usize = 1;
    var positionalEdx: usize = 0;
    while (i < cfg.userArgs.len) : (i += 1) {
        const arg = cfg.userArgs[i];

        if (try matchCommands(alloc, io, cfg, arg, i)) return;

        var matched = false;
        try matchFlags(cfg, arg, &i, &flagMap, &matched);

        if (!matched) {
            const positionalMatch = try matchPositional(cfg, arg, &positionalEdx, &flagMap);
            if (!positionalMatch) {
                return RunError.UnknownArg;
            }
        }
    }

    try cfg.run(Context{
        .msg = "Running the CLI parser!",
        .alloc = alloc,
        .io = io,
        .userArgs = cfg.userArgs,
        .flags = flagMap,
    });
}

const testFlags = &[_]Flag{
    .{ .long = "--all", .short = "-a", .desc = "Show hidden files", .type = .Bool },
    .{ .long = "--depth", .short = "-d", .desc = "Max depth", .type = .Int },
    .{ .long = "--name", .short = "-n", .desc = "Name", .type = .Str },
};

fn testAssertFlags(ctx: Context) !void {
    try std.testing.expect(ctx.argBool("all") == true);
    try std.testing.expect(ctx.argInt("depth") == 4);
    try std.testing.expect(std.mem.eql(u8, ctx.argStr("name"), "Zig"));
}

test "parses long flags" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "--all", "--depth", "4", "--name", "Zig" },
        .run = &testAssertFlags,
        .flags = testFlags,
    };
    try run(std.testing.allocator, undefined, config);
}

test "parses short flags" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "-a", "-d", "4", "-n", "Zig" },
        .run = &testAssertFlags,
        .flags = testFlags,
    };
    try run(std.testing.allocator, undefined, config);
}

fn testDefaults(ctx: Context) !void {
    try std.testing.expect(ctx.argBool("all") == false);
    try std.testing.expect(ctx.argInt("depth") == 0);
    try std.testing.expect(std.mem.eql(u8, ctx.argStr("name"), ""));
}

test "unset flags return defaults" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{"test"},
        .run = &testDefaults,
        .flags = testFlags,
    };
    try run(std.testing.allocator, undefined, config);
}

fn testPositionals(ctx: Context) !void {
    try std.testing.expect(std.mem.eql(u8, ctx.argStr("path"), "/some/path"));
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
    try run(std.testing.allocator, undefined, config);
}

fn testMultiplePositionals(ctx: Context) !void {
    try std.testing.expect(std.mem.eql(u8, ctx.argStr("src"), "from"));
    try std.testing.expect(std.mem.eql(u8, ctx.argStr("dst"), "to"));
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
    try run(std.testing.allocator, undefined, config);
}

fn testCommandRan(ctx: Context) !void {
    try std.testing.expect(ctx.argBool("amend") == true);
    try std.testing.expect(std.mem.eql(u8, ctx.argStr("message"), "hi"));
}

fn testShouldNotRun(_: Context) !void {
    try std.testing.expect(false);
}

test "missing int value errors cleanly" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "--depth" },
        .run = &testDefaults,
        .flags = testFlags,
    };
    try std.testing.expectError(
        error.MissingValue,
        run(std.testing.allocator, undefined, config),
    );
}

test "unknown arg with no positionals" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "test", "--blerp" },
        .run = &testShouldNotRun,
        .flags = testFlags,
    };
    try std.testing.expectError(error.UnknownArg, run(std.testing.allocator, undefined, config));
}

test "runs subcommand with its own flags" {
    const commitFlags = &[_]Flag{
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
    try run(std.testing.allocator, undefined, config);
}

fn testRootRan(ctx: Context) !void {
    try std.testing.expect(ctx.argBool("all") == true);
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
    try run(std.testing.allocator, undefined, config);
}

fn testPushRan(ctx: Context) !void {
    try std.testing.expect(ctx.argBool("force") == true);
}

test "selects the right command among multiple" {
    const pushFlags = &[_]Flag{
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
    try run(std.testing.allocator, undefined, config);
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
    _ = try matchPositional(cfg, "first", &idx, &flagMap);
    _ = try matchPositional(cfg, "second", &idx, &flagMap);

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
    _ = try matchPositional(cfg, "first", &idx, &flagMap);
    _ = try matchPositional(cfg, "ignored", &idx, &flagMap);

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

    const matched = try matchCommands(std.testing.allocator, undefined, cfg, "anything", 1);
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

    const matched = try matchCommands(std.testing.allocator, undefined, cfg, "unknown", 1);
    try std.testing.expect(matched == false);
}
