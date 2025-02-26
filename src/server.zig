const std = @import("std");
const ws2_32 = std.os.windows.ws2_32;
const protocol = @import("protocol.zig");
const serializer = @import("serializer.zig");
const OtherPlayer = @import("game/OtherPlayer.zig");
const Player = @import("game/Player.zig");
const game = @import("game/game.zig");
const AABB = @import("game/AABB.zig");

pub const SERVER_PORT = 12345;
const BUFF_SIZE = 4096;

const SERVER_TICK_RATE = 60;
pub const TICK_DURATION_MCS = 1000000 / SERVER_TICK_RATE;
pub const TICK_DURATION_S = 1 / SERVER_TICK_RATE;

const ClientMessageWrapper = struct {
    id: u64,
    message: protocol.ClientMessage,
};

const ClientMessageQueue = std.fifo.LinearFifo(protocol.ClientMessage, .{ .Static = 2048 });

pub fn run() !void {
    var buffer: [BUFF_SIZE]u8 = undefined;
    var result: i32 = 0;

    var client_message_queue: ClientMessageQueue = ClientMessageQueue.init();

    var ball = game.initial_ball;

    var player1 = OtherPlayer{
        .pos = game.PLAYER_1_STARTING_POSITION,
        .input = 0,
    };
    var player2 = OtherPlayer{
        .pos = game.PLAYER_2_STARTING_POSITION,
        .input = 0,
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
        .port = ws2_32.htons(SERVER_PORT),
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

    var next_tick = std.time.microTimestamp();

    var select_timeval: ws2_32.timeval = undefined;
    select_timeval.sec = 0;

    var player1_addr = std.mem.zeroes(ws2_32.sockaddr);
    var player2_addr = std.mem.zeroes(ws2_32.sockaddr);

    var message_to_p1: protocol.ServerMessage = undefined;
    var message_to_p2: protocol.ServerMessage = undefined;

    while (true) {
        const select_timeout = next_tick - std.time.microTimestamp();
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

                var player_to_process_ptr: *OtherPlayer = &player1;
                var message_to_process_ptr: *protocol.ServerMessage = &message_to_p1;

                const incoming_id = @byteSwap(cli_casted.addr) + @byteSwap(cli_casted.port);
                if (player1.id == null) {
                    player1.id = incoming_id;
                    std.debug.print("Player 1 connected id {any}\n", .{player1.id});
                    player1_addr = cli_addr;
                    message_to_p1.response = 1;
                } else if (incoming_id != player1.id.?) {
                    if (player2.id == null) {
                        player2.id = incoming_id;
                        std.debug.print("Player 2 connected id {any}\n", .{player2.id});
                        player2_addr = cli_addr;
                        message_to_p2.response = 1;
                    }
                    player_to_process_ptr = &player2;
                }

                if (player1.id == incoming_id) {
                    std.debug.print("received: {} from p1\n", .{client_message.stamp});
                } else {
                    std.debug.print("received: {} from p2\n", .{client_message.stamp});
                }

                player_to_process_ptr.input = client_message.input;
                message_to_process_ptr.stamp = client_message.stamp;

                continue;
            }
        }

        next_tick = std.time.microTimestamp() + TICK_DURATION_MCS;

        // simulate
        // only start sending when both players are connected
        if (player1.id == null or player2.id == null) {
            //std.debug.print("Waiting for players...\n", .{});
            continue;
        }

        player1.update(TICK_DURATION_S);
        const player1_aabb = AABB.init(
            &player1.pos,
            Player.PLAYER_WIDTH,
            Player.PLAYER_LENGTH,
        );
        player2.update(TICK_DURATION_S);
        const player2_aabb = AABB.init(
            &player2.pos,
            Player.PLAYER_WIDTH,
            Player.PLAYER_LENGTH,
        );

        ball.update(.{ &player1_aabb, &player2_aabb });

        message_to_p1.ball_pos = ball.pos;
        message_to_p1.ball_dir = ball.dir;
        message_to_p1.player_pos = player1.pos;
        message_to_p1.other_player_pos = player2.pos;
        const p1_buffer = serializer.serialize(message_to_p1);

        message_to_p2.ball_pos = ball.pos;
        message_to_p1.ball_dir = ball.dir;
        message_to_p2.player_pos = player2.pos;
        message_to_p2.other_player_pos = player1.pos;
        const p2_buffer = serializer.serialize(message_to_p2);

        std.debug.print("sending stamp to p1: {}\n", .{message_to_p1.stamp});
        std.debug.print("sending stamp to p2: {}\n", .{message_to_p2.stamp});

        result = std.os.windows.sendto(
            sockfd,
            @ptrCast(&p1_buffer),
            @intCast(p1_buffer.len),
            0,
            &player1_addr,
            @intCast(sockaddr_len),
        );
        if (result == ws2_32.SOCKET_ERROR) {
            //std.debug.print("sendto failed: {}\n", .{ws2_32.WSAGetLastError()});
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
            //std.debug.print("sendto failed: {}\n", .{ws2_32.WSAGetLastError()});
            continue;
        }

        message_to_p1.response = 0;
        message_to_p2.response = 0;
    }
}
