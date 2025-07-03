//! BSD 3-Clause License
//!
//! Copyright (c) raptodb
//! Copyright (c) Andrea Vaccaro
//! All rights reserved.
//!
//! Redistribution and use in source and binary forms, with or without
//! modification, are permitted provided that the following conditions are met:
//!
//! 1. Redistributions of source code must retain the above copyright notice, this
//!    list of conditions and the following disclaimer.
//!
//! 2. Redistributions in binary form must reproduce the above copyright notice,
//!    this list of conditions and the following disclaimer in the documentation
//!    and/or other materials provided with the distribution.
//!
//! 3. Neither the name of the copyright holder nor the names of its
//!    contributors may be used to endorse or promote products derived from
//!    this software without specific prior written permission.
//!
//! THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//! AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//! IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//! DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
//! FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//! DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//! SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//! CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//! OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//! OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//!
//! It contains the implementation of client.

const std = @import("std");

/// Limits of 512 MiB for READ
const MAXFLOW = 1024 * 1024 * 512;

/// Supported versions
pub const RAPTO_VERSION = "0.1.0";
pub const CLIENT_VERSION = "0.1.0";

pub const Commands = enum(u8) {
    PING,

    SET,
    UPDATE,
    RENAME,

    GET,
    TYPE,
    CHECK,
    COUNT,
    LIST,

    TOUCH,
    HEAD,
    TAIL,
    SHEAD,
    STAIL,
    SORT,

    FREQ,
    LAST,
    IDLE,
    LEN,
    SIZE,
    MEM,
    DB,

    DUMP,
    RESTORE,
    ERASE,
    DEL,
    SAVE,
    COPY,

    DOWN,

    /// Parses text command to enum.
    pub fn parse(noalias command: []const u8) ?Commands {
        var i: u8 = 0;
        while (i < 29) : (i += 1) {
            const tag = @as(Commands, @enumFromInt(i));
            if (std.ascii.eqlIgnoreCase(command, @tagName(tag)))
                return tag;
        }

        return null;
    }
};

pub const Query = struct {
    const Self = @This();

    raw_query: []const u8 = undefined,
    command: Commands = undefined,
    args: []const u8 = undefined,

    pub const TextParsingError = error{ EmptyQuery, CommandNotFound, OutOfMemory };

    /// Parses query from text.
    /// Query must be freed with self.free().
    pub fn fromText(allocator: std.mem.Allocator, raw_query: []const u8) TextParsingError!Self {
        const trimmed = std.mem.trim(u8, raw_query, " ");
        if (trimmed.len == 0) {
            @branchHint(.unlikely);
            return error.EmptyQuery;
        }
        const space_index = std.mem.indexOfScalar(u8, trimmed, ' ') orelse trimmed.len;

        return fromEnum(
            allocator,
            Commands.parse(trimmed[0..space_index]) orelse return error.CommandNotFound,
            if (space_index < trimmed.len) trimmed[space_index + 1 ..] else null,
        );
    }

    /// Parses query from enum and optional arguments.
    /// This implementation is faster than fromText().
    /// Query must be freed with self.free().
    pub fn fromEnum(allocator: std.mem.Allocator, command: Commands, args: ?[]const u8) error{OutOfMemory}!Self {
        var q = Self{};

        q.args = try allocator.dupe(u8, args orelse "");
        q.command = command;
        q.raw_query = try std.fmt.allocPrint(allocator, "{s} {s}", .{ @tagName(command), q.args });

        return q;
    }

    /// Parses query in comptime.
    pub fn fromComptime(comptime command: Commands, comptime args: ?[]const u8) Self {
        comptime {
            var q = Self{};

            q.args = args orelse "";
            q.command = command;
            q.raw_query = std.fmt.comptimePrint("{s} {s}", .{ @tagName(command), q.args });

            return q;
        }
    }

    /// Same as self.raw_query for conventional purpose.
    /// Returns query as text to send directly to server.
    pub inline fn getQuery(self: Self) []const u8 {
        return self.raw_query;
    }

    /// Frees query.
    pub fn free(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.raw_query);
    }
};

pub const Client = struct {
    const Self = @This();

    stream: *Stream = undefined,

    /// Initializes client and connect to server.
    pub fn init(
        allocator: std.mem.Allocator,
        address: std.net.Address,
        name: []const u8,
        deadline: struct { readms: ?u32, writems: ?u32 },
    ) !Self {
        const stream = std.net.tcpConnectToAddress(address) catch return error.ConnectError;

        var c = Client{};
        c.stream = try Stream.init(allocator, stream.handle);

        try c.stream.disableNagle();

        if (deadline.readms) |ms| try c.stream.setReadDeadline(ms);
        if (deadline.writems) |ms| try c.stream.setWriteDeadline(ms);

        // check compatibility by version
        try c.stream.write(RAPTO_VERSION);
        const response = try c.stream.read(allocator);
        defer allocator.free(response);
        if (!std.mem.eql(u8, response, "OK")) @panic(response);

        // send conventional client name
        try c.stream.write(name);

        return c;
    }

    /// Sends query and return the response.
    /// If bench is enabled, returns as second parameter
    /// the latency of response in ns.
    pub fn sendQuery(self: *Self, allocator: std.mem.Allocator, query: Query, comptime bench: bool) !struct { []const u8, ?u64 } {
        const msg = query.getQuery();

        var timer: std.time.Timer = if (bench)
            std.time.Timer.start() catch unreachable
        else
            undefined;

        try self.stream.write(msg);
        const response = try self.stream.read(allocator);

        return .{
            response,
            if (bench) timer.read() else null,
        };
    }

    /// Closes client stream.
    pub fn deinit(self: *Self) void {
        self.stream.close();
    }
};

