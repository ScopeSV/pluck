const std = @import("std");
const Io = std.Io;

const cli = @import("cli");

fn testFn(ctx: cli.Context) !void {
    const all = ctx.argBool("all");
    std.debug.print("Flag --all is set: {}\n", .{all});
    const path = ctx.argStr("path");
    std.debug.print("Positional path: {s}\n", .{path});
}

fn testSubCmd(ctx: cli.Context) !void {
    const verbose = ctx.argBool("verbose");
    std.debug.print("Subcommand verbose flag: {}\n", .{verbose});
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
        .commands = &.{
            .{
                .name = "sub",
                .desc = "A subcommand",
                .run = &testSubCmd,
                .flags = &.{
                    .{
                        .long = "--verbose",
                        .short = "-v",
                        .desc = "Verbose output",
                        .type = .Bool,
                    },
                },
            },
        },
    };

    _ = try cli.run(arena, init.io, config);
}
