const std = @import("std");

const Node = struct {
    name: []const u8,
    isDir: bool,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var cwd = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer cwd.close();

    try print_tree(allocator, cwd, 0);
}

fn print_tree(allocator: std.mem.Allocator, dir: std.fs.Dir, indent: usize) !void {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        var prefix = std.mem.zeroes([32]u8);
        _ = std.fmt.bufPrint(&prefix, "{s}", .{"|  "}) catch "";

        for (0..indent) |_| {
            try std.io.getStdOut().writer().writeAll("|  ");
        }

        const is_dir = switch (entry.kind) {
            .directory => true,
            else => false,
        };

        const marker = if (is_dir) "📁" else "📄";
        try std.io.getStdOut().writer().print("{s} {s}\n", .{ marker, entry.name });

        if (is_dir) {
            var sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
            defer sub_dir.close();
            try print_tree(allocator, sub_dir, indent + 1);
        }
    }
}