/// Stream is an alternative of std.net.Stream with
/// length management and deadline configs.
const Stream = struct {
    const Self = @This();

    pub const ReadError = std.posix.ReadError || error{ OutOfMemory, InvalidLength, EndOfStream };
    pub const WriteError = std.posix.WriteError;

    reader: std.io.Reader(*Self, std.posix.ReadError, rawRead) = undefined,
    writer: std.io.Writer(*Self, std.posix.WriteError, rawWrite) = undefined,

    /// File descriptor for socket
    handle: std.posix.socket_t,

    /// Initializes Stream with posix file descriptor.
    pub fn init(allocator: std.mem.Allocator, handle: std.posix.socket_t) error{OutOfMemory}!*Stream {
        var s = try allocator.create(Stream);
        s.* = Stream{ .handle = handle };
        s.reader = std.io.Reader(*Stream, std.posix.ReadError, rawRead){ .context = s };
        s.writer = std.io.Writer(*Stream, std.posix.WriteError, rawWrite){ .context = s };
        return s;
    }

    fn rawRead(self: *Self, buf: []u8) std.posix.ReadError!usize {
        return std.posix.read(self.handle, buf);
    }

    fn rawWrite(self: *Self, buf: []const u8) std.posix.WriteError!usize {
        return std.posix.write(self.handle, buf);
    }

    /// Reads from stream. The buf is discarded if
    /// its length is 0 or over MAXFLOW.
    pub fn read(self: *Self, allocator: std.mem.Allocator) ReadError![]u8 {
        var buflen: [8]u8 = undefined;
        const bufsize = try self.reader.readAll(&buflen);
        if (bufsize == 0) return error.ConnectionResetByPeer;
        if (bufsize != 8) return error.EndOfStream;

        var len = std.mem.readInt(u64, &buflen, .little);
        if (len == 0 or len > MAXFLOW)
            return error.InvalidLength;

        const buf: []u8 = try allocator.alloc(u8, len);
        // receive buf according to length
        len = try self.reader.readAll(buf);

        return buf[0..len];
    }

    /// Writes to stream.
    pub fn write(self: *Self, buf: []const u8) WriteError!void {
        if (buf.len == 0) return;

        // send length of buf
        try self.writer.writeInt(u64, buf.len, .little);
        // send buf
        try self.writer.writeAll(buf);
    }

    /// Disables Nagle's algorithm.
    /// Optimizes network performance.
    pub fn disableNagle(self: *Self) error{SocketConfig}!void {
        const val: u32 = 1;
        std.posix.setsockopt(
            self.handle,
            std.posix.IPPROTO.TCP,
            std.posix.TCP.NODELAY,
            @as([*]const u8, @ptrCast(&val))[0..4],
        ) catch return error.SocketConfig;
    }

    /// Sets the timeout for read function.
    /// Accepts milliseconds parameter.
    pub fn setReadDeadline(self: *Self, ms: u32) error{SocketConfig}!void {
        const opt = std.posix.timeval{
            .sec = @intCast(@divTrunc(ms, std.time.ms_per_s)),
            .usec = @intCast(@mod(ms, std.time.ms_per_s)),
        };

        std.posix.setsockopt(
            self.handle,
            std.posix.SOL.SOCKET,
            std.posix.SO.RCVTIMEO,
            std.mem.toBytes(opt)[0..],
        ) catch return error.SocketConfig;
    }

    /// Sets the timeout for write function.
    /// Accepts milliseconds parameter.
    pub fn setWriteDeadline(self: *Self, ms: u32) error{SocketConfig}!void {
        const opt = std.posix.timeval{
            .sec = @intCast(@divTrunc(ms, std.time.ms_per_s)),
            .usec = @intCast(@mod(ms, std.time.ms_per_s)),
        };

        std.posix.setsockopt(
            self.handle,
            std.posix.SOL.SOCKET,
            std.posix.SO.SNDTIMEO,
            std.mem.toBytes(opt)[0..],
        ) catch return error.SocketConfig;
    }

    /// Closes stream.
    pub fn close(self: Self) void {
        std.posix.close(self.handle);
    }
};
