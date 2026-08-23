//! Handwritten companion to the zettel-generated afk schemas (see
//! `schema/afk.ztl`): re-exports the generated surface under the historical
//! names, plus the cache-only model that is not a wire schema.
const gen = @import("afk-schema").kwatcher.afk;

/// Whether the user is active at the machine.
pub const AfkStatus = gen.AfkStatus;

/// A status transition.
pub const StatusDiff = gen.StatusDiff;

/// The afk heartbeat properties (wire name "afk").
pub const AfkHeartbeatProperties = gen.Afk.V1;

/// The afk status-change heartbeat properties (wire name "afk.status-change").
pub const AfkStatusChangeProperties = gen.Afk.StatusChange.V1;

/// A cached afk status observation (native-only; never serialized).
pub const AfkStatusEntry = struct {
    status: AfkStatus,
    timestamp: i64,
};
