const std = @import("std");
const server = @import("server.zig");
const client = @import("client.zig");
const game = @import("game/game.zig");

const r = @cImport({
    @cInclude("raylib.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip();

    const first_arg = args.next() orelse {
        std.debug.print("needs arguments\n", .{});
        return;
    };

    if (std.mem.eql(u8, first_arg, "server")) {
        try server.run();
    } else if (std.mem.eql(u8, first_arg, "client")) {
        try client.run();
    } else {
        std.debug.print("wrong argument\n", .{});
    }
}
