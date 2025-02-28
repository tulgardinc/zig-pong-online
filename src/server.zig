const std = @import("std");
const ws2_32 = std.os.windows.ws2_32;
const protocol = @import("protocol.zig");
const serializer = @import("serializer.zig");
const Player = @import("game/Player.zig");
const game = @import("game/game.zig");
const AABB = @import("game/AABB.zig");
const Ball = @import("game/Ball.zig");
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const BUFF_SIZE = 4096;

const SERVER_TICK_RATE = 60;
pub const TICK_DURATION_MCS: i64 = 1000000 / SERVER_TICK_RATE;
pub const TICK_DURATION_S = 1.0 / @as(comptime_float, @floatFromInt(SERVER_TICK_RATE));

const ClientMessageWrapper = struct {
    id: ?u32,
    message: protocol.ClientMessage,
};

const PlayerWrapper = struct {
    id: ?u32,
    player: *Player,
};

const ClientMessageQueue = std.fifo.LinearFifo(ClientMessageWrapper, .{ .Static = 2048 });

pub fn run(port: [:0]const u8) !void {
    var buffer: [BUFF_SIZE]u8 = undefined;
    var result: i32 = 0;

    var random_engine = std.Random.DefaultPrng.init(@intCast(std.time.microTimestamp()));
    const rand = random_engine.random();

    var client_message_queue: ClientMessageQueue = ClientMessageQueue.init();

    var game_state = game.GameState{ .server = true, .rand = rand };
    game_state.ball.dir = game_state.get_random_dir();

    var player1 = PlayerWrapper{
        .player = &game_state.player,
        .id = null,
    };
    var player2 = PlayerWrapper{
        .player = &game_state.other_player,
        .id = null,
    };

    _ = try std.os.windows.WSAStartup(2, 2);
    defer _ = ws2_32.WSACleanup();

    const sockfd: ws2_32.SOCKET = ws2_32.socket(
        ws2_32.AF.INET,
        ws2_32.SOCK.DGRAM,
        0,
    );
    if (sockfd == ws2_32.INVALID_SOCKET) {
        _ = ws2_32.WSACleanup();
        return;
    }

    const server_addr = ws2_32.sockaddr.in{
        .family = ws2_32.AF.INET,
        .port = ws2_32.htons(try std.fmt.parseInt(u16, std.mem.sliceTo(port, 0), 10)),
        .addr = 0,
    };

    result = ws2_32.bind(sockfd, @ptrCast(&server_addr), @sizeOf(ws2_32.sockaddr.in));
    defer _ = ws2_32.closesocket(sockfd);
    if (result != 0) {
        _ = ws2_32.closesocket(sockfd);
        _ = ws2_32.WSACleanup();
        return;
    }

    var cli_addr = std.mem.zeroes(ws2_32.sockaddr);
    var sockaddr_len: ws2_32.socklen_t = @sizeOf(ws2_32.sockaddr.in);

    var next_tick_mcs = std.time.microTimestamp();

    var select_timeval: ws2_32.timeval = undefined;
    select_timeval.sec = 0;

    var player1_addr = std.mem.zeroes(ws2_32.sockaddr);
    var player2_addr = std.mem.zeroes(ws2_32.sockaddr);

    while (true) {
        const select_timeout = next_tick_mcs - std.time.microTimestamp();
        if (select_timeout > 0) {
            var fd_set: ws2_32.fd_set = undefined;
            fd_set.fd_array[0] = sockfd;
            fd_set.fd_count = 1;
            select_timeval.usec = @intCast(select_timeout);
            const socket_activity = ws2_32.select(
                0,
                &fd_set,
                null,
                null,
                &select_timeval,
            );
            if (socket_activity > 0) {
                const bytes_recv = std.os.windows.recvfrom(
                    sockfd,
                    @ptrCast(&buffer),
                    BUFF_SIZE,
                    0,
                    &cli_addr,
                    &sockaddr_len,
                );
                if (bytes_recv == ws2_32.SOCKET_ERROR) {
                    // std.debug.print("recvfrom failed: {}\n", .{ws2_32.WSAGetLastError()});
                    continue;
                }

                var client_message: protocol.ClientMessage = undefined;
                serializer.deserialize(&client_message, &buffer);

                const cli_casted: ws2_32.sockaddr.in = @bitCast(cli_addr);

                const incoming_id = @byteSwap(cli_casted.addr) + @byteSwap(cli_casted.port);
                if (player1.id == null) {
                    player1.id = incoming_id;
                    std.debug.print("Player 1 connected id {any}\n", .{player1.id});
                    player1_addr = cli_addr;

                    const server_message = serializer.serialize(protocol.ServerMessage{ .player = 0 });

                    result = std.os.windows.sendto(
                        sockfd,
                        @ptrCast(&server_message),
                        @intCast(server_message.len),
                        0,
                        &player1_addr,
                        @intCast(sockaddr_len),
                    );
                    // TODO: ERROR CHECK

                } else if (incoming_id != player1.id.?) {
                    if (player2.id == null) {
                        player2.id = incoming_id;
                        std.debug.print("Player 2 connected id {any}\n", .{player2.id});
                        player2_addr = cli_addr;

                        const server_message = serializer.serialize(protocol.ServerMessage{ .player = 1 });

                        result = std.os.windows.sendto(
                            sockfd,
                            @ptrCast(&server_message),
                            @intCast(server_message.len),
                            0,
                            &player2_addr,
                            @intCast(sockaddr_len),
                        );
                    }
                }

                try client_message_queue.writeItem(.{
                    .id = incoming_id,
                    .message = client_message,
                });

                continue;
            }
        }

        next_tick_mcs = std.time.microTimestamp() + TICK_DURATION_MCS;

        // simulate
        // only start sending when both players are connected
        if (player1.id == null or player2.id == null) {
            continue;
        }

        var p1_stamp: i64 = 0;
        var p2_stamp: i64 = 0;

        while (client_message_queue.readableLength() > 0) {
            const client_message = client_message_queue.readItem().?;
            if (client_message.id == player1.id) {
                player1.player.update(client_message.message.input, TICK_DURATION_S);
                p1_stamp = client_message.message.stamp;
            } else {
                player2.player.update(client_message.message.input, TICK_DURATION_S);
                p2_stamp = client_message.message.stamp;
            }
        }

        const player1_aabb = AABB.init(
            &player1.player.pos,
            Player.PLAYER_WIDTH,
            Player.PLAYER_LENGTH,
        );
        const player2_aabb = AABB.init(
            &player2.player.pos,
            Player.PLAYER_WIDTH,
            Player.PLAYER_LENGTH,
        );

        game_state.ball.update(&game_state, .{ &player1_aabb, &player2_aabb }, TICK_DURATION_S);

        const message_to_p1 = protocol.ServerMessage{
            .ball_pos = game_state.ball.pos,
            .ball_dir = game_state.ball.dir,
            .ball_speed = game_state.ball.speed,
            .player_pos = player1.player.pos,
            .other_player_pos = player2.player.pos,
            .stamp = p1_stamp,
            .player = 0,
            .player1_score = game_state.game_score.player1_score,
            .player2_score = game_state.game_score.player2_score,
            .started = 1,
        };
        const p1_buffer = serializer.serialize(message_to_p1);

        const message_to_p2 = protocol.ServerMessage{
            .ball_pos = game_state.ball.pos,
            .ball_dir = game_state.ball.dir,
            .ball_speed = game_state.ball.speed,
            .player_pos = player2.player.pos,
            .other_player_pos = player1.player.pos,
            .stamp = p2_stamp,
            .player = 1,
            .player1_score = game_state.game_score.player1_score,
            .player2_score = game_state.game_score.player2_score,
            .started = 1,
        };
        const p2_buffer = serializer.serialize(message_to_p2);

        result = std.os.windows.sendto(
            sockfd,
            @ptrCast(&p1_buffer),
            @intCast(p1_buffer.len),
            0,
            &player1_addr,
            @intCast(sockaddr_len),
        );
        if (result == ws2_32.SOCKET_ERROR) {
            std.debug.print("player 1 sendto failed: {}\n", .{ws2_32.WSAGetLastError()});
            continue;
        }

        result = std.os.windows.sendto(
            sockfd,
            @ptrCast(&p2_buffer),
            @intCast(p2_buffer.len),
            0,
            &player2_addr,
            @intCast(sockaddr_len),
        );
        if (result == ws2_32.SOCKET_ERROR) {
            std.debug.print("player 2 sendto failed: {}\n", .{ws2_32.WSAGetLastError()});
            continue;
        }
    }
}
