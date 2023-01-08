const std = @import("std");
const mustache = @import("mustache");
const http = @import("iwnet");
const db = @import("zq");

const log = std.log.scoped(.coyote);

pub const Coyote = @This();
pub const Data = ?*anyopaque;
pub const Request = [*c]http.iwn_wf_req;
pub const Get = http.IWN_WF_GET;
pub const Put = http.IWN_WF_PUT;
pub const Post = http.IWN_WF_POST;
pub const Head = http.IWN_WF_HEAD;
pub const Delete = http.IWN_WF_DELETE;
pub const Patch = http.IWN_WF_PATCH;
pub const Options = http.IWN_WF_OPTIONS;
pub const Connect = http.IWN_WF_CONNECT;
pub const Trace = http.IWN_WF_TRACE;
pub const All = http.IWN_WF_METHODS_ALL;
pub const Processed = http.IWN_WF_RES_PROCESSED;
pub const Value = http.struct_iwn_val;
pub const Db = @This();

var spec: http.iwn_wf_server_spec = undefined;
var data: ?*anyopaque = undefined;
var allocator = std.heap.c_allocator;
pub var db_engine: ?db.Engine(.postgres) = undefined;
pub var db_conn: ?db.Connection = undefined;

//rework for async // one env per thread
var template_lock: std.Thread.Mutex = .{};
pub var mustache_cache: *std.AutoHashMap(u64, *mustache.Template) = undefined;
var template_directory: []const u8 = undefined;
var cache: ?*Cache = undefined;

var act = std.os.Sigaction{
    .handler = .{ .sigaction = signalHandler },
    .mask = std.os.empty_sigset,
    .flags = 0,
};

pub fn signalHandler(sig: i32, sig_info: *const std.os.siginfo_t, ctx_ptr: ?*const anyopaque) callconv(.C) void {
    http.iwn_poller_shutdown_request(http.poller);
    log.info("Graceful exit requested.", .{});
    _ = sig;
    _ = sig_info;
    _ = ctx_ptr;
}

//Create Coyote handle
pub fn init() !Coyote {
    try ec(http.iw_init());
    try ec(http.iwn_wf_create(0, @ptrCast([*c][*c]http.struct_iwn_wf_ctx, &http.ctx)));

    cache = try allocator.create(Cache);
    cache.?.* = Cache.init();
    return Coyote{};
}

const Cache = struct {
    template: std.StringHashMap(mustache.Template),

    pub fn init() Cache {
        return Cache{
            .template = std.StringHashMap(mustache.Template).init(allocator),
        };
    }
};

var global_fn: ?*const fn (req: Request, data: Data) u32 = undefined;

//This removes the callconv requirement
//TODO: Unpack and repack the Request struct w/ Zig types
pub fn Handler(callback_fn: ?*const fn (req: Request, user_data: Data) u32) ?*const fn (req: Request, user_data: Data) callconv(.C) c_int {
    global_fn = callback_fn;

    const cb = struct {
        pub fn cb(
            req: Request,
            user_data: Data,
        ) callconv(.C) c_int {
            return @intCast(c_int, global_fn.?(req, user_data));
        }
    }.cb;

    return cb;
}

pub fn database(self: *Coyote, conf: anytype) !void {
    db_engine = db.Engine(.postgres).init(allocator, .{
        .host = conf.host,
        .port = conf.port,
        .user = conf.user,
        .pass = conf.pass,
        .db = conf.db,
    });
    _ = self;
}

pub fn save(model: anytype) !void {
    _ = model;
}

pub fn templates(self: *Coyote, directory: []const u8) !void {
    template_directory = directory;
    _ = self;
}

const Rendered = struct {
    data: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.data);
    }
};

