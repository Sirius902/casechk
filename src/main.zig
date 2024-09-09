const std = @import("std");
const yazap = @import("yazap");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = yazap.App.init(allocator, "casechk", "Tool for detecting and handling filesystem case-insensitivity problems.");
    defer app.deinit();

    var casechk = app.rootCommand();
    casechk.setProperty(.help_on_empty_args);

    try casechk.addArgs(&[_]yazap.Arg{
        yazap.Arg.positional("DIR", null, null),
    });

    const matches = try app.parseProcess();
    if (matches.getSingleValue("DIR")) |dir| {
        try check(dir, allocator);
    }
}

fn check(root_dir: []const u8, allocator: std.mem.Allocator) !void {
    var to_check = try std.ArrayList([]const u8).initCapacity(allocator, 1);
    defer to_check.deinit();

    to_check.appendAssumeCapacity(try allocator.dupe(u8, root_dir));

    // TODO: Track all unique names to report.
    var dir_items = std.StringHashMap(void).init(allocator);
    defer dir_items.deinit();

    while (to_check.popOrNull()) |path| {
        defer allocator.free(path);

        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();

        var dir_arena = std.heap.ArenaAllocator.init(allocator);
        defer dir_arena.deinit();

        dir_items.clearRetainingCapacity();

        var it = dir.iterateAssumeFirstIteration();
        while (try it.next()) |entry| {
            const entry_name_lower = try dir_arena.allocator().alloc(u8, entry.name.len);
            for (entry_name_lower, 0..) |*c, i| {
                c.* = std.ascii.toLower(entry.name[i]);
            }

            const kv = try dir_items.getOrPut(entry_name_lower);
            if (kv.found_existing) {
                std.log.info("Found conflict: {s}", .{
                    try std.fs.path.join(dir_arena.allocator(), &[_][]const u8{
                        path,
                        entry.name,
                    }),
                });
            } else {
                kv.value_ptr.* = {};
            }

            if (entry.kind == .directory) {
                const next_to_check = if (std.mem.eql(u8, path, "."))
                    try allocator.dupe(u8, entry.name)
                else
                    try std.fs.path.join(allocator, &[_][]const u8{
                        path,
                        entry.name,
                    });
                errdefer allocator.free(next_to_check);

                try to_check.append(next_to_check);
            }
        }
    }
}
