const std = @import("std");
pub const jinja = @import("jinja");
pub const http = @import("iwnet");

const log = std.log.scoped(.coyote);

pub const Coyote = @This();
pub const Data = ?*anyopaque;
pub const Request = [*c]http.iwn_wf_req;
pub const Get = http.IWN_WF_GET;
pub const Put = http.IWN_WF_PUT;
pub const Post = http.IWN_WF_POST;
pub const All = http.IWN_WF_METHODS_ALL;
pub const Processed = http.IWN_WF_RES_PROCESSED;

var spec: http.iwn_wf_server_spec = undefined;
var data: ?*anyopaque = undefined;
var allocator = std.heap.c_allocator;

//separate this by view? namespace?
pub export var jinja_env: ?*anyopaque = undefined;

var act = std.os.Sigaction{
    .handler = .{.sigaction = signal_handler },
    .mask = std.os.empty_sigset,
    .flags = 0,
};

pub fn signal_handler(sig: i32, sig_info: *const std.os.siginfo_t, ctx_ptr: ?*const anyopaque) callconv(.C) void {
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
    return Coyote{};
}

pub fn templates(self: *Coyote, directory: [*:0]const u8) !void {
    jinja_env = jinja.init_environment(directory);
    _ = self;
}

pub fn render(path: [*:0] const u8, vars: anytype) [:0]const u8 {
    var template = jinja.get_template(jinja_env, path);
    var vars_array: [@typeInfo(@TypeOf(vars)).Struct.fields.len * 2][*:0]const u8 = undefined;

    var i: usize = 0;
    inline for (std.meta.fields(@TypeOf(vars))) |member| {
        log.info("member name: {s} value: {s} total: {}, idx: {}", .{member.name, @field(vars, member.name), @typeInfo(@TypeOf(vars)).Struct.fields.len, i});
        vars_array[i] = @ptrCast([*:0]const u8, member.name);
        vars_array[i + 1] = @ptrCast([*:0]const u8, @field(vars, member.name));
        i += 2;
    }
    var rendered = jinja.render(@ptrCast(?*anyopaque, template), @as(c_int, @typeInfo(@TypeOf(vars)).Struct.fields.len * 2), @ptrCast([*c][*:0]const u8, &vars_array));
    var rendered_utf8 = std.mem.span(jinja.PyUnicode_AsUTF8(rendered));

    return rendered_utf8;
}

pub fn response(req: [*c]http.iwn_wf_req, code: u32, mime: [:0]const u8, body: [:0]const u8, user_data: ?*anyopaque) !void {
    _ = http.iwn_http_response_printf(req.*.http, @intCast(c_int, code), mime, "%.*s\n",
                                body.len, @ptrCast([*:0]const u8, body), @ptrCast([*c]const u8, &user_data));
}

//Dynamically build these from loaded template directory
pub fn routes(self: *Coyote) !void {
    var route: http.struct_iwn_wf_route = undefined;
    var route_pattern: [*:0]const u8 = undefined;
    var route_handler: fn(req: Request, data: Data) callconv(.C) c_int = undefined;
    var route_flags: u32 = undefined;

    inline for (@typeInfo(@import("root")).Struct.decls) |decl| {
        const idx = comptime std.mem.indexOf(u8, decl.name, "coyote_");
        if (decl.is_pub and comptime idx != null) {
            const fn_name = decl.name[idx.?+7..];
            _ = fn_name;
            log.info("found decl, {s}", .{decl.name});
            inline for (std.meta.fields(@field(@import("root"), decl.name))) |member| {
                log.info("found member, {s}", .{member.name});
                var member_type = @field(@import("root"), decl.name){};
                if(std.mem.eql(u8, member.name, "route")) {
                    route_pattern = member_type.route;
                    log.info("found route_pattern, {s}", .{route_pattern});
                }
                if(std.mem.eql(u8, member.name, "handler")) {
                    route_handler = member_type.handler;
                    log.info("found handler, {s}", .{route_handler});
                }
                if(std.mem.eql(u8, member.name, "flags")) {
                    route_flags = member_type.flags;
                    log.info("found flags, {}", .{route_flags});
                }
            }
            if(route_pattern != undefined) {
                route = std.mem.zeroes(http.struct_iwn_wf_route);
                route.pattern = route_pattern;
            }

            if(route_handler != undefined)
                route.handler = route_handler;

            if(route_flags != 0)
                route.flags = route_flags;

            route.ctx = http.ctx;
            route.user_data = @ptrCast(*anyopaque, &data);
            try ec(http.iwn_wf_route(@ptrCast([*c]http.struct_iwn_wf_route, &route), 0));
        }
    }
    _ = self;
}

//Zero the struct and fill opportunistically
pub fn config(self: *Coyote, conf: anytype) !void {
    try ec(http.iwn_poller_create(0, 0, &http.poller));
    spec = std.mem.zeroes(http.iwn_wf_server_spec);

    inline for (std.meta.fields(@TypeOf(conf))) |member| {
        @field(spec, member.name) = @field(conf, member.name);
    }

    spec.poller = http.poller;
    _ = self;
}

//Create IWN server and poll
pub fn run(self: *Coyote) !void {
    std.os.sigaction(std.os.SIG.INT, &act, null);
    http.iwn_wf_route_print(http.ctx.*.root, http.stderr);
    try ec(http.iwn_wf_server(&spec, http.ctx));
    http.iwn_poller_poll(http.poller);
    _ = self;
}

//Destruct any allocations
pub fn deinit(self: *Coyote) void {
    jinja.free_environment(jinja_env);
    log.info("deinit()", .{});
    _ = self;
}

//Build these with routes
pub fn _handle_echo(req: [*c]http.iwn_wf_req, user_data: ?*anyopaque) callconv(.C) c_int {
    //std.log.info("Echo handler called\n", .{});
    _ = http.iwn_http_response_printf(req.*.http, 200, "text/plain", "%.*s\n",
                                @intCast(c_int, req.*.body_len), req.*.body, @ptrCast([*c]const u8, &user_data));
    return http.IWN_WF_RES_PROCESSED;
}

pub fn ec(err: u64) !void {
    switch(err) {
        0 => return,
        else => return error.IWNetError,
    }
}

//Create error handler, error struct
//Config JSON or KV loader
//MVC / MVVM / MVT architecture https://www.tutorialspoint.com/django/django_models.htm
//Create ORM, comptime?
//Build IWNet
//Sessions
//Hot reload + inotify
//REST example
//Swagger generator
//Migrations
//Emailer