const std = @import("std");
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});
const Ball = @import("Ball.zig");
const AABB = @import("AABB.zig");
const Player = @import("Player.zig");
const client = @import("../client.zig");
const consts = @import("constants.zig");
const server = @import("../server.zig");

const protocol = @import("../protocol.zig");

pub const SCREEN_WIDTH = 890;
pub const SCREEN_HEIGHT = 500;

pub const GameStateSnapshot = struct {
    other_player_pos: r.Vector2,
    input: i2,
    stamp: i64,
};

pub const GameScore = struct {
    player1_score: u16 = 0,
    player2_score: u16 = 0,
};

pub const GameState = struct {
    server: bool,
    rand: ?std.Random = null,
    player: Player = .{
        .player_type = 0,
        .pos = Player.PLAYER_1_STARTING_POSITION,
    },
    other_player: Player = .{
        .player_type = 1,
        .pos = Player.PLAYER_2_STARTING_POSITION,
    },
    ball: Ball = .{
        .dir = r.Vector2Zero(),
        .pos = Ball.INITIAL_POSITION,
        .size = Ball.SIZE,
        .speed = Ball.INITIAL_SPEED,
    },
    server_info: struct {
        other_player_pos: ?r.Vector2 = null,
        ball: Ball = .{
            .dir = r.Vector2Zero(),
            .pos = Ball.INITIAL_POSITION,
            .size = Ball.SIZE,
            .speed = Ball.INITIAL_SPEED,
        },
    } = .{},
    positions_set: bool = false,
    game_score: GameScore = GameScore{},

    pub fn get_random_dir(self: *GameState) r.Vector2 {
        const x_factor: f32 = if (self.rand.?.boolean()) 1.0 else -1.0;
        const y_factor: f32 = if (self.rand.?.boolean()) 1.0 else -1.0;
        return r.Vector2Normalize(
            r.Vector2{
                .x = (self.rand.?.float(f32) * 0.6 + 0.2) * x_factor,
                .y = (self.rand.?.float(f32) * 0.6 + 0.2) * y_factor,
            },
        );
    }

    pub fn score_goal(self: *GameState, player_type: u1) void {
        std.debug.print("score!\n", .{});

        if (player_type == 0) {
            self.game_score.player1_score += 1;
        } else {
            self.game_score.player2_score += 1;
        }

        self.ball.pos = Ball.INITIAL_POSITION;
        if (self.server) {
            self.ball.dir = self.get_random_dir();
        } else {
            self.ball.dir = r.Vector2Zero();
        }
        self.ball.speed = Ball.INITIAL_SPEED;

        self.player.set_starting_position();
        self.other_player.set_starting_position();
    }

    pub fn run_game(
        self: *GameState,
        game_state_buffer_ptr: *GameStateSnapshot,
        server_message_queue_ptr: *client.ServerMessageQueue,
        game_state_queue_ptr: *client.GameStateSnapshotQueue,
        active_ptr: *bool,
    ) !void {
        var player1_score_buffer: [5]u8 = .{0} ** 5;
        var player2_score_buffer: [5]u8 = .{0} ** 5;

        r.SetTraceLogLevel(r.LOG_ERROR);
        r.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Pong");
        defer r.CloseWindow();
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

                if (!self.positions_set) {
                    if (server_message.player == 1) {
                        self.player.player_type = 1;
                        self.other_player.player_type = 0;
                        self.player.set_starting_position();
                        self.other_player.set_starting_position();
                    }
                    self.positions_set = true;
                    std.debug.print("player: {}\n", .{self.player.player_type});
                }

                // entity interpolation
                self.server_info.other_player_pos = server_message.other_player_pos;

                // reconsiliation
                if (server_message.stamp != 0) {
                    var game_state_record: GameStateSnapshot = game_state_queue_ptr.readItem().?;
                    while (game_state_record.stamp != server_message.stamp) {
                        game_state_record = game_state_queue_ptr.readItem() orelse @panic("no state left");
                    }
                }

                self.player.pos = server_message.player_pos;
                self.server_info.ball.pos = server_message.ball_pos;
                self.ball.dir = server_message.ball_dir;
                self.ball.speed = server_message.ball_speed;
                self.game_score.player1_score = server_message.player1_score;
                self.game_score.player2_score = server_message.player2_score;
                for (game_state_queue_ptr.readableSlice(0)) |*snapshot_ptr| {
                    const other_player_pos = snapshot_ptr.other_player_pos;
                    self.player.update(snapshot_ptr.input, server.TICK_DURATION_S);

                    const player_aabb = AABB.init(&self.player.pos, Player.PLAYER_WIDTH, Player.PLAYER_LENGTH);
                    const player_other_aabb = AABB.init(&other_player_pos, Player.PLAYER_WIDTH, Player.PLAYER_LENGTH);
                    self.server_info.ball.update(self, .{ &player_aabb, &player_other_aabb }, server.TICK_DURATION_S);
                }
                self.ball.dir = server_message.ball_dir;
                self.ball.speed = server_message.ball_speed;
            }

            if (active_ptr.*) {
                const player_aabb = AABB.init(&self.player.pos, Player.PLAYER_WIDTH, Player.PLAYER_LENGTH);
                const other_player_aabb = AABB.init(&self.other_player.pos, Player.PLAYER_WIDTH, Player.PLAYER_LENGTH);

                const collisions = [_]*const AABB{ &player_aabb, &other_player_aabb };

                const input: i2 = if (r.IsKeyDown(r.KEY_D)) 1 else if (r.IsKeyDown(r.KEY_A)) -1 else 0;

                self.player.update(input, r.GetFrameTime());

                if (self.server_info.other_player_pos) |other_pos| {
                    self.other_player.pos = r.Vector2MoveTowards(
                        self.other_player.pos,
                        other_pos,
                        Player.PLAYER_SPEED * r.GetFrameTime(),
                    );
                }

                self.ball.update(self, collisions, r.GetFrameTime());

                const ball_dist = r.Vector2Distance(self.ball.pos, self.server_info.ball.pos);
                if (ball_dist > 0.05) {
                    self.ball.pos = r.Vector2MoveTowards(
                        self.ball.pos,
                        self.server_info.ball.pos,
                        std.math.pow(f32, ball_dist, 1.5) * r.GetFrameTime(),
                    );
                }

                game_state_buffer_ptr.stamp = std.time.microTimestamp();
                game_state_buffer_ptr.input = input;
            }

            r.BeginDrawing();

            r.ClearBackground(r.BLACK);

            r.BeginMode2D(camera);

            r.DrawRectangle(
                @intFromFloat(self.player.pos.x),
                @intFromFloat(self.player.pos.y),
                Player.PLAYER_WIDTH,
                Player.PLAYER_LENGTH,
                r.RAYWHITE,
            );

            r.DrawRectangle(
                @intFromFloat(self.other_player.pos.x),
                @intFromFloat(self.other_player.pos.y),
                Player.PLAYER_WIDTH,
                Player.PLAYER_LENGTH,
                r.RAYWHITE,
            );

            r.DrawRectangle(
                @intFromFloat(self.ball.pos.x),
                @intFromFloat(self.ball.pos.y),
                @intFromFloat(self.ball.size),
                @intFromFloat(self.ball.size),
                r.RAYWHITE,
            );

            r.DrawRectangle(
                -2,
                -SCREEN_HEIGHT / 2,
                4,
                SCREEN_HEIGHT,
                r.RAYWHITE,
            );

            const p1_score_str = try std.fmt.bufPrint(player1_score_buffer[0..], "{}", .{self.game_score.player1_score});
            r.DrawText(@ptrCast(p1_score_str), 15, -(SCREEN_HEIGHT / 2) + 5, 40, r.RAYWHITE);

            const p2_score_str = try std.fmt.bufPrint(player2_score_buffer[0..], "{}", .{self.game_score.player2_score});
            const text_width = r.MeasureText(@ptrCast(p2_score_str), 40);
            r.DrawText(@ptrCast(p2_score_str), -15 - text_width, -(SCREEN_HEIGHT / 2) + 5, 40, r.RAYWHITE);

            r.EndMode2D();
            r.EndDrawing();
        }
    }
};
