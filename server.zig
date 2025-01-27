const std = @import("std");
const os = std.os;
const system = os.linux;
const mem = std.mem;
const net = std.net;

const BindError = error{
    BindFailed,
    AddressInUse,
    PermissionDenied,
};

const ListenError = error{
    ListenFailed,
    PermissionDenied,
};

const AcceptError = error{
    WouldBlock,
    BadFileDescriptor,
    ConnectionAborted,
    Interrupted,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    AcceptFailed,
};

pub const HttpServer = struct {
    socket_handle: i32,

    pub fn create() !HttpServer { // returns server or error
        const fd = system.socket(
            system.AF.INET,
            system.SOCK.STREAM,
            0,
        );

        return HttpServer{
            .socket_handle = @intCast(fd),
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

        const result = system.bind(
            self.socket_handle,
            @ptrCast(&sock_addr), // casting the pointer to required type
            @sizeOf(system.sockaddr.in),
        );

        if (@as(i64, @bitCast(result)) < 0) {
            const err_num = -@as(i64, @bitCast(result));
            switch (err_num) {
                98 => return BindError.AddressInUse, // EADDRINUSE
                13 => return BindError.PermissionDenied, // EACCES
                else => {
                    std.debug.print("bind failed dawg - error number: {}/n", .{err_num});
                    return error.BindFailed;
                },
            }
        }
    }

    pub fn accept(self: HttpServer) !usize {
        var addr: system.sockaddr = undefined;
        var addr_len: system.socklen_t = @sizeOf(system.sockaddr);

        const new_socket = system.accept(
            self.socket_handle,
            &addr,
            &addr_len,
        );

        if (@as(i64, @bitCast(new_socket)) < 0) {
            const err_num = -@as(i64, @bitCast(new_socket));
            switch (err_num) {
                11 => return AcceptError.WouldBlock, // EAGAIN/EWOULDBLOCK
                9 => return AcceptError.BadFileDescriptor, // EBADF
                103 => return AcceptError.ConnectionAborted, // ECONNABORTED
                4 => return AcceptError.Interrupted, // EINTR
                24 => return AcceptError.ProcessFdQuotaExceeded, // EMFILE
                23 => return AcceptError.SystemFdQuotaExceeded, // ENFILE
                else => {
                    std.debug.print("accept failed - error number: {}\n", .{err_num});
                    return error.AcceptFailed;
                },
            }
        } else {
            return new_socket;
        }
    }

    pub fn listen(self: *HttpServer) !void {
        // Mark socket as passive listener
        // 128 = maximum length of pending connections queue
        const result = system.listen(self.socket_handle, 128);

        if (@as(i64, @bitCast(result)) < 0) {
            const err_num = -@as(i64, @bitCast(result));
            switch (err_num) {
                13 => return ListenError.PermissionDenied, // EACCES
                else => {
                    std.debug.print("Listen failed with error number: {}\n", .{err_num});
                    return ListenError.ListenFailed;
                },
            }
        }
    }

    pub fn deinit(self: *HttpServer) void {
        const result = system.close(self.socket_handle);
        if (@as(i64, @bitCast(result)) < 0) {
            const err_num = -@as(i64, @bitCast(result));
            std.debug.print("Close failed with error number: {}\n", .{err_num});
        }
    }
};

pub fn main() !void {
    var server = try HttpServer.create();
    defer server.deinit();
    const port: u16 = 8080;

    server.bind(port) catch |err| {
        switch (err) {
            error.AddressInUse => {
                std.debug.print("Port {} is already in use\n", .{port});
                return err;
            },
            error.PermissionDenied => {
                std.debug.print("Permission denied when binding to port {}\n", .{port});
                return err;
            },
            error.BindFailed => {
                std.debug.print("Failed to bind to port {}\n", .{port});
                return err;
            },
        }
    };

    server.listen() catch |err| {
        switch (err) {
            error.PermissionDenied => {
                std.debug.print("Permission denied when trying to listen\n", .{});
                return err;
            },
            error.ListenFailed => {
                std.debug.print("Failed to start listening\n", .{});
                return err;
            },
        }
    };

    while (true) {
        const client_socket = try server.accept();
        const socket_number = @as(i32, @intCast(client_socket));
        defer _ = system.close(socket_number);

        //read from client socket
        var buffer: [1024]u8 = undefined;
        const bytes_read = system.read(socket_number, &buffer, buffer.len);

        std.debug.print("Received: {s}\n", .{buffer[0..bytes_read]});

        // Send a basic response
        const response = "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello, World!\n";
        _ = system.write(socket_number, response, response.len);
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Hello, world!\n", .{});
    try stdout.print("server listening on port {}", .{port});
}
