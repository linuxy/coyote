# coyote
a small poc web framework w/ jinja2 bolted onto iwnet

Builds against zig 0.11.0-dev.944+a193ec432+

```git clone --recursive https://github.com/linuxy/coyote.git```

To build:
* zig build iwnet
* zig build

Example:
```Zig
const std = @import("std");
const log = std.log.scoped(.model);
const Coyote = @import("coyote");
const Db = Coyote.Db;
pub const Models = @import("./models/export.zig"); //must be named Models

pub fn main() !void {
    var coyote = try Coyote.init();
    defer coyote.deinit();
    try coyote.templates("examples/templates/");
    try coyote.database(.{.host = "localhost",
                          .port = 5434,
                          .user = "test",
                          .pass = "test",
                          .db = "testdb"});
    try coyote.config(.{.listen = "localhost",
                        .port = 8080});
    try coyote.run();
}

pub const coyote_user = struct { //must have coyote_ prefix
    const Self = @This();

    route: []const u8 = "/user",
    template: []const u8 = "user.html",
    flags: u32 = (Coyote.Post | Coyote.Put | Coyote.Get),
    handler: fn(req: Coyote.Request, data: Coyote.Data) u32 = handler,

    pub fn handler(req: Coyote.Request, data: Coyote.Data) u32 {
        var user = Models.User{.username = try Coyote.formValue(req, "user"),
                        .hashedpass = try Coyote.formValue(req, "password"),
                        .email = try Coyote.formValue(req, "email")};
        try Db.save(user);
        var rendered = Coyote.render("user.html", .{.object = user.username, .status = "created successfully"});
        try Coyote.response(req, 200, "text/plain", rendered.data, rendered.len, data);
        return Coyote.Processed;
    }
};
```
