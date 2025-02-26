const std = @import("std");

test "enum" {
    const data = [_]u8{ 65, 32, 0, 0 };
    const slice = data[0..];
    const int_rep: *const u32 = @alignCast(@ptrCast(slice.ptr));
    const swaped = @byteSwap(int_rep.*);
    const float: f32 = @bitCast(swaped);
    std.debug.print("\n{d}\n", .{float});
}

// pub fn main() !void {
//     comptime var slice: []const u8 = &[0]u8{};
//     slice = slice ++ [1]u8{1};
//     slice = slice ++ &[1]u8{2};
//     slice = slice ++ .{3};
//     std.debug.print("{any}\n", .{slice});
// }
