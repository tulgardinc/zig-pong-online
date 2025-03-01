const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});
const serializer = @import("zig-serializer");

pub const Serializer = serializer.GenSerializer(&.{ ClientMessage, ServerMessage });

pub const CLIENT_MESSAGE_SIZE = serializer.get_serialization_array_size(ClientMessage);
pub const ClientMessage = struct {
    stamp: i64,
    input: i2,
};

pub const SERVER_MESSAGE_SIZE = serializer.get_serialization_array_size(ServerMessage);
pub const ServerMessage = struct {
    stamp: i64 = 0,
    player_pos: r.Vector2 = r.Vector2Zero(),
    other_player_pos: r.Vector2 = r.Vector2Zero(),
    ball_pos: r.Vector2 = r.Vector2Zero(),
    ball_dir: r.Vector2 = r.Vector2Zero(),
    ball_speed: f32 = 0,
    player: u1 = 0,
    player1_score: u16 = 0,
    player2_score: u16 = 0,
    started: u1 = 0,
};
