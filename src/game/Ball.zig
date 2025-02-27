const std = @import("std");
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});
const game = @import("game.zig");
const AABB = @import("AABB.zig");
const consts = @import("constants.zig");

pub const INITIAL_SPEED = 360;
pub const SIZE = 35;
pub const INITIAL_POSITION = r.Vector2{ .x = -SIZE / 2, .y = -SIZE / 2 };

pos: r.Vector2,
dir: r.Vector2,
size: f32,
speed: f32,

const Self = @This();

pub fn update(
    self: *Self,
    game_state: *game.GameState,
    player_aabb_ptrs: [2]*const AABB,
    frame_time: f32,
) void {
    self.move(frame_time);
    self.handleCollision(player_aabb_ptrs, game_state);
}

fn move(self: *Self, frame_time: f32) void {
    const vel = r.Vector2Scale(
        self.dir,
        self.speed * frame_time,
    );
    self.pos = r.Vector2Add(self.pos, vel);
}

fn handleCollision(self: *Self, player_aabb_ptrs: [2]*const AABB, game_state: *game.GameState) void {
    const ball_aabb = AABB.init(&self.pos, self.size, self.size);

    var correction = r.Vector2Zero();

    if (ball_aabb.right > game.SCREEN_WIDTH / 2) {
        game_state.score_goal(1);
    } else if (ball_aabb.left < -game.SCREEN_WIDTH / 2) {
        game_state.score_goal(0);
    } else if (ball_aabb.bottom > game.SCREEN_HEIGHT / 2) {
        self.dir = r.Vector2Reflect(self.dir, consts.VEC_DOWN);
        correction = r.Vector2Scale(consts.VEC_UP, ball_aabb.bottom - game.SCREEN_HEIGHT / 2);
    } else if (ball_aabb.top < -game.SCREEN_HEIGHT / 2) {
        self.dir = r.Vector2Reflect(self.dir, consts.VEC_UP);
        correction = r.Vector2Scale(consts.VEC_DOWN, ball_aabb.top * -1 - game.SCREEN_HEIGHT / 2);
    }

    self.pos = r.Vector2Add(self.pos, correction);

    for (player_aabb_ptrs) |player_aabb_ptr| {
        if (ball_aabb.get_collision_vector(player_aabb_ptr)) |vec| {
            const normal = r.Vector2Normalize(vec);
            self.dir = r.Vector2Reflect(self.dir, normal);
            self.pos = r.Vector2Add(self.pos, vec);
            self.speed = self.speed * 1.1;
        }
    }
}
