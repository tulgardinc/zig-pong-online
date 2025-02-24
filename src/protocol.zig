const std = @import("std");
const r = @cImport({
    @cInclude("raylib.h");
});

const native_endian = @import("builtin").target.cpu.arch.endian();

fn ProtocolBuffer(comptime T: type, comptime len: comptime_int) type {
    return struct {
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
            inline for (object_info.@"struct".fields) |field| {
                cur_sum += get_serialization_size(0, field.type);
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

fn struct_array_rep_size(comptime sum: u32, comptime fields: []const std.builtin.Type.StructField) comptime_int {
    comptime {
        var current_sum = sum;

        for (fields) |field| {
            const field_type = field.type;
            const field_type_info = @typeInfo(field_type);
            switch (field_type_info) {
                .@"struct" => {
                    const inner_fields = field_type_info.@"struct".fields;
                    current_sum += struct_array_rep_size(current_sum, inner_fields);
                },
                .int, .float => {
                    current_sum += @sizeOf(field_type);
                },
                .array => {
                    current_sum += @sizeOf(field_type);
                },
                .pointer => {},
                else => @compileError("Wrong type of field"),
            }
        }

        return current_sum;
    }
}

fn serialize_numeric(numeric: anytype, buffer: []u8) void {
    if (@sizeOf(@TypeOf(numeric)) == 1) {
        buffer[0] = numeric;
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
        target_field.* = @bitCast(data[0]);
    }

    switch (@typeInfo(child_type)) {
        .float => {
            const int_type = get_int_type_for_float(child_type);
            const int_rep: *const int_type = @alignCast(@ptrCast(data.ptr));
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
            const fields = object_type_info.@"struct".fields;

            inline for (fields) |field| {
                serialize_data(
                    slice,
                    cur_index,
                    @field(object, field.name),
                );
                cur_index += get_serialization_size(0, field.type);
            }
        },
        .array => {
            const child_type = object_type_info.array.child;

            for (object) |num| {
                serialize_data(slice, cur_index, num);
                cur_index += get_serialization_size(0, child_type);
            }
        },
        .pointer => {
            serialize_data(slice, cur_index, object.*);
        },
        else => {
            @compileError("Type" ++ object_type ++ "not supported");
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
    const child_info = @typeInfo(target_info.pointer.child);
    const child_size = get_serialization_size(0, target_info.pointer.child);

    switch (child_info) {
        .@"struct" => {
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
        },
        .int, .float => {
            deserialize_numeric(
                data[cur_index .. cur_index + child_size],
                target,
            );
            cur_index += child_size;
        },
        .array => {
            for (target) |*el| {
                const el_size = get_serialization_size(0, child_info.array.child);
                deserialize_data(
                    el,
                    data,
                    cur_index,
                );
                cur_index += el_size;
            }
        },
        .pointer => {
            deserialize_data(target.*, data, cur_index);
        },
        else => @compileError("unsuported type"),
    }
}

fn deserialize_to_struct(struct_to_fill: anytype, data: []const u8, index: u32) void {
    var cur_index = index;

    const ptr_type = @typeInfo(@TypeOf(struct_to_fill)).pointer;
    const struct_type = @typeInfo(ptr_type.child).@"struct";

    inline for (struct_type.fields) |field| {
        const field_type = field.type;
        const field_type_info = @typeInfo(field_type);
        switch (field_type_info) {
            .float, .int => {
                if (@sizeOf(field_type) > 1) {
                    @field(struct_to_fill, field.name) = deserialize_numeric(
                        data[cur_index .. cur_index + @sizeOf(field_type)],
                        field_type,
                    );
                } else {
                    @field(struct_to_fill, field.name) = @bitCast(data[cur_index]);
                }
                cur_index += @sizeOf(field_type);
            },
            .@"struct" => {
                const inner_struct_to_fill = &@field(struct_to_fill, field.name);
                const size = struct_array_rep_size(
                    0,
                    field_type_info.@"struct".fields,
                );
                deserialize_to_struct(
                    inner_struct_to_fill,
                    data,
                    cur_index,
                );
                cur_index += size;
            },
            .array => {
                const slice = data[cur_index .. cur_index + @sizeOf(field_type)];

                const child_info = @typeInfo(field_type_info.array.child);
                const child_size = @sizeOf(field_type_info.array.child);

                if (child_info == .int or child_info == .float) {
                    for (1..(slice.len / child_size)) |i| {
                        @field(struct_to_fill, field.name)[i] = @bitCast(deserialize_numeric(
                            slice[(i - 1) * child_size .. i * child_size],
                            field_type_info.array.child,
                        ));
                    }
                }
                cur_index += @sizeOf(field_type);
            },
            else => @compileError("Field type not supported"),
        }
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
    list: [4]u16,
};

test "serialize" {
    var player_info = PlayerInfo{
        .pos = .{
            .x = 10,
            .y = 20,
        },
        .id = 100,
        .list = .{ 1, 2, 3, 4 },
    };

    const serialized = serialize(&player_info);

    std.debug.print("\n{any}\n", .{serialized});
}

test "deserialize" {
    var player_info = PlayerInfo{
        .pos = .{
            .x = 10,
            .y = 20,
        },
        .id = 100,
        .list = .{ 1, 2, 3, 4 },
    };

    const serialized = serialize(&player_info);

    var deserialized: PlayerInfo = undefined;
    deserialize(&deserialized, &serialized);

    std.debug.print("\n{any}\n", .{deserialized});
}

test "type" {
    const buffer1 = ProtocolBuffer(u8, 10);
    //const buffer2 = ProtocolBuffer(u16, 15);

    try std.testing.expect(@TypeOf(buffer1) == @TypeOf(ProtocolBuffer(u8, 0)));
}