//Render templates with value dictionary, supports ?*value, *value, ?value, value
pub fn render(template_name: []const u8, vars: anytype) Rendered {
    const template = cache.?.template.get(template_name) orelse template: {
        log.info("Loading template {s}", .{template_name});
        template_lock.lock(); //TODO: Fix
        defer template_lock.unlock();
        break :template cache.?.template.get(template_name) orelse cache: {
            var path_buffer: [std.fs.MAX_NAME_BYTES]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&path_buffer);
            const path = std.fs.path.join(fba.allocator(), &.{ template_directory, template_name }) catch unreachable;

            var absolute_path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
            const absolute_path = std.fs.cwd().realpath(path, &absolute_path_buffer) catch unreachable;
            const result = mustache.parseFile(allocator, absolute_path, .{}, .{}) catch {
                // TODO: Handle file errors here:
                unreachable;
            };

            const template_cache = switch (result) {
                .success => |template| template,
                .parse_error => |detail| {
                    // TODO: Handle parser errors here:
                    const message = std.fmt.allocPrintZ(allocator, "Template {s} error {s} at lin {}, col {}", .{
                        template_name,
                        @errorName(detail.parse_error),
                        detail.lin,
                        detail.col,
                    }) catch unreachable;
                    return .{ .data = message, .allocator = allocator };
                },
            };

            cache.?.template.put(template_name, template_cache) catch unreachable;
            break :cache template_cache;
        };
    };

    const rendered = mustache.allocRenderZ(allocator, template, vars) catch unreachable;
    return .{ .data = rendered, .allocator = allocator };
}

pub fn response(req: [*c]http.iwn_wf_req, code: u32, mime: []const u8, body: [*c]const u8, body_len: ?usize, user_data: ?*anyopaque) !void {
    _ = http.iwn_http_response_printf(req.*.http, @intCast(c_int, code), @ptrCast([*c]const u8, mime), "%.*s\n", body_len.?, body, @ptrCast([*c]const u8, &user_data));
}

//Dynamically build routes from loaded template directory
pub fn routes(self: *Coyote) !void {
    var route: http.struct_iwn_wf_route = undefined;
    var route_pattern: ?[]const u8 = null;
    var route_handler: ?*const fn (req: Request, data: Data) callconv(.C) c_int = null;
    var route_flags: u32 = undefined;

    inline for (@typeInfo(@import("root")).Struct.decls) |decl| {
        const idx = comptime std.mem.indexOf(u8, decl.name, "coyote_");
        if (decl.is_pub and comptime idx != null) {
            const fn_name = decl.name[idx.? + 7 ..];
            _ = fn_name;
            log.info("found decl, {s}", .{decl.name});
            inline for (std.meta.fields(@field(@import("root"), decl.name))) |member| {
                log.info("found member, {s}", .{member.name});
                comptime var member_type = @field(@import("root"), decl.name){};
                if (std.mem.eql(u8, member.name, "route")) {
                    route_pattern = member_type.route;
                    //log.info("found route_pattern, {s}", .{route_pattern});
                }
                if (std.mem.eql(u8, member.name, "handler")) {
                    route_handler = Handler(member_type.handler);
                    //log.info("found handler, {s}", .{route_handler.?});
                }
                if (std.mem.eql(u8, member.name, "flags")) {
                    route_flags = member_type.flags;
                    log.info("found flags, {}", .{route_flags});
                }
            }

            if (route_pattern != null) {
                route = std.mem.zeroes(http.struct_iwn_wf_route);
                route.pattern = @ptrCast([*:0]const u8, route_pattern.?);
            }

            route.handler = route_handler;
            if (route_flags != 0)
                route.flags = route_flags;

            route.ctx = http.ctx;
            route.user_data = @ptrCast(*anyopaque, &data);
            try ec(http.iwn_wf_route(@ptrCast([*c]http.struct_iwn_wf_route, &route), 0));
        }
    }
    _ = self;
}

