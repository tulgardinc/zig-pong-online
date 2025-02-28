const std = @import("std");
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});
const game = @import("game.zig");

const BG_HOVER = r.Color{ .a = 255, .b = 200, .g = 200, .r = 200 };
const BG_COLOR = r.Color{ .a = 255, .b = 150, .g = 150, .r = 150 };

current_selection: *?u8,
rectangle: r.Rectangle,
filled: u8 = 0,
key: u8,

const Self = @This();

pub fn update(self: *Self, buffer: [:0]u8, game_state: *game.GameState) void {
    var ss_rect = self.rectangle;
    const ss_pos = r.GetWorldToScreen2D(r.Vector2{ .x = self.rectangle.x, .y = self.rectangle.y }, game_state.camera);
    ss_rect.x = ss_pos.x;
    ss_rect.y = ss_pos.y;
    const mouse_on_box = r.CheckCollisionPointRec(r.GetMousePosition(), ss_rect);

    if (self.current_selection.* == self.key) {
        r.DrawRectangleRec(self.rectangle, BG_HOVER);
        const input = r.GetCharPressed();

        const char_buffer: [1]u8 = .{@intCast(input)};

        if (input > 0 and self.filled < buffer.len - 1) {
            std.debug.print("pressed: {s}\n", .{char_buffer});
            buffer[self.filled] = @intCast(input);
            self.filled += 1;
        } else if (self.filled > 0 and r.IsKeyPressed(r.KEY_BACKSPACE)) {
            self.filled -= 1;
            buffer[self.filled] = 0;
        }
    } else {
        if (mouse_on_box) {
            r.DrawRectangleRec(self.rectangle, BG_HOVER);

            if (r.IsMouseButtonPressed(r.MOUSE_BUTTON_LEFT)) {
                self.current_selection.* = self.key;
            }
        } else {
            r.DrawRectangleRec(self.rectangle, BG_COLOR);
        }
    }

    r.DrawText(
        buffer.ptr,
        @intFromFloat(self.rectangle.x + 5),
        @intFromFloat(self.rectangle.y + self.rectangle.height / 2.0 - 15.0),
        30,
        r.RAYWHITE,
    );
}
