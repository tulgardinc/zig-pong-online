const std = @import("std");
const game = @import("game.zig");
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const BG_COLOR = r.Color{ .a = 255, .b = 200, .g = 200, .r = 200 };
const BG_HOVER = r.Color{ .a = 255, .b = 150, .g = 150, .r = 150 };

rectangle: r.Rectangle,
text: []const u8,
on_click: *const fn (*game.GameState) void,

const Self = @This();

pub fn update(self: *Self, game_state_ptr: *game.GameState) void {
    var ss_rect = self.rectangle;
    const ss_pos = r.GetWorldToScreen2D(r.Vector2{ .x = self.rectangle.x, .y = self.rectangle.y }, game_state_ptr.camera);
    ss_rect.x = ss_pos.x;
    ss_rect.y = ss_pos.y;
    const mouse_on_button = r.CheckCollisionPointRec(r.GetMousePosition(), ss_rect);

    if (mouse_on_button) {
        r.DrawRectangleRec(self.rectangle, BG_COLOR);

        if (r.IsMouseButtonPressed(r.MOUSE_BUTTON_LEFT)) {
            self.on_click(game_state_ptr);
        }
    } else {
        r.DrawRectangleRec(self.rectangle, BG_HOVER);
    }

    const text_width: f32 = @floatFromInt(r.MeasureText(@ptrCast(self.text), 30));
    r.DrawText(
        @ptrCast(self.text),
        @intFromFloat(self.rectangle.x + self.rectangle.width / 2.0 - text_width / 2.0),
        @intFromFloat(self.rectangle.y + self.rectangle.height / 2.0 - 15.0),
        30,
        r.RAYWHITE,
    );
}
