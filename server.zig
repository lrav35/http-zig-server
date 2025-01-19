const std = @import("std");
const os = std.os;
const system = os.linux;
const mem = std.mem;
const net = std.net;

pub const HttpServer = struct {
    socket_handle: system.socket_t,

    pub fn create() !HttpServer { // returns server or error
        const socket_handle = try system.socket(
            system.AF.INET,
            system.SOCK.STREAM,
            0,
        );

        return HttpServer{
            .socket_handle = socket_handle,
        };
    }

    pub fn bind(self: *HttpServer, port: u16) !void { // takes HttpServer pointer (address of pointer)
        // set up IPv4 address structure
        var sock_addr = system.sockaddr.in{
            .family = system.AF.INET,
            .port = mem.nativeToBig(u16, port),
            .addr = mem.nativeToBig(u32, 0),
            .zero = [_]u8{0} ** 8, // creates an inferred array of 0's multiplied by 8 -> [0,0,0,0,0,0,0,0]
            // could also use [8]u8{0,0,0,0,0,0,0,0}
        };

        try system.bind(
            self.socket_handle,
            @ptrCast(&sock_addr), // casting the pointer to required type
            @sizeOf(system.sockaddr.in),
        );
    }

    pub fn listen(self: *HttpServer) !void {
        // Mark socket as passive listener
        // 128 = maximum length of pending connections queue
        try system.listen(self.socket_handle, 128);
    }

    pub fn deinit(self: *HttpServer) void {
        system.close(self.socket_handle);
    }
};

pub fn main() !void {
    var server = try HttpServer.create();
    defer server.deinit();
    const port: u16 = 8080;

    try server.bind(port);

    try server.listen();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Hello, world!\n", .{});
    try stdout.print("server listening on port {}", .{port});
}
