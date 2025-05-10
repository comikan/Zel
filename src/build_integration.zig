const std = @import("std");
const Package = @import("package.zig").Package;
const Cache = @import("cache.zig").Cache;

pub fn generate(allocator: std.mem.Allocator, resolution: anytype) !void {
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
        \\
    );

    var cache = try Cache.init(allocator);
    defer cache.deinit();

    for (resolution.packages.items) |pkg| {
        const pkg_path = try cache.getPackagePath(pkg.name, pkg.version);
        defer allocator.free(pkg_path);

        try writer.print(
            \\    const {s}_path = "{s}";
            \\    const {s}_module = step.builder.createModule(.{{
            \\        .source_file = .{{ .path = std.fs.path.join(step.builder.allocator, &.{{ {s}_path, "src", "main.zig" }}) catch unreachable }},
            \\    }});
            \\    step.addModule("{s}", {s}_module);
            \\
        , .{ 
            utils.sanitizeName(pkg.name),
            pkg_path,
            utils.sanitizeName(pkg.name),
            utils.sanitizeName(pkg.name),
            pkg.name,
            utils.sanitizeName(pkg.name),
        });
    }

    try writer.writeAll("}\n");
}
