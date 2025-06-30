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
        "BENCHMARKING-CLIENT",
        .{ .readms = null, .writems = null },
    );
    defer client.deinit();

    try benchmark(allocator, &client);
}

fn benchmark(allocator: std.mem.Allocator, client: *Client) !void {
    @setEvalBranchQuota(std.math.maxInt(u32));

    // ISET
    var iset_bench: [2000]u64 = undefined;
    inline for (0..2000) |i| {
        const query = comptime Query.fromComptime(
            .ISET,
            std.fmt.comptimePrint("key-i{d} {d}", .{ i, i }),
        );

        _, const latency = try client.sendQuery(allocator, query, true);
        iset_bench[i] = latency.?;
    }

    // DSET
    var dset_bench: [2000]u64 = undefined;
    inline for (0..2000) |i| {
        const query = comptime Query.fromComptime(
            .DSET,
            std.fmt.comptimePrint("key-d{d} {d}", .{ i, i }),
        );

        _, const latency = try client.sendQuery(allocator, query, true);
        dset_bench[i] = latency.?;
    }

    // SSET
    var sset_bench: [2000]u64 = undefined;
    inline for (0..2000) |i| {
        const query = comptime Query.fromComptime(
            .SSET,
            std.fmt.comptimePrint("key-s{d} {d}", .{ i, i }),
        );

        _, const latency = try client.sendQuery(allocator, query, true);
        sset_bench[i] = latency.?;
    }

    // GET
    var get_bench: [6000]u64 = undefined;
    inline for (0..2000) |i| {
        const queryi = comptime Query.fromComptime(
            .GET,
            std.fmt.comptimePrint("key-i{d} {d}", .{ i, i }),
        );
        const queryd = comptime Query.fromComptime(
            .GET,
            std.fmt.comptimePrint("key-d{d} {d}", .{ i, i }),
        );
        const querys = comptime Query.fromComptime(
            .GET,
            std.fmt.comptimePrint("key-s{d} {d}", .{ i, i }),
        );

        _, const latencyi = try client.sendQuery(allocator, queryi, true);
        _, const latencyd = try client.sendQuery(allocator, queryd, true);
        _, const latencys = try client.sendQuery(allocator, querys, true);
        get_bench[i] = latencyi.?;
        get_bench[i + 1] = latencyd.?;
        get_bench[i + 2] = latencys.?;
    }

    // log benchmark of ISET
    {
        const min, const max = std.mem.minMax(u64, &iset_bench);
        const avg = average(&iset_bench);
        std.debug.print("ISET: min={d}ns max={d}ns avg={d}ns\n", .{ min, max, avg });
    }
    // log benchmark of DSET
    {
        const min, const max = std.mem.minMax(u64, &dset_bench);
        const avg = average(&dset_bench);
        std.debug.print("DSET: min={d}ns max={d}ns avg={d}ns\n", .{ min, max, avg });
    }
    // log benchmark of SSET
    {
        const min, const max = std.mem.minMax(u64, &sset_bench);
        const avg = average(&sset_bench);
        std.debug.print("SSET: min={d}ns max={d}ns avg={d}ns\n", .{ min, max, avg });
    }
    // log benchmark of GET
    {
        const min, const max = std.mem.minMax(u64, &get_bench);
        const avg = average(&get_bench);
        std.debug.print("GET: min={d}ns max={d}ns avg={d}ns\n", .{ min, max, avg });
    }
}

fn average(slice: []const u64) u64 {
    var sum: u64 = 0;
    for (slice[1..]) |item| sum += item;
    return std.math.divFloor(u64, sum, slice.len) catch unreachable;
}
