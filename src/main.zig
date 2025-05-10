const std = @import("std");
const Package = @import("package.zig").Package;
const Resolver = @import("resolver.zig");
const Fetcher = @import("fetcher.zig");
const Lockfile = @import("lockfile.zig");
const BuildIntegration = @import("build_integration.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    if (args.len < 2) {
        printHelp();
        return;
    }

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "init")) {
        try initProject(allocator);
    } else if (std.mem.eql(u8, cmd, "add")) {
        if (args.len < 3) return error.MissingPackageName;
        try addPackage(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "install")) {
        try installPackages(allocator);
    } else if (std.mem.eql(u8, cmd, "build")) {
        try buildProject(allocator);
    } else {
        printHelp();
    }
}

fn printHelp() void {
    std.debug.print(
        \\Zel - Zig Package Manager
        \\Usage:
        \\  zel init               Initialize a new project
        \\  zel add <package>      Add a package
        \\  zel install            Install all dependencies
        \\  zel build              Build the project
        \\
    , .{});
}

fn initProject(allocator: std.mem.Allocator) !void {
    // Create basic project structure
    try std.fs.cwd().makeDir("src");
    
    // Create sample zel.mod file
    const file = try std.fs.cwd().createFile("zel.mod", .{});
    defer file.close();
    try file.writeAll(
        \\{
        \\  "name": "my-project",
        \\  "version": "0.1.0",
        \\  "dependencies": {}
        \\}
    );
    
    // Create basic build.zig
    const build_file = try std.fs.cwd().createFile("build.zig", .{});
    defer build_file.close();
    try build_file.writeAll(
        \\const std = @import("std");
        \\const zel = @import("zel.build.zig");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    zel.setup(b);
        \\    
        \\    const exe = b.addExecutable(.{
        \\        .name = "my-project",
        \\        .root_source_file = .{ .path = "src/main.zig" },
        \\        .target = b.standardTargetOptions(.{}),
        \\        .optimize = b.standardOptimizeOption(.{}),
        \\    });
        \\    
        \\    zel.linkDependencies(b, exe);
        \\    b.installArtifact(exe);
        \\}
    );
    
    std.debug.print("Project initialized!\n", .{});
}

fn addPackage(allocator: std.mem.Allocator, packages: [][]const u8) !void {
    // Parse existing zel.mod
    const mod_file = try std.fs.cwd().openFile("zel.mod", .{});
    defer mod_file.close();
    
    const file_size = try mod_file.getEndPos();
    const file_contents = try mod_file.readToEndAlloc(allocator, file_size);
    defer allocator.free(file_contents);
    
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, file_contents, .{});
    defer parsed.deinit();
    
    // Add new packages
    var dependencies = parsed.value.object.get("dependencies").?.object;
    
    for (packages) |pkg| {
        // Simple parsing of package@version
        const at_index = std.mem.indexOf(u8, pkg, "@") orelse pkg.len;
        const name = pkg[0..at_index];
        const version = if (at_index < pkg.len) pkg[at_index+1..] else "latest";
        
        try dependencies.put(name, .{ .string = version });
    }
    
    // Write back to file
    try mod_file.seekTo(0);
    try mod_file.setEndPos(0);
    try std.json.stringify(parsed.value, .{ .whitespace = .indent_2 }, mod_file.writer());
    
    std.debug.print("Added {} package(s). Run 'zel install' to install them.\n", .{packages.len});
}

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
    
    // 3. Fetch packages
    std.debug.print("Downloading packages...\n", .{});
    const fetcher = try Fetcher.init(allocator);
    defer fetcher.deinit();
    
    for (resolution.packages.items) |pkg| {
        try fetcher.fetch(pkg);
    }
    
    // 4. Generate lockfile
    try Lockfile.generate(allocator, resolution);
    
    // 5. Generate build integration
    try BuildIntegration.generate(allocator, resolution);
    
    std.debug.print("Done! {} packages installed.\n", .{resolution.packages.items.len});
}

fn buildProject(allocator: std.mem.Allocator) !void {
    try installPackages(allocator);
    
    // Run zig build
    const result = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &[_][]const u8{"zig", "build"},
    });
    
    std.debug.print("{s}\n", .{result.stdout});
    if (result.term.Exited != 0) {
        std.debug.print("{s}\n", .{result.stderr});
        return error.BuildFailed;
    }
}
