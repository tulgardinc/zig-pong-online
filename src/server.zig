const std = @import("std");
const ws2_32 = std.os.windows.ws2_32;
const protocol = @import("protocol.zig");

pub const SERVER_PORT = 12345;
const BUFF_SIZE = 4096;

pub fn run() !void {
    var buffer: [BUFF_SIZE]u8 = undefined;
    var result: i32 = 0;

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
    var cli_addr_len: ws2_32.socklen_t = @sizeOf(ws2_32.sockaddr);

    while (true) {
        const bytes_recv = std.os.windows.recvfrom(
            sockfd,
            @ptrCast(&buffer),
            BUFF_SIZE,
            0,
            &cli_addr,
            &cli_addr_len,
        );
        if (bytes_recv == ws2_32.SOCKET_ERROR) {
            std.debug.print("recvfrom failed: {}\n", .{ws2_32.WSAGetLastError()});
            continue;
        }

        // const player_info = protocol.PlayerInfo{
        // };

        var player_info: protocol.PlayerInfo = undefined;
        protocol.deserialize(&player_info, &buffer);

        std.debug.print("{s}, pos: {d}, {d} id: {d}\n", .{
            player_info.buffer.get_filled_slice(),
            player_info.pos.x,
            player_info.pos.y,
            player_info.id,
        });

        // result = std.os.windows.sendto(
        //     sockfd,
        //     @ptrCast(&buffer),
        //     @intCast(bytes_recv),
        //     0,
        //     &cli_addr,
        //     cli_addr_len,
        // );
        // if (result == ws2_32.SOCKET_ERROR) {
        //     std.debug.print("sendto failed: {}\n", .{ws2_32.WSAGetLastError()});
        //     continue;
        // }
    }
}
