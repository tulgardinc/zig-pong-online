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

pub const PLAYER_1_STARTING_POSITION = r.Vector2{
    .x = game.SCREEN_WIDTH / 2 - PLAYER_WIDTH,
    .y = -PLAYER_LENGTH / 2,
};

pub const PLAYER_2_STARTING_POSITION = r.Vector2{
    .x = -game.SCREEN_WIDTH / 2,
    .y = -PLAYER_LENGTH / 2,
};

pos: r.Vector2,
player_type: u1,

const Self = @This();

pub fn update(self: *Self, input: i2, frame_time: f32) void {
    const mutliplier: f32 = if (self.player_type == 0) -1.0 else 1.0;
    const input_modified: f32 = @as(f32, @floatFromInt(input)) * mutliplier;
    self.pos.y += input_modified * PLAYER_SPEED * frame_time;

    self.pos.y = std.math.clamp(
        self.pos.y,
        -game.SCREEN_HEIGHT / 2,
        game.SCREEN_HEIGHT / 2 - PLAYER_LENGTH,
    );
}

pub fn set_starting_position(self: *Self) void {
    if (self.player_type == 0) {
        self.pos = PLAYER_1_STARTING_POSITION;
    } else {
        self.pos = PLAYER_2_STARTING_POSITION;
    }
}