pub fn models(self: *Coyote) !void {
    inline for (@typeInfo(@import("root")).Struct.decls) |decl| {
        const found = comptime std.mem.eql(u8, decl.name, "Models");
        if (decl.is_pub and comptime found) {
            log.info("found Models", .{});
            inline for (@typeInfo(@field(@import("root"), decl.name)).Struct.decls) |child| {
                log.info("found Models child, {s}", .{child.name});
                if (child.is_pub) {
                    inline for (@typeInfo(@field(@field(@import("root"), decl.name), child.name)).Struct.decls) |sub| {
                        log.info("found Sub child, {s}", .{sub.name});
                        if (std.mem.eql(u8, sub.name, "Meta")) {
                            //
                        }
                    }
                }
            }
        }
    }
    _ = self;
}

pub fn queryValue(req: Request, key: []const u8) !?[]u8 {
    var value: Value = http.iwn_pair_find_val(&req.*.query_params, @ptrCast([*c]const u8, key), @intCast(isize, key.len));
    if (value.buf != 0) {
        var found = std.mem.sliceTo(value.buf, 0);
        return found;
    }
    return null;
}

pub fn multiQueryValue(req: Request, key: []const u8) !std.ArrayList([]u8) {
    var value_array: std.ArrayList([]u8) = std.ArrayList([]u8).init(allocator);
    var value: Value = http.iwn_pair_find_val(&req.*.query_params, @ptrCast([*c]const u8, key), @intCast(isize, key.len));
    while (value.buf != 0) {
        try value_array.append(std.mem.sliceTo(value.buf, 0));
        if (value.next != 0) {
            value = value.next.*;
        } else {
            break;
        }
    }

    //owner must deinit()
    return value_array;
}

pub fn formValue(req: Request, key: []const u8) !?[]u8 {
    var value: Value = http.iwn_pair_find_val(&req.*.form_params, @ptrCast([*c]const u8, key), @intCast(isize, key.len));
    if (value.buf != 0) {
        var found = std.mem.sliceTo(value.buf, 0);
        return found;
    }
    return null;
}

//Fix?
pub fn multiFormValue(req: Request, key: []const u8) !std.ArrayList([]u8) {
    var value_array: std.ArrayList([]u8) = std.ArrayList([]u8).init(allocator);
    var value: Value = http.iwn_pair_find_val(&req.*.form_params, @ptrCast([*c]const u8, key), @intCast(isize, key.len));
    while (value.buf != 0) {
        try value_array.append(std.mem.sliceTo(value.buf, 0));
        if (value.next != 0) {
            value = value.next.*;
        } else {
            break;
        }
    }

    //owner must deinit()
    return value_array;
}

//Zero the struct and fill opportunistically
pub fn config(self: *Coyote, conf: anytype) !void {
    try ec(http.iwn_poller_create(0, 0, &http.poller));
    spec = std.mem.zeroes(http.iwn_wf_server_spec);
    inline for (std.meta.fields(@TypeOf(conf))) |member| {
        @field(spec, member.name) = @field(conf, member.name);
    }

    spec.poller = http.poller;
    try self.routes();
    try self.models();
}

//Create IWN server and poll
pub fn run(self: *Coyote) !void {
    try std.os.sigaction(std.os.SIG.INT, &act, null);
    http.iwn_wf_route_print(http.ctx.*.root, http.stderr);
    try ec(http.iwn_wf_server(&spec, http.ctx));
    http.iwn_poller_poll(http.poller);
    _ = self;
}

//Destruct any allocations
pub fn deinit(self: *Coyote) void {
    var iter = cache.?.template.iterator();
    while (iter.next()) |kv| {
        kv.value_ptr.deinit(allocator);
    }

    if (db_engine != null)
        db_engine.?.deinit();

    log.info("deinit()", .{});
    _ = self;
}

pub fn ec(err: u64) !void {
    switch (err) {
        0 => return,
        else => return error.IWNetError,
    }
}

//Escape inputs
//Create error handler, error struct
//Config JSON or KV loader
//MVC / MVVM / MVT architecture https://www.tutorialspoint.com/django/django_models.htm
//Create ORM, comptime?
//Build IWNet
//Sessions
//Hot reload + inotify
//REST example
//Swagger generator
//Migrations, zig-yaml + Pyrseas
//Emailer
//Structured logging middleware
