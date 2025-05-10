const std = @import("std");
const Package = @import("package.zig").Package;

pub fn generate(allocator: std.mem.Allocator, resolution: anytype) !void {
    const file = try std.fs.cwd().createFile("zel.lock", .{});
    defer file.close();

    var writer = file.writer();
    try writer.writeAll("{\n  \"packages\": [\n");

    for (resolution.packages.items, 0..) |pkg, i| {
        try writer.writeAll("    {\n");
        try writer.print("      \"name\": \"{s}\",\n", .{pkg.name});
        try writer.print("      \"version\": \"{s}\",\n", .{pkg.version});
        
        switch (pkg.source) {
            .git => |git| {
                try writer.writeAll("      \"source\": {\n");
                try writer.print("        \"type\": \"git\",\n", .{});
                try writer.print("        \"url\": \"{s}\",\n", .{git.url});
                try writer.print("        \"rev\": \"{s}\"\n", .{git.rev});
                try writer.writeAll("      }\n");
            },
            .http => |http| {
                try writer.writeAll("      \"source\": {\n");
                try writer.print("        \"type\": \"http\",\n", .{});
                try writer.print("        \"url\": \"{s}\",\n", .{http.url});
                try writer.print("        \"sha256\": \"{s}\"\n", .{http.sha256});
                try writer.writeAll("      }\n");
            },
            .local => |path| {
                try writer.writeAll("      \"source\": {\n");
                try writer.print("        \"type\": \"local\",\n", .{});
                try writer.print("        \"path\": \"{s}\"\n", .{path});
                try writer.writeAll("      }\n");
            },
        }

        if (pkg.dependencies.items.len > 0) {
            try writer.writeAll(",\n      \"dependencies\": [\n");
            for (pkg.dependencies.items, 0..) |dep, j| {
                try writer.print("        {{\"name\": \"{s}\", \"version\": \"{s}\"}}", .{ dep.name, dep.version_range });
                if (j < pkg.dependencies.items.len - 1) try writer.writeAll(",\n");
            }
            try writer.writeAll("\n      ]\n");
        } else {
            try writer.writeAll("\n");
        }

        try writer.writeAll("    }");
        if (i < resolution.packages.items.len - 1) try writer.writeAll(",");
        try writer.writeAll("\n");
    }

    try writer.writeAll("  ]\n}\n");
}
