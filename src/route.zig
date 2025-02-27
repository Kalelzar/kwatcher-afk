const std = @import("std");
const kwatcher = @import("kwatcher");
const afk = @import("kwatcher-afk");

pub fn @"publish:disabled amq.direct/heartbeat"(
    user_info: kwatcher.schema.UserInfo,
    client_info: kwatcher.schema.ClientInfo,
    status: afk.schema.AfkStatus,
) kwatcher.schema.Heartbeat.V1(afk.schema.AfkHeartbeatProperties) {
    std.log.info("GOT: {}", .{status});
    return .{
        .timestamp = std.time.timestamp(),
        .event = "afk-status",
        .user = user_info.v1(),
        .client = client_info.v1(),
        .properties = .{
            .status = status,
        },
    };
}

pub fn @"publish:afkStatusChange amq.direct/afk-status"(
    user_info: kwatcher.schema.UserInfo,
    client_info: kwatcher.schema.ClientInfo,
    status: afk.schema.StatusDiff,
) kwatcher.schema.Heartbeat.V1(afk.schema.AfkStatusChangeProperties) {
    return .{
        .timestamp = std.time.timestamp(),
        .event = "afk-status-change",
        .user = user_info.v1(),
        .client = client_info.v1(),
        .properties = .{
            .diff = status,
        },
    };
}
