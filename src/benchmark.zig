const std = @import("std");

const Client = @import("client.zig").Client;
const Query = @import("client.zig").Query;
const VERSION = @import("client.zig").CLIENT_VERSION;

const epochs: u32 = 2000;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var client = try Client.init(
        allocator,
        try std.net.Address.parseIp4("127.0.0.1", 55555),
        "BENCHMARKING-CLIENT",
        .{ .readms = null, .writems = null },
    );
    defer client.deinit();

    try benchmark(allocator, &client);
}

fn benchmark(allocator: std.mem.Allocator, client: *Client) !void {
    // test set
    const set_stats = try set_bench(allocator, client, epochs);
    try eraseDatabase(allocator, client);

    // test get
    const get_stats = try get_bench(allocator, client, epochs);
    try eraseDatabase(allocator, client);

    std.debug.print("Benchmarks version={s} epochs={d}:\n", .{ VERSION, epochs });
    {
        const min, const max = std.mem.minMax(u64, &set_stats);
        const avg = average(&set_stats);
        std.debug.print("SET: min={d}ns max={d}ns avg={d}ns\n", .{ min, max, avg });
    }
    {
        const min, const max = std.mem.minMax(u64, &get_stats);
        const avg = average(&get_stats);
        std.debug.print("GET: min={d}ns max={d}ns avg={d}ns\n", .{ min, max, avg });
    }
}

fn set_bench(allocator: std.mem.Allocator, client: *Client, comptime qty: u32) ![qty]u64 {
    var iset_stats: [qty]u64 = undefined;

    for (0..qty) |i| {
        const query = try Query.fromEnum(
            allocator,
            .SET,
            try std.fmt.allocPrint(allocator, "key{d} {d}", .{ i, i }),
        );

        _, const latency = try client.sendQuery(allocator, query, true);
        iset_stats[i] = latency.?;
    }

    return iset_stats;
}

fn get_bench(allocator: std.mem.Allocator, client: *Client, comptime qty: u32) ![qty]u64 {
    var get_stats: [qty]u64 = undefined;

    for (0..qty) |i| {
        const query = try Query.fromEnum(
            allocator,
            .GET,
            try std.fmt.allocPrint(allocator, "key{d}", .{i}),
        );

        _, const latency = try client.sendQuery(allocator, query, true);
        get_stats[i] = latency.?;
    }

    return get_stats;
}

fn eraseDatabase(allocator: std.mem.Allocator, client: *Client) !void {
    _, _ = try client.sendQuery(allocator, comptime .fromComptime(.ERASE, null), false);
}

fn average(slice: []const u64) u64 {
    var sum: u64 = 0;
    for (slice[1..]) |item| {
        sum += item;
    }
    return @divFloor(sum, slice.len);
}
