const std = @import("std");
const builtin = @import("builtin");

pub const schema = @import("schema.zig");
pub const config = @import("config.zig");

const platform = switch (builtin.target.os.tag) {
    .windows => @import("windows.zig"),
    .linux => @import("linux.zig"),
    else => struct {
        pub const State = struct {};

        pub fn timeSinceLastInput() !u64 {
            return error.Unimplemented;
        }
    },
};

pub const State = platform.State;

pub fn timeSinceLastInput(ctx: *State) !u64 {
    return platform.timeSinceLastInput(ctx);
}
