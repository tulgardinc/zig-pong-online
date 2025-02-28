const std = @import("std");
const server = @import("server.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();

    var args_iter = try std.process.argsWithAllocator(alloc);
    defer args_iter.deinit();

    _ = args_iter.skip();

    const port = args_iter.next() orelse @panic("no port number :(");

    std.debug.print("port: {s}\n", .{port});

    try server.run(port);
}
