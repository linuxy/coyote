const std = @import("std");

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