const std = @import("std");

const xcb_connection_t = extern struct {};
const xcb_setup_t = extern struct {};
const xcb_window_t = extern struct {};
const xcb_generic_error_t = extern struct {};
const xcb_screen_t = extern struct {
    root: u32,
};
const xcb_screen_iterator_t = extern struct {
    data: *xcb_screen_t,
    rem: i32,
    index: i32,
};

const xcb_screensaver_query_info_cookie_t = extern struct {
    sequence: u32,
};

const xcb_drawable_t = u32;

const xcb_screensaver_query_info_reply_t = extern struct {
    response_type: u8,
    state: u8,
    sequence: u16,
    length: u32,
    saver_window: u8,
    ms_until_server: u32,
    ms_since_user_input: u32,
    event_mask: u32,
    kind: u8,
    pad0: [7]u8,
};

extern fn xcb_connect(displayname: ?[*:0]const u8, screenp: ?*i32) *xcb_connection_t;
extern fn xcb_disconnect(c: *xcb_connection_t) void;
extern fn xcb_connection_has_error(c: *xcb_connection_t) c_int;
extern fn xcb_get_setup(c: *xcb_connection_t) *xcb_setup_t;
extern fn xcb_setup_roots_iterator(R: *xcb_setup_t) xcb_screen_iterator_t;

extern fn xcb_screensaver_query_info(c: *xcb_connection_t, drawable: xcb_drawable_t) xcb_screensaver_query_info_cookie_t;
extern fn xcb_screensaver_query_info_reply(c: *xcb_connection_t, cookie: xcb_screensaver_query_info_cookie_t, e: ?**xcb_generic_error_t) ?*xcb_screensaver_query_info_reply_t;

pub const State = struct {
    connection: *xcb_connection_t,
    screen: *xcb_screen_t,

    pub fn init() !State {
        return connect();
    }

    fn connect() !State {
        const conn = xcb_connect(null, null);
        // xcb_connect never returns null; a failed connection is reported here.
        if (xcb_connection_has_error(conn) != 0) {
            xcb_disconnect(conn);
            return error.XcbConnectionFailed;
        }
        const scr = xcb_setup_roots_iterator(xcb_get_setup(conn)).data;
        return .{
            .connection = conn,
            .screen = scr,
        };
    }

    /// Re-establish a lost connection (X server restart/logout) in place. Dials
    /// the new connection first so a failure leaves the old handle untouched
    /// rather than dangling.
    pub fn reconnect(state: *State) !void {
        const fresh = try connect();
        xcb_disconnect(state.connection);
        state.* = fresh;
    }

    pub fn deinit(state: *State) void {
        xcb_disconnect(state.connection);
    }
};

pub fn timeSinceLastInput(state: *State) !u64 {
    // Recover from a dead X connection instead of dereferencing it and crashing.
    if (xcb_connection_has_error(state.connection) != 0) {
        try state.reconnect();
    }

    const cookie = xcb_screensaver_query_info(state.connection, state.screen.root);
    const info = xcb_screensaver_query_info_reply(state.connection, cookie, null) orelse
        return error.XcbQueryFailed;
    defer std.c.free(info);
    const time = info.ms_since_user_input;
    return time / std.time.ms_per_s;
}
