const std = @import("std");
const r = @cImport({
    @cInclude("raylib.h");
});

const native_endian = @import("builtin").target.cpu.arch.endian();

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
            }
        }

        return current_sum;
    }
}

fn serialize_numeric(field_value: anytype) [@sizeOf(@TypeOf(field_value))]u8 {
    const field_type = @TypeOf(field_value);
    const field_type_info = @typeInfo(field_type);
    switch (field_type_info) {
        .float => {
            const int_type = get_int_type_for_float(field_type);
            const int_rep: int_type = @bitCast(field_value);
            return @bitCast(serialize_endian(int_rep));
        },
        .int => {
            return @bitCast(serialize_endian(field_value));
        },
        else => @compileError("Field type not supported"),
    }
}

fn deserialize_numeric(data: []const u8, data_type: type) data_type {
    switch (@typeInfo(data_type)) {
        .float => {
            const int_type = get_int_type_for_float(data_type);
            const int_rep: *const int_type = @alignCast(@ptrCast(data.ptr));
            return @bitCast(deserialize_endian(int_rep.*));
        },
        .int => {
            const int: *const data_type = @alignCast(@ptrCast(data.ptr));
            return @bitCast(serialize_endian(int.*));
        },
        else => @compileError("Field type not supported"),
    }
}

fn serialize_struct(slice: []u8, index: u32, object: anytype, struct_type_info: std.builtin.Type.Struct) void {
    var cur_index = index;

    const fields = struct_type_info.fields;

    inline for (fields) |field| {
        const field_type = field.type;
        const field_type_info = @typeInfo(field_type);
        switch (field_type_info) {
            .float, .int => {
                if (@sizeOf(field_type) > 1) {
                    @memcpy(
                        slice[cur_index .. cur_index + @sizeOf(field_type)],
                        &serialize_numeric(@field(object, field.name)),
                    );
                } else {
                    slice[cur_index] = @bitCast(@field(object, field.name));
                }
                cur_index += @sizeOf(field_type);
            },
            .@"struct" => {
                const size = struct_array_rep_size(0, field_type_info.@"struct".fields);
                serialize_struct(
                    slice,
                    cur_index,
                    @field(object, field.name),
                    field_type_info.@"struct",
                );
                cur_index += size;
            },
            .array => {
                const child_info = @typeInfo(field_type_info.array.child);

                if (child_info == .int or child_info == .float) {
                    const arr = &@field(object, field.name);
                    for (arr, 0..) |num, i| {
                        arr[i] = @bitCast(serialize_numeric(num));
                    }
                }

                @memcpy(slice[cur_index .. cur_index + @sizeOf(field_type)], std.mem.sliceAsBytes(&@field(object, field.name)));
                cur_index += @sizeOf(field_type);
            },
            else => @compileError("Field type not supported"),
        }
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
    struct_array_rep_size(
        0,
        get_struct_type_info_from_pointer(@TypeOf(object)).fields,
    )
]u8 {
    const struct_type = get_struct_type_info_from_pointer(@TypeOf(object));
    const size = struct_array_rep_size(0, struct_type.fields);
    var array_representation: [size]u8 = undefined;

    serialize_struct(
        &array_representation,
        0,
        object,
        struct_type,
    );

    // THIS COPIES THE ARRAY COULD BE OPTIMIZED
    return array_representation;
}

fn deserialize_struct(struct_to_fill: anytype, data: []const u8, index: u32) void {
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
                deserialize_struct(
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

    deserialize_struct(struct_to_fill, data, 0);
}

pub const Vector2 = struct { x: f32, y: f32 };

pub const PlayerInfo = struct {
    pos: Vector2,
    id: i32,
    list: [4]u16,
    name: []const u8,
};

test "serializer" {
    var player_info = PlayerInfo{
        .pos = .{
            .x = 10,
            .y = 20,
        },
        .id = 100,
        .list = .{ 1, 2, 3, 4 },
        .name = "test",
    };

    // const alloc = std.testing.allocator;
    // const str = try alloc.alloc(u8, 4);
    // defer alloc.free(player_info.name);

    // str.* = "test";
    // player_info.name = str;

    const serialized = serialize(&player_info);

    std.debug.print("\n{any}\n", .{serialized});

    var deserialized: PlayerInfo = undefined;
    deserialize(&deserialized, &serialized);

    std.debug.print("\nx: {d} y: {d}\nid: {d}\nlist: {any}\nname: {s}\n", .{ deserialized.pos.x, deserialized.pos.y, deserialized.id, deserialized.list, deserialized.name });
}
