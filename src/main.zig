const terminos = @cImport({
    @cInclude("termio.h");
    @cInclude("unistd.h");
});
const std = @import("std");

const Node = struct {
    name: []const u8,
    is_dir: bool,
    expanded: bool = false,
    children: ?[]Node = null,
};

const VisibleNode = struct {
    node: *Node,
    depth: usize,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var cwd = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer cwd.close();

    const root_nodes = try buildTree(allocator, &cwd);

    var cursor_index: usize = 0;
    var prev_cursor_index: usize = 0;

    enableRawMode();
    defer disableRawMode();

    var visible = try flattenTree(allocator, root_nodes, 0);

    try std.io.getStdOut().writeAll("\x1b[2J\x1b[H");
    try renderVisibleTree(visible, cursor_index);

    while (true) {
        const key = try readKey();

        switch (key) {
            'q' => break,
            'u' => {
                if (cursor_index > 0) cursor_index -= 1;
            },
            'd' => {
                if (cursor_index + 1 < visible.len) cursor_index += 1;
            },
            'e' => {
                const current = visible[cursor_index];
                if (current.node.is_dir) {
                    current.node.expanded = !current.node.expanded;
                    visible = try flattenTree(allocator, root_nodes, 0);
                    try std.io.getStdOut().writeAll("\x1b[2J\x1b[H");
                    try renderVisibleTree(visible, cursor_index);
                    continue;
                }
            },
            else => {},
        }

        if (cursor_index != prev_cursor_index) {
            try moveToLine(prev_cursor_index);
            try renderLine(visible[prev_cursor_index], false);

            try moveToLine(cursor_index);
            try renderLine(visible[cursor_index], true);

            prev_cursor_index = cursor_index;
        }
    }
}

fn buildTree(allocator: std.mem.Allocator, dir: *std.fs.Dir) ![]Node {
    var entries = std.ArrayList(Node).init(allocator);

    var it = dir.iterate();
    while (try it.next()) |entry| {
        const is_dir = entry.kind == .directory;
        const name = try allocator.dupe(u8, entry.name);

        var node = Node{
            .name = name,
            .is_dir = is_dir,
            .expanded = false,
            .children = null,
        };

        if (is_dir) {
            var sub_dir_val: std.fs.Dir = try dir.openDir(entry.name, .{ .iterate = true });
            defer sub_dir_val.close();

            const children = try buildTree(allocator, &sub_dir_val);
            node.children = children;
        }

        try entries.append(node);
    }

    return entries.toOwnedSlice();
}

fn renderVisibleTree(visible: []VisibleNode, cursor_index: usize) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("\x1b[?25l"); // Hide cursor

    for (visible, 0..) |entry, i| {
        for (0..entry.depth) |_| {
            try stdout.writeAll("  | ");
        }

        const marker = if (entry.node.is_dir)
            (if (entry.node.expanded) "📂" else "📁")
        else
            "📄";

        const cursor = if (i == cursor_index) "▶" else " ";

        try stdout.print("{s} {s} {s}\n", .{ cursor, marker, entry.node.name });
    }

    try stdout.writeAll("\x1b[?25h"); // Show cursor again (optional here)
}

fn flattenTree(allocator: std.mem.Allocator, nodes: []Node, depth: usize) ![]VisibleNode {
    var list = std.ArrayList(VisibleNode).init(allocator);

    for (nodes) |*node| {
        try list.append(.{
            .node = node,
            .depth = depth,
        });

        if (node.is_dir and node.expanded) {
            if (node.children) |children| {
                const sublist = try flattenTree(allocator, children, depth + 1);
                try list.appendSlice(sublist);
            }
        }
    }

    return list.toOwnedSlice();
}

fn enableRawMode() void {
    var raw: terminos.termios = undefined;
    _ = terminos.tcgetattr(0, &raw);
    raw.c_lflag &= ~@as(terminos.tcflag_t, terminos.ICANON | terminos.ECHO);
    raw.c_cc[terminos.VMIN] = 1;
    raw.c_cc[terminos.VTIME] = 0;
    _ = terminos.tcsetattr(0, terminos.TCSAFLUSH, &raw);
}

fn disableRawMode() void {
    var cooked: terminos.termios = undefined;
    _ = terminos.tcgetattr(0, &cooked);
    cooked.c_lflag |= (terminos.ICANON | terminos.ECHO);
    _ = terminos.tcsetattr(0, terminos.TCSAFLUSH, &cooked);
    std.io.getStdOut().writeAll("\x1b[?25h") catch {};
}

fn readKey() !u8 {
    var stdin = std.io.getStdIn().reader();

    const b1 = try stdin.readByte();
    if (b1 == 0x1b) {
        _ = try stdin.readByte();
        const b3 = try stdin.readByte();

        return switch (b3) {
            'A' => 'u',
            'B' => 'd',
            else => 0,
        };
    } else if (b1 == '\r' or b1 == '\n') {
        return 'e';
    }

    return b1;
}

fn moveToLine(line: usize) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\x1b[{};1H", .{line + 1}); // ANSI: line starts at 1
}

fn renderLine(entry: VisibleNode, is_selected: bool) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("\x1b[2K"); // Clear line

    for (0..entry.depth) |_| {
        try stdout.writeAll("  | ");
    }

    const marker = if (entry.node.is_dir)
        (if (entry.node.expanded) "📂" else "📁")
    else
        "📄";

    const cursor = if (is_selected) "▶" else " ";

    try stdout.print("{s} {s} {s}\n", .{ cursor, marker, entry.node.name });
}
