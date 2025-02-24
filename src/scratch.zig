const std = @import("std");

fn test_fn(comptime x: u64) [*]u8 {
    comptime var val: []const u8 = &[0]u8{};
    inline for (0..x) |_| {
        val = val ++ .{0};
    }
    return val;
}

const Testing = struct {
    size: comptime_int,

    fn init(val: comptime_int) Testing {
        return .{ .size = val };
    }

    fn gen(self: *const Testing) [self.size]u8 {
        return [_]u8{0} ** self.size;
    }
};

test "array_size" {
    std.debug.print("{any}", .{Testing.init(5).gen()});
}
