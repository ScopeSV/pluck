const std = @import("std");
const Io = std.Io;

const cli = @import("cli");

fn testFn(ctx: cli.Context) !void {
    const all = ctx.flagBool("all");
    std.debug.print("Flag --all is set: {}\n", .{all});
    const path = ctx.flagStr("path");
    std.debug.print("Positional path: {s}\n", .{path});
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
        .positionals = &.{
            .{ .name = "path", .desc = "Some path" },
        },
    };

    _ = try cli.parse(arena, config);
}
