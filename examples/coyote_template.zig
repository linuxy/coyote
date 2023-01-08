const std = @import("std");
const log = std.log.scoped(.echo);
const Coyote = @import("coyote");

pub fn main() !void {
    var coyote = try Coyote.init();
    defer coyote.deinit();
    try coyote.templates("examples/templates/");
    try coyote.config(.{
        .listen = "localhost",
        .port = 8080,
    });
    try coyote.run();
}

pub const coyote_index = struct {
    const Self = @This();

    route: []const u8 = "/index",
    template: []const u8 = "index.html",
    handler: fn (req: Coyote.Request, data: Coyote.Data) u32 = handler,
    flags: u32 = Coyote.All,

    pub fn handler(req: Coyote.Request, data: Coyote.Data) u32 {
        var rendered = Coyote.render("index.html", .{ .name = "Zero", .surname = "Ziguana" });
        defer rendered.deinit();
        try Coyote.response(req, 200, "text/plain", rendered.data.ptr, rendered.data.len, data);
        return Coyote.Processed;
    }
};
