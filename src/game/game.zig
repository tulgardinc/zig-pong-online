const std = @import("std");
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});
const Ball = @import("Ball.zig");
const AABB = @import("AABB.zig");
const Player = @import("Player.zig");
const OtherPlayer = @import("OtherPlayer.zig");
const client = @import("../client.zig");
const consts = @import("constants.zig");
const server = @import("../server.zig");

const protocol = @import("../protocol.zig");

pub const SCREEN_WIDTH = 890;
pub const SCREEN_HEIGHT = 500;

pub const PLAYER_1_STARTING_POSITION = r.Vector2{
    .x = SCREEN_WIDTH / 2 - Player.PLAYER_WIDTH,
    .y = -Player.PLAYER_LENGTH / 2,
};

pub const PLAYER_2_STARTING_POSITION = r.Vector2{
    .x = -SCREEN_WIDTH / 2,
    .y = -Player.PLAYER_LENGTH / 2,
};

pub const initial_ball = Ball{
    .dir = .{ .x = -0.5, .y = -0.5 },
    .pos = .{ .x = 0, .y = 0 },
    .size = 35,
    .speed = Ball.BALL_SPEED,
};

pub const GameStateSnapshot = struct {
    player_pos: r.Vector2,
    ball_dir: r.Vector2,
    ball_pos: r.Vector2,
    input: i2,
    stamp: i64,
};

var server_other_player_position: ?r.Vector2 = null;
var server_ball_position = initial_ball.pos;

var interpolation_start_time_mcs: i64 = 0;

var positions_set = false;

pub fn run_game(
    game_state_buffer_ptr: *GameStateSnapshot,
    server_message_queue_ptr: *client.ServerMessageQueue,
    game_state_queue_ptr: *client.GameStateQueue,
    active_ptr: *bool,
) !void {
    r.SetTraceLogLevel(r.LOG_ERROR);
    r.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Pong");
    defer r.CloseWindow();

    var player = Player{
        .pos = PLAYER_1_STARTING_POSITION,
        .vel = r.Vector2Zero(),
    };

    var other_player = OtherPlayer{
        .pos = PLAYER_2_STARTING_POSITION,
        .input = 0,
        .id = 0,
    };

    var ball = initial_ball;

    const camera = r.Camera2D{
        .offset = .{
            .x = @divFloor(SCREEN_WIDTH, 2),
            .y = @divFloor(SCREEN_HEIGHT, 2),
        },
        .rotation = 0,
        .target = .{ .x = 0, .y = 0 },
        .zoom = 1.0,
    };

    r.SetTargetFPS(166);

    while (!r.WindowShouldClose()) {
        if (server_message_queue_ptr.readableLength() > 0 and game_state_queue_ptr.readableLength() > 0) {

            // handle positioning and correction
            const server_message = server_message_queue_ptr.readItem().?;

            if (!positions_set) {
                if (server_message.player == 1) {
                    player.pos = PLAYER_2_STARTING_POSITION;
                    other_player.pos = PLAYER_1_STARTING_POSITION;
                }
                positions_set = true;
            }

            // entity interpolation
            server_other_player_position = server_message.other_player_pos;
            interpolation_start_time_mcs = std.time.microTimestamp();

            // reconsiliation
            if (server_message.stamp != 0) {
                var game_state_record: GameStateSnapshot = game_state_queue_ptr.readItem().?;
                while (game_state_record.stamp != server_message.stamp) {
                    game_state_record = game_state_queue_ptr.readItem() orelse @panic("no state left");
                }
            }

            player.pos = server_message.player_pos;
            server_ball_position = server_message.ball_pos;
            for (game_state_queue_ptr.readableSlice(0)) |*snapshot_ptr| {
                const input_float: f32 = @floatFromInt(snapshot_ptr.input);
                const player_vel = r.Vector2Scale(consts.VEC_UP, input_float * (server.TICK_DURATION_S));
                player.pos = r.Vector2Add(player.pos, player_vel);
                const ball_vel = r.Vector2Scale(snapshot_ptr.ball_dir, Ball.BALL_SPEED * server.TICK_DURATION_S);
                server_ball_position = r.Vector2Add(server_ball_position, ball_vel);
            }
        }

        if (active_ptr.*) {
            const player_aabb = AABB.init(&player.pos, Player.PLAYER_WIDTH, Player.PLAYER_LENGTH);
            const other_player_aabb = AABB.init(&other_player.pos, Player.PLAYER_WIDTH, Player.PLAYER_LENGTH);

            const collisions = [_]*const AABB{ &player_aabb, &other_player_aabb };

            player.update(game_state_buffer_ptr);

            if (server_other_player_position) |other_pos| {
                other_player.pos = r.Vector2MoveTowards(
                    other_player.pos,
                    other_pos,
                    Player.PLAYER_SPEED * r.GetFrameTime(),
                );
            }

            ball.update(collisions, r.GetFrameTime());

            const ball_dist = r.Vector2Distance(ball.pos, server_ball_position);
            if (ball_dist > 0.05) {
                ball.pos = r.Vector2MoveTowards(
                    ball.pos,
                    server_ball_position,
                    std.math.pow(f32, ball_dist, 2) * r.GetFrameTime(),
                );
            }

            game_state_buffer_ptr.stamp = std.time.microTimestamp();
            game_state_buffer_ptr.ball_pos = ball.pos;
            game_state_buffer_ptr.ball_dir = ball.dir;
            game_state_buffer_ptr.player_pos = player.pos;
        }

        r.BeginDrawing();

        r.ClearBackground(r.BLACK);

        r.BeginMode2D(camera);

        r.DrawRectangle(
            @intFromFloat(player.pos.x),
            @intFromFloat(player.pos.y),
            Player.PLAYER_WIDTH,
            Player.PLAYER_LENGTH,
            r.RAYWHITE,
        );

        r.DrawRectangle(
            @intFromFloat(other_player.pos.x),
            @intFromFloat(other_player.pos.y),
            Player.PLAYER_WIDTH,
            Player.PLAYER_LENGTH,
            r.RAYWHITE,
        );

        r.DrawRectangle(
            @intFromFloat(ball.pos.x),
            @intFromFloat(ball.pos.y),
            @intFromFloat(ball.size),
            @intFromFloat(ball.size),
            r.RAYWHITE,
        );

        r.EndMode2D();
        r.EndDrawing();
    }
}
