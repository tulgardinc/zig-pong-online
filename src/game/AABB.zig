const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const consts = @import("constants.zig");

right: f32,
left: f32,
top: f32,
bottom: f32,

const Self = @This();

pub fn init(pos_ptr: *const r.Vector2, width: f32, length: f32) Self {
    return .{
        .right = pos_ptr.x + width,
        .top = pos_ptr.y,
        .bottom = pos_ptr.y + length,
        .left = pos_ptr.x,
    };
}

pub fn check_collision(self: *const Self, other_aabb_ptr: *const Self) bool {
    return self.right > other_aabb_ptr.left and self.left < other_aabb_ptr.right and self.top < other_aabb_ptr.bottom and self.bottom > other_aabb_ptr.top;
}

pub fn get_collision_vector(self: *const Self, other_aabb_ptr: *const Self) ?r.Vector2 {
    if (self.check_collision(other_aabb_ptr)) {
        const overlap_x = @min(self.right - other_aabb_ptr.left, other_aabb_ptr.right - self.left);
        const overlap_y = @min(self.bottom - other_aabb_ptr.top, other_aabb_ptr.bottom - self.top);

        if (overlap_x < overlap_y) {
            if (self.left > other_aabb_ptr.left) {
                return r.Vector2Scale(consts.VEC_RIGHT, overlap_x);
            } else {
                return r.Vector2Scale(consts.VEC_LEFT, overlap_x);
            }
        } else {
            if (self.top > other_aabb_ptr.top) {
                return r.Vector2Scale(consts.VEC_DOWN, overlap_y);
            } else {
                return r.Vector2Scale(consts.VEC_UP, overlap_y);
            }
        }
    } else {
        return null;
    }
}
