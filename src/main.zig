const std = @import("std");
const Io = std.Io;

const cli = @import("cli");

// const args = try cli.parse(allocator, &.{
//      .flag("--all", "-a", "Show hidden files", bool, false),
//      .flag("--depth", "-d", "Max depth", usize, 1000),
//      .flag("--size", "-s", "Show file sizes", bool, false),
//      .positional("path", "Directory to list", "."),
//  });
//
//  // Then just use:
//  args.get("all")    // bool
//  args.get("depth")  // usize
//  args.get("path")   // []const u8
fn testFn(ctx: cli.Context) void {
    const all = ctx.flagBool("all");
    std.debug.print("Flag --all is set: {}\n", .{all});
}

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const argsInp = try init.minimal.args.toSlice(arena);

    const config = cli.Config{
        .name = "Zig CLI",
        .desc = "A simple CLI example in Zig",
        .userArgs = argsInp,
        .run = &testFn,
        .flags = &.{
            .{
                .long = "--all",
                .short = "-a",
                .desc = "Show hidden files",
                .type = .Bool,
            },
            .{
                .long = "--depth",
                .short = "-d",
                .desc = "Max depth",
                .type = .Int,
            },
        },
    };

    _ = try cli.parse(arena, config);
}
