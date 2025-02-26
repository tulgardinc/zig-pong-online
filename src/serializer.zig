const std = @import("std");
const protocol = @import("protocol.zig");
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const native_endian = @import("builtin").target.cpu.arch.endian();

const BUFFER_LENGTH_TYPE = u16;

pub fn ProtocolBuffer(comptime T: type, comptime len: comptime_int) type {
    return struct {
        const ProtocolBuffer: void = undefined;

        populated: BUFFER_LENGTH_TYPE = 0,
        buffer: [len]T = undefined, // TODO: make the buffer not owning

        const Self = @This();

        pub fn add(self: *Self, item: T) void {
            self.buffer[self.populated] = item;
            self.populated += 1;
        }

        pub fn reset(self: *Self) void {
            self.buffer = undefined;
            self.populated = 0;
        }

        pub fn get_filled_slice(self: *const Self) []const u8 {
            return self.buffer[0..self.populated];
        }
    };
}

fn serialize_endian(x: anytype) @TypeOf(x) {
    switch (native_endian) {
        .big => {
            return x;
        },
        .little => {
            return @byteSwap(x);
        },
    }
}

fn deserialize_endian(x: anytype) @TypeOf(x) {
    switch (native_endian) {
        .big => {
            return x;
        },
        .little => {
            return @byteSwap(x);
        },
    }
}

fn get_int_type_for_float(float_type: type) type {
    return switch (float_type) {
        f16 => u16,
        f32 => u32,
        f64 => u64,
        f128 => u128,
        else => @compileError("type of float not supported"),
    };
}

fn get_serialization_size(sum: comptime_int, data_type: type) comptime_int {
    var cur_sum = sum;
    const object_info = @typeInfo(data_type);

    switch (object_info) {
        .@"struct" => {
            if (@hasField(data_type, "ProtocolBuffer")) {
                cur_sum += @sizeOf(BUFFER_LENGTH_TYPE);
                const buffer = @field(data_type, "buffer");
                const buffer_len = @typeInfo(@TypeOf(buffer)).array.len;
                const item_type = @typeInfo(@TypeOf(buffer)).array.child;
                cur_sum += get_serialization_size(0, item_type) * buffer_len;
            } else {
                inline for (object_info.@"struct".fields) |field| {
                    cur_sum += get_serialization_size(0, field.type);
                }
            }
        },
        .pointer => {
            cur_sum += get_serialization_size(cur_sum, object_info.pointer.child);
        },
        else => {
            cur_sum += @sizeOf(data_type);
        },
    }

    return cur_sum;
}

fn serialize_numeric(numeric: anytype, buffer: []u8) void {
    if (@sizeOf(@TypeOf(numeric)) == 1) {
        buffer[0] = std.mem.toBytes(numeric)[0];
        return;
    }

    const field_type = @TypeOf(numeric);
    const field_type_info = @typeInfo(field_type);
    switch (field_type_info) {
        .float => {
            const int_type = get_int_type_for_float(field_type);
            const int_rep: int_type = @bitCast(numeric);
            @memcpy(buffer[0..], std.mem.asBytes(&serialize_endian(int_rep)));
        },
        .int => {
            @memcpy(buffer[0..], std.mem.asBytes(&serialize_endian(numeric)));
        },
        else => @compileError("Field type not supported"),
    }
}

fn deserialize_numeric(data: []const u8, target_field: anytype) void {
    const buffer_ptr_type = @TypeOf(target_field);
    if (@typeInfo(buffer_ptr_type) != .pointer) @compileError("bufer should be a pointer");
    const child_type = @typeInfo(buffer_ptr_type).pointer.child;

    if (@sizeOf(child_type) == 1) {
        target_field.* = @intCast(std.mem.bytesAsValue(child_type, &data[0]).*);
        return;
    }

    switch (@typeInfo(child_type)) {
        .float => {
            const int_type = get_int_type_for_float(child_type);
            // const int_rep: *const int_type = @alignCast(@ptrCast(data.ptr));
            const int_rep = std.mem.bytesAsValue(int_type, data.ptr);
            target_field.* = @bitCast(deserialize_endian(int_rep.*));
        },
        .int => {
            const int: *const child_type = @alignCast(@ptrCast(data.ptr));
            target_field.* = @bitCast(deserialize_endian(int.*));
        },
        else => @compileError("Field type not supported"),
    }
}

fn serialize_data(slice: []u8, index: u32, object: anytype) void {
    var cur_index = index;

    const object_type = @TypeOf(object);
    const object_type_info = @typeInfo(object_type);
    const object_size = @sizeOf(object_type);

    switch (object_type_info) {
        .float, .int => {
            serialize_numeric(object, slice[cur_index .. cur_index + object_size]);
            cur_index += object_size;
        },
        .@"struct" => {
            if (@hasDecl(object_type, "ProtocolBuffer")) {
                serialize_numeric(
                    @field(object, "populated"),
                    slice[cur_index .. cur_index + @sizeOf(BUFFER_LENGTH_TYPE)],
                );
                cur_index += @sizeOf(BUFFER_LENGTH_TYPE);
                const buffer = @field(object, "buffer");
                const buffer_type = @TypeOf(buffer);
                const item_type = @typeInfo(buffer_type).array.child;
                const item_size = get_serialization_size(0, item_type);

                for (buffer) |num| {
                    serialize_data(slice, cur_index, num);
                    cur_index += item_size;
                }
            } else {
                const fields = object_type_info.@"struct".fields;

                inline for (fields) |field| {
                    serialize_data(
                        slice,
                        cur_index,
                        @field(object, field.name),
                    );
                    cur_index += get_serialization_size(0, field.type);
                }
            }
        },
        .pointer => {
            serialize_data(slice, cur_index, object.*);
        },
        else => {
            @compileError("Type not supported");
        },
    }
}

