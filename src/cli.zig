const std = @import("std");
const Client = @import("client.zig").Client;
const Query = @import("client.zig").Query;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var client = try Client.init(
        allocator,
        try std.net.Address.parseIp4("127.0.0.1", 55555),
        "CLI",
        .{ .readms = null, .writems = null },
    );
    defer client.deinit();

    while (true) {
        std.debug.print("rapto> ", .{});
        const input = try std.io.getStdIn().reader().readUntilDelimiterAlloc(allocator, '\n', 10000);

        var query = try Query.fromText(allocator, input);
        const res, const rl = try client.sendQuery(allocator, query, true);
        defer query.free(allocator);

        const latency = @as(f64, @floatFromInt(rl.?)) / 1e9;
        std.debug.print("{s} (latency={d:.6}s)\n", .{ res, latency });
    }
}
