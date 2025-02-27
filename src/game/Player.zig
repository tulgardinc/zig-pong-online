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
player_type: u1,

const Self = @This();

pub fn update(self: *Self, input: i2, frame_time: f32) void {
    const mutliplier: f32 = if (self.player_type == 1) 1.0 else 1.0;
    const input_modified: f32 = @as(f32, @floatFromInt(input)) * mutliplier;
    self.pos.y += input_modified * PLAYER_SPEED * frame_time;

    self.pos.y = std.math.clamp(
        self.pos.y,
        -game.SCREEN_HEIGHT / 2,
        game.SCREEN_HEIGHT / 2 - PLAYER_LENGTH,
    );
}
