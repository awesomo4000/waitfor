const std = @import("std");
const builtin = @import("builtin");

const EXIT_SUCCESS: u8 = 0;
const EXIT_TIMEOUT: u8 = 1;
const EXIT_SIGNAL: u8 = 2;
const EXIT_ERROR: u8 = 3;

const DEFAULT_POLL_MS: u64 = 100;

const Config = struct {
    wait_for_deletion: bool = false,
    timeout_sec: ?f64 = null, // null = wait indefinitely
    paths: []const []const u8 = &.{},
    paths_allocated: usize = 0, // for proper deallocation
};

pub fn main() u8 {
    return run() catch |err| {
        std.debug.print("waitfor: {s}\n", .{@errorName(err)});
        return EXIT_ERROR;
    };
}

fn run() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parseArgs(allocator);
    defer if (config.paths.len > 0) allocator.free(config.paths.ptr[0..config.paths_allocated]);

    if (config.paths.len == 0) {
        printUsage();
        return EXIT_ERROR;
    }

    // Validate paths are non-empty
    for (config.paths) |path| {
        if (path.len == 0) {
            std.debug.print("waitfor: empty path not allowed\n", .{});
            return EXIT_ERROR;
        }
    }

    return try waitForPaths(config);
}

fn parseArgs(allocator: std.mem.Allocator) !Config {
    var config = Config{};

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Count total args for worst-case allocation
    _ = args.skip(); // Skip program name
    var arg_count: usize = 0;
    while (args.next()) |_| {
        arg_count += 1;
    }

    // Allocate for worst case (all args are paths)
    const paths = try allocator.alloc([]const u8, arg_count);
    errdefer allocator.free(paths);
    var path_idx: usize = 0;

    // Re-iterate to parse
    args = try std.process.argsWithAllocator(allocator);
    _ = args.skip(); // Skip program name

    while (args.next()) |arg| {
        if (arg.len > 0 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-d")) {
                config.wait_for_deletion = true;
            } else if (std.mem.eql(u8, arg, "-t")) {
                // Peek at next arg to see if it's a timeout value
                if (args.next()) |next| {
                    if (next.len > 0 and next[0] == '-') {
                        // It's another flag, -t means wait forever
                        config.timeout_sec = 0;
                        // Process this flag inline since we can't push back
                        if (std.mem.eql(u8, next, "-d")) {
                            config.wait_for_deletion = true;
                        } else if (std.mem.eql(u8, next, "-h") or std.mem.eql(u8, next, "--help")) {
                            printUsage();
                            std.process.exit(EXIT_SUCCESS);
                        } else if (std.mem.eql(u8, next, "-t")) {
                            // Another -t, still means wait forever
                            config.timeout_sec = 0;
                        } else {
                            return error.UnknownOption;
                        }
                    } else {
                        // Must be a valid non-negative number
                        const timeout = std.fmt.parseFloat(f64, next) catch {
                            return error.InvalidTimeout;
                        };
                        if (timeout < 0 or std.math.isNan(timeout)) {
                            return error.InvalidTimeout;
                        }
                        config.timeout_sec = timeout;
                    }
                } else {
                    // -t at end of args means wait forever
                    config.timeout_sec = 0;
                }
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                printUsage();
                std.process.exit(EXIT_SUCCESS);
            } else {
                return error.UnknownOption;
            }
        } else {
            paths[path_idx] = arg;
            path_idx += 1;
        }
    }

    // Store actual paths and allocation size
    config.paths = paths[0..path_idx];
    config.paths_allocated = arg_count;
    return config;
}

fn printUsage() void {
    std.debug.print(
        \\Usage: waitfor [-d] [-t timeout] pathname [pathname ...]
        \\
        \\Block until file(s) appear or disappear.
        \\
        \\Options:
        \\  -d          Wait for files to be deleted (disappear)
        \\  -t timeout  Timeout in seconds (0 = wait indefinitely, default)
        \\  -h, --help  Show this help message
        \\
        \\Exit status:
        \\  0  All conditions met
        \\  1  Timeout expired
        \\  2  Interrupted by signal
        \\  3  Error
        \\
    , .{});
}

fn waitForPaths(config: Config) !u8 {
    const start_time = std.time.nanoTimestamp();
    const timeout_ns: ?i128 = if (config.timeout_sec) |t| blk: {
        if (t == 0) break :blk null;
        if (t < 0) return EXIT_ERROR; // negative timeout
        // Check for overflow before conversion (max ~292 years in nanoseconds fits in i128)
        const max_seconds: f64 = @floatFromInt(@as(i128, std.math.maxInt(i64)));
        if (t > max_seconds) break :blk null; // treat huge values as "forever"
        break :blk @intFromFloat(t * std.time.ns_per_s);
    } else null;

    while (true) {
        // Check if all conditions are met
        var all_satisfied = true;
        for (config.paths) |path| {
            const exists = pathExists(path);
            const want_exists = !config.wait_for_deletion;

            if (exists != want_exists) {
                all_satisfied = false;
                break;
            }
        }

        if (all_satisfied) {
            return EXIT_SUCCESS;
        }

        // Check timeout
        if (timeout_ns) |tns| {
            const elapsed = std.time.nanoTimestamp() - start_time;
            if (elapsed >= tns) {
                return EXIT_TIMEOUT;
            }
        }

        // Sleep before next poll
        std.Thread.sleep(DEFAULT_POLL_MS * std.time.ns_per_ms);
    }
}

fn pathExists(path: []const u8) bool {
    // Try as absolute path first, then relative to cwd
    if (std.fs.path.isAbsolute(path)) {
        std.fs.accessAbsolute(path, .{}) catch return false;
        return true;
    } else {
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }
}

test "pathExists detects existing file" {
    // Test with a path that should exist on any system
    if (builtin.os.tag == .windows) {
        try std.testing.expect(pathExists("C:\\Windows"));
    } else {
        try std.testing.expect(pathExists("/tmp"));
    }
}

test "pathExists returns false for non-existent file" {
    try std.testing.expect(!pathExists("/nonexistent/path/that/should/not/exist"));
}
