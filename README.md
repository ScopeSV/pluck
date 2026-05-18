# pluck

A dead-simple declarative CLI library for Zig.

## Usage

Define your CLI as a single config struct. The library handles parsing, help generation, version output, subcommands, positionals, and typed flag values.

```zig
const std = @import("std");
const pluck = @import("pluck");

fn run(ctx: pluck.Context) !void {
    const path = if (ctx.argStr("path").len > 0) ctx.argStr("path") else ".";
    const depth = ctx.argInt("depth");
    const noColor = ctx.argBool("no-color");

    std.debug.print("path={s}, depth={d}, no-color={}\n", .{ path, depth, noColor });
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);

    const config = pluck.Config{
        .name = "myapp",
        .desc = "An example CLI",
        .version = "0.1.0",
        .userArgs = args,
        .flags = &.{
            .{ .long = "--depth", .short = "-d", .desc = "Max depth", .type = .Int },
            .{ .long = "--no-color", .short = "", .desc = "Disable colors", .type = .Bool },
        },
        .positionals = &.{
            .{ .name = "path", .desc = "Path to operate on" },
        },
        .run = &run,
    };

    try pluck.run(alloc, init.io, config);
}
```

## Features

- Declarative config - no builder methods, no chained calls
- Typed flag values: `Bool`, `Int`, `Str`
- Positional arguments
- Subcommands with their own flags
- Auto-generated `--help` / `-h`
- Auto-generated `--version` / `-v`
- Clean error returns for missing values, invalid values, and unknown args

## Accessing parsed values

Inside your `run` function, pull values from the context:

```zig
ctx.argBool("flag-name")
ctx.argInt("flag-name")
ctx.argStr("flag-name")
```

Positionals are accessed the same way as flags - by the name you gave them in the config.

## Subcommands

```zig
.commands = &.{
    .{
        .name = "commit",
        .desc = "Commit changes",
        .flags = &.{
            .{ .long = "--message", .short = "-m", .desc = "Message", .type = .Str },
        },
        .run = &commitFn,
    },
},
```

When the user runs `myapp commit --message "hello"`, pluck dispatches to `commitFn` with the commit's flags parsed.

## Errors

`pluck.run` returns a `RunError` for parsing issues:

- `error.MissingValue` - a flag was given without its required value
- `error.InvalidValue` - a flag's value could not be parsed (e.g. non-numeric for an `Int` flag)
- `error.UnknownArg` - an unrecognized argument was passed

User callbacks can return any error - they propagate through.

```zig
pluck.run(alloc, io, config) catch |err| switch (err) {
    error.MissingValue => std.debug.print("Missing value for flag\n", .{}),
    error.UnknownArg => std.debug.print("Unknown argument\n", .{}),
    error.InvalidValue => std.debug.print("Invalid value for flag\n", .{}),
    else => return err,
};
```

## Installation

Add pluck to your `build.zig.zon`:

```zig
.dependencies = .{
    .pluck = .{
        .url = "https://codeberg.org/ScopeSV/pluck/archive/v0.1.0.tar.gz",
        .hash = "...",
    },
},
```

Then in `build.zig`:

```zig
const pluck = b.dependency("pluck", .{});
exe.root_module.addImport("pluck", pluck.module("pluck"));
```

## License

MIT
