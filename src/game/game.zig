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
const Button = @import("Button.zig");
const Input = @import("Input.zig");

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

fn join_pressed(state_ptr: *GameState) void {
    std.debug.print("ip: {s}, port: {s}\n", .{ state_ptr.ip_input_host, state_ptr.port_input_host });
    _ = std.Thread.spawn(.{}, client.run_network, .{ &state_ptr.ip_input_host, &state_ptr.port_input_host, state_ptr }) catch @panic("couldn't start thread");
}

fn host_pressed(state_ptr: *GameState) void {
    std.debug.print("button pressed\n", .{});
    var path_buffer: [256]u8 = undefined;
    const path = std.fs.selfExeDirPath(&path_buffer) catch @panic("couldn't find exe dir");
    const exe_name = "pongserver.exe";
    @memcpy(path_buffer[path.len .. path.len + exe_name.len + 1], "/" ++ exe_name);
    state_ptr.server_process = std.process.Child.init(&.{ path_buffer[0 .. path.len + exe_name.len + 1], &state_ptr.port_input_join }, state_ptr.alloc.?);
    state_ptr.server_process.?.spawn() catch @panic("failed to spawn server");
    _ = std.Thread.spawn(.{}, client.run_network, .{ "127.0.0.1", &state_ptr.port_input_join, state_ptr }) catch @panic("couldn't start thread");
}

