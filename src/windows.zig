const std = @import("std");
const schema = @import("schema.zig");
const windows = std.os.windows;

const LASTINPUTINFO = extern struct {
    cbSize: windows.UINT,
    dwTime: windows.DWORD,
};

extern "kernel32" fn GetTickCount() windows.DWORD;

extern "user32" fn GetLastInputInfo(plii: *LASTINPUTINFO) windows.BOOL;

pub fn timeOfLastInput() !u64 {
    var info = LASTINPUTINFO{
        .cbSize = @sizeOf(LASTINPUTINFO),
        .dwTime = undefined,
    };

    if (GetLastInputInfo(&info) == 0) {
        return error.Unexpected;
    }

    return info.dwTime;
}

pub fn timeSinceLastInput() !u64 {
    const lastTime = try timeOfLastInput();
    const tick: u64 = GetTickCount();

    return (tick - lastTime) / std.time.ms_per_s;
}
