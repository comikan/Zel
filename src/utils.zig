const std = @import("std");

pub fn runCommand(argv: []const []const u8) !void {
    var child = std.ChildProcess.init(argv, std.heap.page_allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    
    const stderr = try child.stderr.?.reader().readAllAlloc(std.heap.page_allocator, 1024 * 1024);
    defer std.heap.page_allocator.free(stderr);

    const term = try child.wait();
    if (term.Exited != 0) {
        std.debug.print("{s}\n", .{stderr});
        return error.CommandFailed;
    }
}

pub fn copyDirectory(src_path: []const u8, dest_path: []const u8) !void {
    var src_dir = try std.fs.cwd().openDir(src_path, .{ .iterate = true });
    defer src_dir.close();

    var dest_dir = try std.fs.cwd().makeOpenPath(dest_path, .{});
    defer dest_dir.close();

    var walker = try src_dir.walk(std.heap.page_allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const dest_entry_path = try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{dest_path, entry.path});
        defer std.heap.page_allocator.free(dest_entry_path);

        switch (entry.kind) {
            .file => {
                try src_dir.copyFile(entry.path, dest_dir, entry.path, .{});
            },
            .directory => {
                try dest_dir.makeDir(entry.path);
            },
            else => continue,
        }
    }
}

pub fn sanitizeName(name: []const u8) []const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    for (name) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            result.append(std.ascii.toLower(c)) catch unreachable;
        } else {
            result.append('_') catch unreachable;
        }
    }

    return result.toOwnedSlice() catch unreachable;
}
