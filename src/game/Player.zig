const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});
const std = @import("std");
const game = @import("game.zig");
const protocol = @import("../protocol.zig");
const client = @import("../client.zig");

pub const PLAYER_SPEED = 300;

pub const PLAYER_WIDTH = 25;
pub const PLAYER_LENGTH = 120;

pos: r.Vector2,
vel: r.Vector2,

const Self = @This();

pub fn update(self: *Self, snapshot_ptr: *game.GameStateSnapshot) void {
    if (r.IsKeyDown(r.KEY_A)) {
        self.pos.y += PLAYER_SPEED * r.GetFrameTime();
        snapshot_ptr.input = -1;
    } else if (r.IsKeyDown(r.KEY_D)) {
        self.pos.y -= PLAYER_SPEED * r.GetFrameTime();
        snapshot_ptr.input = 1;
    } else {
        snapshot_ptr.input = 0;
    }

    self.pos.y = std.math.clamp(
        self.pos.y,
        -game.SCREEN_HEIGHT / 2,
        game.SCREEN_HEIGHT / 2 - PLAYER_LENGTH,
    );
}
