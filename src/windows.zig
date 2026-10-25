const std = @import("std");
const windows = std.os.windows;

const LASTINPUTINFO = extern struct {
    cbSize: windows.UINT,
    dwTime: windows.DWORD,
};

extern "kernel32" fn GetTickCount() windows.DWORD;

extern "user32" fn GetLastInputInfo(plii: *LASTINPUTINFO) windows.BOOL;

pub fn timeOfLastInput() !windows.DWORD {
    var info = LASTINPUTINFO{
        .cbSize = @sizeOf(LASTINPUTINFO),
        .dwTime = undefined,
    };

    if (!GetLastInputInfo(&info).toBool()) {
        return error.Unexpected;
    }

    return info.dwTime;
}

pub const State = struct {
    // Fallible for signature parity with the linux State (`stateFac` does
    // `try .init()` on every platform).
    pub fn init() !State {
        return .{};
    }
    pub inline fn deinit(_: *State) void {}
};

pub fn timeSinceLastInput(_: *const State) !u64 {
    const lastTime = try timeOfLastInput();
    // Both are 32-bit millisecond tick counts that wrap every ~49.7 days;
    // wrapping subtraction gives the right elapsed time across a wrap.
    const elapsed_ms: windows.DWORD = GetTickCount() -% lastTime;

    return elapsed_ms / std.time.ms_per_s;
}
