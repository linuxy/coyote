const std = @import("std");
const log = std.log.scoped(.echo);
const Coyote = @import("coyote");

pub fn main() !void {
    var coyote = try Coyote.init();
    defer coyote.deinit();
    try coyote.templates("examples/templates/");
    try coyote.routes();
    try coyote.config(.{.listen = "localhost",
                        .port = 8080});
    try coyote.run();
}

pub const coyote_index = struct {
    const Self = @This();

    route: [*:0]const u8 = "/index",
    template: [*:0]const u8 = "index.html",
    handler: Coyote.Handler(fn(req: Coyote.Request, data: Coyote.Data) u32),
    flags: u32 = Coyote.All,

    pub fn handler(req: Coyote.Request, data: Coyote.Data) callconv(.C) c_int {
        var rendered = Coyote.render("index.html", .{.name = "Zero", .surname = "Ziguana"});
        try Coyote.response(req, 200, "text/plain", rendered, data);
        return Coyote.Processed;
    }
};