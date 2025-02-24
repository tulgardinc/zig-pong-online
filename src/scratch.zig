const std = @import("std");

fn ProtocolBuffer(comptime T: type, comptime len: comptime_int) type {
    return struct {
        const ProtocolBuffer: void = undefined;

        populated: u32,
        buffer: [len]T,

        const Self = @This();

        pub fn add(self: *Self, item: T) void {
            self.buffer[self.populated] = item;
            self.populated += 1;
        }

        pub fn reset(self: *Self) void {
            self.buffer = undefined;
            self.populated = 0;
        }
    };
}

test "array_size" {
    const pb = ProtocolBuffer(u8, 5){ .populated = 0, .buffer = .{ 0, 0, 0, 0, 0 } };

    @compileLog(@hasDecl(@TypeOf(pb), "Prot"));
}
