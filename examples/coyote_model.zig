const std = @import("std");
const log = std.log.scoped(.model);
const Coyote = @import("coyote");
const Db = Coyote.Db;

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

pub const User = struct {
    id: ?u32 = null, // id defaults to the primary key
    username: ?[]const u8,
    hashedpass: ?[]const u8,
    email: ?[]const u8,

    // Table Metadata
    pub const Meta = struct {
        pub const table = "users";
        pub const hashedpass_len = 64;
        pub const username_len = 100;
        pub const username_unique = true;
        pub const email_unique = true;
        pub const email_len = 255;
    };
};

pub const coyote_user = struct { 
    const Self = @This();

    route: []const u8 = "/user",
    template: []const u8 = "user.html",
    flags: u32 = (Coyote.Post | Coyote.Put),
    handler: fn(req: Coyote.Request, data: Coyote.Data) u32 = handler,

    pub fn handler(req: Coyote.Request, data: Coyote.Data) u32 {
        var user = User{.username = try Coyote.formValue(req, "user"),
                        .hashedpass = try Coyote.formValue(req, "password"),
                        .email = try Coyote.formValue(req, "email")};
        try Db.save(user);
        var rendered = Coyote.render("user.html", .{.object = user.username, .status = "created successfully"});
        try Coyote.response(req, 200, "text/plain", rendered, data);
        return Coyote.Processed;
    }
};