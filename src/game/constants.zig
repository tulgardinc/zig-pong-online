const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

pub const VEC_RIGHT = r.Vector2{ .x = 1, .y = 0 };
pub const VEC_LEFT = r.Vector2{ .x = -1, .y = 0 };
pub const VEC_UP = r.Vector2{ .x = 0, .y = -1 };
pub const VEC_DOWN = r.Vector2{ .x = 0, .y = 1 };
