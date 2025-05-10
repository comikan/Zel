const std = @import("std");
const Package = @import("package.zig").Package;
const Cache = @import("cache.zig").Cache;

pub fn generate(allocator: std.mem.Allocator, resolution: anytype, target: std.Target) !void {
    const file = try std.fs.cwd().createFile("zel.build.zig", .{});
    defer file.close();

    var writer = file.writer();
    
    try writer.writeAll(
        \\const std = @import("std");
        \\
        \\pub fn setup(b: *std.Build) void {
        \\    _ = b;
        \\}
        \\
        \\pub fn linkDependencies(b: *std.Build, step: *std.Build.Step.Compile) void {
        \\    const target = step.target;
        \\    const optimize = step.optimize;
        \\
    );

    var cache = try Cache.init(allocator);
    defer cache.deinit();

    for (resolution.packages.items) |pkg| {
        const pkg_path = try cache.getPackagePath(pkg.name, pkg.version);
        defer allocator.free(pkg_path);

        const target_suffix = switch (target.os.tag) {
            .windows => "-windows",
            .macos => "-macos",
            .linux => "-linux",
            else => "",
        };

        try writer.print(
            \\    const {s}_path = "{s}";
            \\    const {s}_src = if (std.fs.path.exists(std.fs.cwd(), "{s}_" ++ @tagName(target.os.tag) ++ ".zig")) 
            \\        .{{ .path = std.fs.path.join(b.allocator, &.{{ {s}_path, "src", "main_" ++ @tagName(target.os.tag) ++ ".zig" }}) catch unreachable }}
            \\    else 
            \\        .{{ .path = std.fs.path.join(b.allocator, &.{{ {s}_path, "src", "main.zig" }}) catch unreachable }};
            \\    
            \\    const {s}_module = b.createModule(.{{
            \\        .source_file = {s}_src,
            \\    }});
            \\    step.addModule("{s}", {s}_module);
            \\
        , .{ 
            utils.sanitizeName(pkg.name),
            pkg_path,
            utils.sanitizeName(pkg.name),
            pkg_path,
            utils.sanitizeName(pkg.name),
            utils.sanitizeName(pkg.name),
            utils.sanitizeName(pkg.name),
            utils.sanitizeName(pkg.name),
            pkg.name,
            utils.sanitizeName(pkg.name),
        });

        // Platform-specific linking
        if (target.os.tag == .windows) {
            try writer.print(
                \\    if (target.os.tag == .windows and std.fs.path.exists(std.fs.cwd(), 
                \\        std.fs.path.join(b.allocator, &.{{ {s}_path, "lib", "{s}.lib" }}) catch unreachable)) {{
                \\        step.linkLibrary(.{{
                \\            .name = "{s}",
                \\            .path = .{{ .path = std.fs.path.join(b.allocator, &.{{ {s}_path, "lib", "{s}.lib" }}) catch unreachable }},
                \\        }});
                \\    }}
                \\
            , .{
                pkg_path,
                pkg.name,
                pkg.name,
                pkg_path,
                pkg.name,
            });
        }
    }

    try writer.writeAll("}\n");
}
