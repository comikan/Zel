fn installPackages(allocator: std.mem.Allocator) !void {
    std.debug.print("Resolving dependencies...\n", .{});
    
    // 1. Read zel.mod
    const mod_file = try std.fs.cwd().openFile("zel.mod", .{});
    defer mod_file.close();
    
    const file_size = try mod_file.getEndPos();
    const file_contents = try mod_file.readToEndAlloc(allocator, file_size);
    defer allocator.free(file_contents);
    
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, file_contents, .{});
    defer parsed.deinit();
    
    // 2. Resolve dependencies
    const resolver = try Resolver.init(allocator);
    defer resolver.deinit();
    
    const dependencies = parsed.value.object.get("dependencies").?.object;
    var it = dependencies.iterator();
    
    while (it.next()) |entry| {
        try resolver.addDependency(entry.key_ptr.*, entry.value_ptr.*.string);
    }
    
    const resolution = try resolver.resolve();
    defer resolution.deinit();

    // Handle conflicts
    if (resolver.conflicts.count() > 0) {
        std.debug.print("\nDependency conflicts found:\n", .{});
        try resolver.formatConflicts(std.io.getStdOut().writer());
        return error.DependencyConflict;
    }
    
    // 3. Fetch packages in parallel
    std.debug.print("\nDownloading packages...\n", .{});
    const fetcher = try Fetcher.init(allocator);
    defer fetcher.deinit();

    try fetcher.fetchAll(resolution.packages.items);

    if (fetcher.error_flag.load(.SeqCst)) {
        std.debug.print("\nDownload errors occurred:\n", .{});
        try fetcher.formatErrors(std.io.getStdOut().writer());
        return error.DownloadFailed;
    }
    
    // 4. Generate lockfile
    try Lockfile.generate(allocator, resolution);
    
    // 5. Generate build integration
    const target = try std.zig.system.NativeTargetInfo.detect(.{ .allocator = allocator });
    try BuildIntegration.generate(allocator, resolution, target.target);
    
    std.debug.print("\nDone! {} packages installed successfully.\n", .{resolution.packages.items.len});
}
