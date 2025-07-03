# Rapto client for Zig

Lightweight library to use Rapto as client.

## Usage and documentation

Copy `client.zig` on `/src` of your project and import it.

### Examples

```zig
// IMPORTS
const Client = @import("client.zig").Client;
const Query = @import("client.zig").Query;
```

```zig
// bind connection
var client = try Client.init(
    allocator,
    try std.net.Address.parseIp4("127.0.0.1", 55555), // address of server
    "CLI",                                            // conventional name of client
    .{ .readms = 5.0, .writems = null },              // optional deadline
);
defer client.deinit(); // closes stream
```

```zig
// build query
const input = "GET mykey"; // GET can be lowercase
var query = try Query.fromText(allocator, input);

// send query
const res, const latency = try client.sendQuery(
    allocator,
    query,
    true, // enable benchmark
);

assert(latency != null) // if benchmark is enabled

// latency is latency of send and receive of query in ns

std.debug.print("{s}\n", .{res}); // print response of query
```

### Query parsing methods

`@import("client.zig").Query` has different methods as:

| Method | Description |
|--------|-------------|
| `fromText()` | Parses query from text |
| `fromEnum()` | Parses query from command as enum and args as text |
| `fromComptime()` | As `fromEnum()` but in comptime |
| `getQuery()` | Returns raw query as string |
| `free()` | Frees memory. Used after `fromText()` and `fromEnum()` |

> [!WARNING]
> If parsing does not found recognized command, returns `error.CommandNotFound`.

```zig
// parsing examples
.fromText(allocator, "ISET foo 150);
.fromEnum(allocator, .ISET, "foo 150");
.fromComptime(.ISET, "foo 150");
```

## Benchmark

Benchmark can be tested with `zig build benchmark` step command.
This step is already in ReleaseFast mode.

Tested on `system=WSL2 cpu=i7-12700H version=0.1.0`:
```
Benchmarks version=0.1.0 epochs=2000:
SET: min=52615ns max=440281ns avg=92026ns
GET: min=44712ns max=679387ns avg=55844ns
```