const std = @import("std");
const server = @import("server.zig");
const protocol = @import("protocol.zig");
const serializer = @import("serializer.zig");
const game = @import("game/game.zig");
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const ws2_32 = std.os.windows.ws2_32;

const CLIENT_TICK_RATE = 60;
const TICK_TIME_MCS: i64 = 1000000 / CLIENT_TICK_RATE;

var buffer: [BUFF_SIZE]u8 = undefined;

const BUFF_SIZE = 4096;

pub var game_state_buffer: game.GameStateSnapshot = undefined;

pub const ServerMessageQueue = std.fifo.LinearFifo(protocol.ServerMessage, .{ .Static = 2048 });
pub var server_message_queue: ServerMessageQueue = ServerMessageQueue.init();

pub const GameStateSnapshotQueue = std.fifo.LinearFifo(game.GameStateSnapshot, .{ .Static = 2048 });
pub var game_state_queue: GameStateSnapshotQueue = GameStateSnapshotQueue.init();

pub fn run(alloc: std.mem.Allocator) !void {
    var game_state = game.GameState{ .server = false, .alloc = alloc };
    try game_state.run_game(
        &game_state_buffer,
        &server_message_queue,
        &game_state_queue,
    );
}

pub fn run_network(
    server_ip: [:0]const u8,
    server_port: [:0]const u8,
    game_state_ptr: *game.GameState,
) !void {
    errdefer {
        if (game_state_ptr.server_process) |*process| {
            _ = process.kill() catch @panic("failed to shutdown server");
        }
    }

    var result: i32 = 0;

    _ = try std.os.windows.WSAStartup(2, 2);
    defer _ = ws2_32.WSACleanup();
    errdefer _ = ws2_32.WSACleanup();

    const socketfd = ws2_32.socket(ws2_32.AF.INET, ws2_32.SOCK.DGRAM, 0);
    if (socketfd == ws2_32.INVALID_SOCKET) return;

    const server_addr = ws2_32.sockaddr.in{
        .family = ws2_32.AF.INET,
        .port = ws2_32.htons(try std.fmt.parseInt(u16, std.mem.sliceTo(server_port, 0), 10)),
        .addr = ws2_32.inet_addr(@ptrCast(std.mem.sliceTo(server_ip, 0))),
    };

    result = ws2_32.connect(socketfd, @ptrCast(&server_addr), @sizeOf(ws2_32.sockaddr));
    defer _ = ws2_32.closesocket(socketfd);
    if (result == ws2_32.SOCKET_ERROR) return;

    var local_sockaddr: ws2_32.sockaddr = undefined;
    var name_len: i32 = @intCast(@sizeOf(ws2_32.sockaddr.in));
    result = ws2_32.getsockname(socketfd, &local_sockaddr, &name_len);
    if (result == ws2_32.SOCKET_ERROR) @panic("failed to get ip");

    var next_tick = std.time.microTimestamp();

    var message: protocol.ClientMessage = undefined;

    while (true) {
        const select_timeout = next_tick - std.time.microTimestamp();
        if (select_timeout > 0) {
            var fd_set: ws2_32.fd_set = undefined;
            fd_set.fd_array[0] = socketfd;
            fd_set.fd_count = 1;
            const socket_activity = ws2_32.select(0, &fd_set, null, null, &.{ .sec = 0, .usec = @intCast(select_timeout) });
            if (socket_activity > 0) {
                result = ws2_32.recv(socketfd, @ptrCast(&buffer), @intCast(BUFF_SIZE), 0);
                if (result == ws2_32.SOCKET_ERROR) {
                    std.debug.print("failed recv: {}\n", .{ws2_32.WSAGetLastError()});
                    continue;
                }

                var server_message: protocol.ServerMessage = undefined;
                serializer.deserialize(&server_message, buffer[0..@intCast(result)]);

                try server_message_queue.writeItem(server_message);

                continue;
            }
        }

        // ticking

        next_tick = std.time.microTimestamp() + TICK_TIME_MCS;

        if (game_state_ptr.current_scene == .Waiting) continue;

        const game_state_snapshot = game_state_buffer;

        message.input = game_state_snapshot.input;
        message.stamp = game_state_snapshot.stamp;
        const client_message_serialized = serializer.serialize(&message);

        result = ws2_32.sendto(
            socketfd,
            @ptrCast(&client_message_serialized),
            @intCast(client_message_serialized.len),
            0,
            @ptrCast(&server_addr),
            @sizeOf(ws2_32.sockaddr.in),
        );
        if (result == ws2_32.SOCKET_ERROR) {
            std.debug.print("failed sendto: {}\n", .{ws2_32.WSAGetLastError()});
            continue;
        }

        if (game_state_ptr.current_scene == .Game) {
            game_state_queue.writeItem(game_state_snapshot) catch |err| {
                std.debug.panic("failed to add to queue: {}\n", .{err});
            };
        }
    }
}

const a = std.Thread.Mutex{};
