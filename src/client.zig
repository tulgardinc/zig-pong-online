const std = @import("std");
const server = @import("server.zig");
const protocol = @import("protocol.zig");

const ws2_32 = std.os.windows.ws2_32;

//const BUFF_SIZE = 1024;

var player_info = protocol.PlayerInfo{
    .buffer = .{},
    .id = 0,
    .pos = .{
        .x = 10,
        .y = 20,
    },
};

pub fn run() !void {
    const reader = std.io.getStdIn().reader();
    var buffer_stream = std.io.fixedBufferStream(&player_info.buffer.buffer);

    var result: i32 = 0;

    _ = try std.os.windows.WSAStartup(2, 2);
    defer _ = ws2_32.WSACleanup();
    errdefer _ = ws2_32.WSACleanup();

    const socketfd = ws2_32.socket(ws2_32.AF.INET, ws2_32.SOCK.DGRAM, 0);
    if (socketfd == ws2_32.INVALID_SOCKET) return;

    const server_addr = ws2_32.sockaddr.in{
        .family = ws2_32.AF.INET,
        .port = ws2_32.htons(server.SERVER_PORT),
        .addr = ws2_32.inet_addr("127.0.0.1"),
    };

    const client_addr = ws2_32.sockaddr.in{
        .family = ws2_32.AF.INET,
        .port = 0,
        .addr = ws2_32.inet_addr("0.0.0.0"),
    };

    result = ws2_32.bind(socketfd, @ptrCast(&client_addr), @sizeOf(ws2_32.sockaddr));
    defer _ = ws2_32.closesocket(socketfd);
    if (result != 0) return;

    while (true) {
        try reader.streamUntilDelimiter(buffer_stream.writer(), '\n', null);
        defer {
            buffer_stream.reset();
            player_info.buffer.populated = 0;
        }
        player_info.buffer.populated = @intCast(try buffer_stream.getPos() - 1);

        const buffer = protocol.serialize(player_info);

        result = ws2_32.sendto(
            socketfd,
            @ptrCast(&buffer),
            @intCast(buffer.len),
            0,
            @ptrCast(&server_addr),
            @sizeOf(ws2_32.sockaddr),
        );
        if (result == ws2_32.SOCKET_ERROR) {
            std.debug.print("failed sendto: {}\n", .{ws2_32.WSAGetLastError()});
            continue;
        }

        // while (true) {
        //     result = ws2_32.recv(socketfd, @ptrCast(&buffer), @intCast(BUFF_SIZE), 0);
        //     if (result == ws2_32.SOCKET_ERROR) {
        //         std.debug.print("failed recv: {}\n", .{ws2_32.WSAGetLastError()});
        //         break;
        //     }
        //     std.debug.print("received: {s}\n", .{buffer[0..@intCast(result)]});
        //     break;
        // }
    }
}