fn get_struct_type_info_from_pointer(arg: type) std.builtin.Type.Struct {
    const arg_type = @typeInfo(arg);

    if (arg_type != .pointer) @compileError("Argument should be pointer to struct");
    const pointer_type = arg_type.pointer;

    const child_type_info = @typeInfo(pointer_type.child);
    if (child_type_info != .@"struct") @compileError("Argument should be pointer to struct");

    return child_type_info.@"struct";
}

pub fn serialize(
    object: anytype,
) [
    get_serialization_size(
        0,
        @TypeOf(object),
    )
]u8 {
    const size = get_serialization_size(0, @TypeOf(object));
    var array_representation: [size]u8 = undefined;

    serialize_data(
        &array_representation,
        0,
        object,
    );

    // THIS COPIES THE ARRAY COULD BE OPTIMIZED
    return array_representation;
}

fn deserialize_data(target: anytype, data: []const u8, index: u32) void {
    var cur_index = index;
    const target_type = @TypeOf(target);
    const target_info = @typeInfo(target_type);

    if (target_info != .pointer) @compileError("should be called with a pointer");
    const child_type = target_info.pointer.child;
    const child_info = @typeInfo(child_type);
    const child_size = get_serialization_size(0, target_info.pointer.child);

    switch (child_info) {
        .@"struct" => {
            if (@hasDecl(child_type, "ProtocolBuffer")) {
                var length_as_array: [@sizeOf(BUFFER_LENGTH_TYPE)]u8 = undefined;
                @memcpy(&length_as_array, data[cur_index .. cur_index + @sizeOf(BUFFER_LENGTH_TYPE)]);

                @field(target, "populated") = std.mem.readInt(
                    BUFFER_LENGTH_TYPE,
                    &length_as_array,
                    native_endian,
                );

                deserialize_numeric(
                    data[cur_index .. cur_index + @sizeOf(BUFFER_LENGTH_TYPE)],
                    &@field(target, "populated"),
                );

                cur_index += @sizeOf(BUFFER_LENGTH_TYPE);
                const buffer = &@field(target, "buffer");
                const buffer_type = @TypeOf(buffer.*);
                const item_type = @typeInfo(buffer_type).array.child;
                const el_size = get_serialization_size(0, item_type);

                for (buffer) |*el| {
                    deserialize_data(el, data, cur_index);
                    cur_index += el_size;
                }
            } else {
                const fields = child_info.@"struct".fields;

                inline for (fields) |field| {
                    const field_size = get_serialization_size(0, field.type);
                    deserialize_data(
                        &@field(target, field.name),
                        data,
                        cur_index,
                    );
                    cur_index += field_size;
                }
            }
        },
        .int, .float => {
            deserialize_numeric(
                data[cur_index .. cur_index + child_size],
                target,
            );
            cur_index += child_size;
        },
        .pointer => {
            deserialize_data(target.*, data, cur_index);
        },
        else => @compileError("unsuported type"),
    }
}

pub fn deserialize(struct_to_fill: anytype, data: []const u8) void {
    if (@typeInfo(@TypeOf(struct_to_fill)) != .pointer) @compileError("Argument should be a pointer to a struct type");
    const ptr_child = @typeInfo(@typeInfo(@TypeOf(struct_to_fill)).pointer.child);
    if (ptr_child != .@"struct") @compileError("Argument should be a pointer to a struct type");

    deserialize_data(struct_to_fill, data, 0);
}

pub const Vector2 = struct { x: f32, y: f32 };

pub const PlayerInfo = struct {
    pos: Vector2,
    id: i32,
};

const NegativeTest = struct {
    num: i32,
};

// test "negative" {
//     const num = NegativeTest{ .num = -100 };

//     const serialized = serialize(&num);

//     var deserialized: NegativeTest = undefined;
//     deserialize(&deserialized, &serialized);
//     std.debug.print("\n{any}\n", .{deserialized});
// }

// test "serialize" {
//     var player_info = PlayerInfo{
//         .pos = .{
//             .x = 10,
//             .y = 20,
//         },
//         .id = -100,
//     };

//     const serialized = serialize(&player_info);

//     std.debug.print("\n{any}\n", .{serialized});
// }

// test "serialize" {
//     var data = Vector2{
//         .x = 10,
//         .y = 20,
//     };

//     const serialized = serialize(&data);

//     std.debug.print("\n{any}\n", .{serialized});

//     var deserialized: Vector2 = undefined;
//     deserialize(&deserialized, &serialized);

//     std.debug.print("\n{any}\n", .{deserialized});
// }

// const test_struct = struct {
//     pos: r.Vector2,
// };

// pub const ClientMessage = struct {
//     input: i2 = 0,
//     pos: r.Vector2 = r.Vector2Zero(),
// };

// test "serialize" {
//     var data = test_struct{
//         .pos = r.Vector2{
//             .x = 10,
//             .y = 20,
//         },
//         //.input = 0,
//     };

//     const serialized = serialize(&data);

//     std.debug.print("\n{any}\n", .{serialized});

//     var deserialized: test_struct = undefined;
//     deserialize(&deserialized, &serialized);

//     std.debug.print("\n{any}\n", .{deserialized});
// }

const itest_struct = struct {
    input: Vector2,
    input2: i64,
};

test "deserialize" {
    var data = itest_struct{
        .input = Vector2{ .x = 10, .y = 20 },
        .input2 = -100000,
    };

    const serialized = serialize(&data);

    std.debug.print("\n{any}\n", .{serialized});

    var deserialized: itest_struct = undefined;
    deserialize(&deserialized, &serialized);

    std.debug.print("\n{any}\n", .{deserialized});
}
