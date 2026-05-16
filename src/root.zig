//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

/// This is a documentation comment to explain the `printAnotherMessage` function below.
///
/// Accepting an `Io.Writer` instance is a handy way to write reusable code.
pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

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

pub const Positionals = struct {
    name: []const u8,
    desc: []const u8,
    flags: []const Flags,
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

pub const Config = struct {
    name: []const u8,
    desc: []const u8,
    userArgs: []const []const u8,
    flags: []const Flags,
    run: *const fn (Context) anyerror!void,
    positionals: ?[]const Positionals = null,
};

pub fn parse(
    alloc: std.mem.Allocator,
    cfg: Config,
) !void {
    var flagMap = std.StringHashMap(Value).init(alloc);
    defer flagMap.deinit();

    var i: usize = 0;
    while (i < cfg.userArgs.len) : (i += 1) {
        const arg = cfg.userArgs[i];
        for (cfg.flags) |flag| {
            if (std.mem.eql(u8, flag.long, arg) or std.mem.eql(u8, flag.short, arg)) {
                if (flag.type == .Bool) {
                    try flagMap.put(flag.long[2..], Value{ .Bool = true });
                } else if (flag.type == .Int) {
                    i += 1;
                    const v = std.fmt.parseInt(usize, cfg.userArgs[i], 10) catch 0;
                    try flagMap.put(flag.long[2..], Value{ .Int = v });
                } else if (flag.type == .Str) {
                    i += 1;
                    const strArg = cfg.userArgs[i];
                    try flagMap.put(flag.long[2..], Value{ .Str = strArg });
                }
                continue;
            }
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
        .userArgs = &.{ "--all", "--depth", "4", "--name", "Zig" },
        .run = &testAssertFlags,
        .flags = testFlags,
    };
    try parse(std.testing.allocator, config);
}

test "parses short flags" {
    const config = Config{
        .name = "Test",
        .desc = "Test",
        .userArgs = &.{ "-a", "-d", "4", "-n", "Zig" },
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
        .userArgs = &.{},
        .run = &testDefaults,
        .flags = testFlags,
    };
    try parse(std.testing.allocator, config);
}
