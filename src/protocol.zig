const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

pub const ClientMessage = struct {
    stamp: i64,
    input: i2,
};

pub const ServerMessage = struct {
    stamp: i64,
    player_pos: r.Vector2 = r.Vector2Zero(),
    other_player_pos: r.Vector2 = r.Vector2Zero(),
    ball_pos: r.Vector2 = r.Vector2Zero(),
    ball_dir: r.Vector2 = r.Vector2Zero(),
    response: u1,
};
