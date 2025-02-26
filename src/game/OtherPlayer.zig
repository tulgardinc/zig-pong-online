const std = @import("std");
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});
const consts = @import("constants.zig");
const Player = @import("Player.zig");
const game = @import("game.zig");

id: ?u32 = null,
pos: r.Vector2 = r.Vector2Zero(),
input: i2,

const Self = @This();

pub fn update(self: *Self, frame_speed: f32) void {
    const dir = r.Vector2Scale(consts.VEC_UP, @floatFromInt(self.input));
    self.pos = r.Vector2Add(self.pos, r.Vector2Scale(dir, Player.PLAYER_SPEED * frame_speed));

    self.pos.y = std.math.clamp(
        self.pos.y,
        -game.SCREEN_HEIGHT / 2,
        game.SCREEN_HEIGHT / 2 - Player.PLAYER_LENGTH,
    );
}
