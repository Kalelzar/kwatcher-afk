const std = @import("std");
const kwatcher = @import("kwatcher");
const builtin = @import("builtin");

pub const schema = @import("schema.zig");
pub const config = @import("config.zig");

const platform = switch (builtin.target.os.tag) {
    .windows => @import("windows.zig"),
    else => struct {
        pub fn timeSinceLastInput() !u64 {
            return error.Unimplemented;
        }
    },
};

pub fn timeSinceLastInput() !u64 {
    return platform.timeSinceLastInput();
}