pub const Scenes = enum { Menu, Game, Waiting };

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
        player: Player = .{
            .player_type = 0,
            .pos = r.Vector2Zero(),
        },
    } = .{},
    positions_set: bool = false,
    game_score: GameScore = GameScore{},
    camera: r.Camera2D = .{
        .offset = .{
            .x = @divFloor(SCREEN_WIDTH, 2),
            .y = @divFloor(SCREEN_HEIGHT, 2),
        },
        .rotation = 0,
        .target = .{ .x = 0, .y = 0 },
        .zoom = 1.0,
    },
    ip_input_host: [16:0]u8 = undefined,
    port_input_join: [6:0]u8 = undefined,
    port_input_host: [6:0]u8 = undefined,
    current_scene: Scenes = .Menu,
    alloc: ?std.mem.Allocator = null,
    server_process: ?std.process.Child = null,

    pub fn get_random_dir(self: *GameState) r.Vector2 {
        const x_factor: f32 = if (self.rand.?.boolean()) 1.0 else -1.0;
        const y_factor: f32 = if (self.rand.?.boolean()) 1.0 else -1.0;
        return r.Vector2Normalize(
            r.Vector2{
                .x = (self.rand.?.float(f32) * 1.0 + 0.1) * x_factor,
                .y = (self.rand.?.float(f32) * 0.6 + 0.1) * y_factor,
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
    ) !void {
        var player1_score_buffer: [5]u8 = .{0} ** 5;
        var player2_score_buffer: [5]u8 = .{0} ** 5;

        var selected_input: ?u8 = null;

        var port_input_field_host = Input{
            .current_selection = &selected_input,
            .key = 2,
            .rectangle = r.Rectangle{
                .height = 50,
                .width = 250,
                .x = -130,
                .y = -100,
            },
        };

        var host_button = Button{
            .on_click = &host_pressed,
            .rectangle = r.Rectangle{
                .height = 50,
                .width = 200,
                .x = 35,
                .y = 100,
            },
            .text = "Host",
        };

        var ip_input_field = Input{
            .current_selection = &selected_input,
            .key = 0,
            .rectangle = r.Rectangle{
                .height = 50,
                .width = 250,
                .x = -400,
                .y = -100,
            },
        };

        var join_button = Button{
            .on_click = &join_pressed,
            .rectangle = r.Rectangle{
                .height = 50,
                .width = 200,
                .x = 140,
                .y = -100,
            },
            .text = "Join",
        };

        var port_input_field_join = Input{
            .current_selection = &selected_input,
            .key = 1,
            .rectangle = r.Rectangle{
                .height = 50,
                .width = 250,
                .x = -235,
                .y = 100,
            },
        };

        r.SetTraceLogLevel(r.LOG_ERROR);
        r.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Pong");
        defer r.CloseWindow();

        r.SetTargetFPS(166);

        while (!r.WindowShouldClose()) {
            if (server_message_queue_ptr.readableLength() > 0) {

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

                    self.current_scene = .Waiting;
                    continue;
                }

                if (self.current_scene != .Game and server_message.started == 1) {
                    self.current_scene = .Game;
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

                self.server_info.ball.pos = server_message.ball_pos;
                self.ball.dir = server_message.ball_dir;
                self.ball.speed = server_message.ball_speed;
                self.game_score.player1_score = server_message.player1_score;
                self.game_score.player2_score = server_message.player2_score;
                self.server_info.player.pos = server_message.player_pos;
                for (game_state_queue_ptr.readableSlice(0)) |*snapshot_ptr| {
                    const other_player_pos = snapshot_ptr.other_player_pos;
                    self.server_info.player.update(snapshot_ptr.input, server.TICK_DURATION_S);

                    const player_aabb = AABB.init(&self.player.pos, Player.PLAYER_WIDTH, Player.PLAYER_LENGTH);
                    const player_other_aabb = AABB.init(&other_player_pos, Player.PLAYER_WIDTH, Player.PLAYER_LENGTH);
                    self.server_info.ball.update(self, .{ &player_aabb, &player_other_aabb }, server.TICK_DURATION_S);
                }
                self.ball.dir = server_message.ball_dir;
                self.ball.speed = server_message.ball_speed;
            }

            if (self.current_scene == .Game) {
                const player_aabb = AABB.init(&self.player.pos, Player.PLAYER_WIDTH, Player.PLAYER_LENGTH);
                const other_player_aabb = AABB.init(&self.other_player.pos, Player.PLAYER_WIDTH, Player.PLAYER_LENGTH);

                const collisions = [_]*const AABB{ &player_aabb, &other_player_aabb };

                const input: i2 = if (r.IsKeyDown(r.KEY_D)) 1 else if (r.IsKeyDown(r.KEY_A)) -1 else 0;

                self.player.update(input, r.GetFrameTime());

                const player_dist = r.Vector2Distance(self.player.pos, self.server_info.player.pos);
                if (player_dist > 0.05) {
                    self.player.pos = r.Vector2MoveTowards(
                        self.player.pos,
                        self.server_info.player.pos,
                        std.math.pow(f32, player_dist, 1.5) * r.GetFrameTime(),
                    );
                }

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

            r.BeginMode2D(self.camera);

            switch (self.current_scene) {
                .Game => {
                    // Render the game

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
                },
                .Menu => {
                    r.DrawRectangle(
                        Player.PLAYER_1_STARTING_POSITION.x,
                        Player.PLAYER_1_STARTING_POSITION.y,
                        Player.PLAYER_WIDTH,
                        Player.PLAYER_LENGTH,
                        r.RAYWHITE,
                    );

                    r.DrawRectangle(
                        Player.PLAYER_2_STARTING_POSITION.x,
                        Player.PLAYER_2_STARTING_POSITION.y,
                        Player.PLAYER_WIDTH,
                        Player.PLAYER_LENGTH,
                        r.RAYWHITE,
                    );

                    r.DrawRectangle(
                        Ball.INITIAL_POSITION.x,
                        Ball.INITIAL_POSITION.y,
                        Ball.SIZE,
                        Ball.SIZE,
                        r.RAYWHITE,
                    );

                    r.DrawRectangle(
                        -2,
                        -SCREEN_HEIGHT / 2,
                        4,
                        SCREEN_HEIGHT,
                        r.RAYWHITE,
                    );

                    r.DrawRectangle(
                        -SCREEN_WIDTH / 2,
                        -SCREEN_HEIGHT / 2,
                        SCREEN_WIDTH,
                        SCREEN_HEIGHT,
                        r.ColorAlpha(
                            r.BLACK,
                            0.8,
                        ),
                    );

                    r.DrawRectangleRounded(
                        r.Rectangle{
                            .x = -SCREEN_WIDTH / 2 + 25,
                            .y = -2,
                            .width = SCREEN_WIDTH - 50,
                            .height = 2,
                        },
                        0.5,
                        5,
                        r.RAYWHITE,
                    );

                    host_button.update(self);
                    join_button.update(self);
                    ip_input_field.update(&self.ip_input_host, self);
                    port_input_field_join.update(&self.port_input_join, self);
                    port_input_field_host.update(&self.port_input_host, self);
                },
                .Waiting => {
                    r.DrawRectangle(
                        Player.PLAYER_1_STARTING_POSITION.x,
                        Player.PLAYER_1_STARTING_POSITION.y,
                        Player.PLAYER_WIDTH,
                        Player.PLAYER_LENGTH,
                        r.RAYWHITE,
                    );

                    r.DrawRectangle(
                        Player.PLAYER_2_STARTING_POSITION.x,
                        Player.PLAYER_2_STARTING_POSITION.y,
                        Player.PLAYER_WIDTH,
                        Player.PLAYER_LENGTH,
                        r.RAYWHITE,
                    );

                    r.DrawRectangle(
                        Ball.INITIAL_POSITION.x,
                        Ball.INITIAL_POSITION.y,
                        Ball.SIZE,
                        Ball.SIZE,
                        r.RAYWHITE,
                    );

                    r.DrawRectangle(
                        -2,
                        -SCREEN_HEIGHT / 2,
                        4,
                        SCREEN_HEIGHT,
                        r.RAYWHITE,
                    );

                    r.DrawRectangle(
                        -SCREEN_WIDTH / 2,
                        -SCREEN_HEIGHT / 2,
                        SCREEN_WIDTH,
                        SCREEN_HEIGHT,
                        r.ColorAlpha(
                            r.BLACK,
                            0.8,
                        ),
                    );

                    const text = "Waiting for Player 2";
                    const text_width = r.MeasureText(text, 50);
                    r.DrawText(text, @divFloor(-text_width, 2), -25, 50, r.RAYWHITE);
                },
            }

            r.EndMode2D();
            r.EndDrawing();
        }

        if (self.server_process) |*process| {
            _ = try process.kill();
        }
    }
};
