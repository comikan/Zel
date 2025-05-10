const std = @import("std");
const http = std.http;
const json = std.json;
const Package = @import("package.zig").Package;

pub const Registry = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .base_url = "https://registry.zel-lang.org",
        };
    }

    pub fn deinit(self: *Registry) void {
        self.allocator.free(self.base_url);
    }

    pub fn getPackageMetadata(self: *Registry, name: []const u8) !json.Parsed(json.Value) {
        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const url = try std.fmt.allocPrint(self.allocator, "{s}/packages/{s}", .{ self.base_url, name });
        defer self.allocator.free(url);

        var headers = http.Headers{ .allocator = self.allocator };
        defer headers.deinit();
        try headers.append("Accept", "application/json");

        var req = try client.request(.GET, try std.Uri.parse(url), headers, .{});
        defer req.deinit();

        try req.start();
        try req.wait();

        if (req.response.status != .ok) {
            return error.RegistryRequestFailed;
        }

        const body = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(body);

        return json.parseFromSlice(json.Value, self.allocator, body, .{});
    }

    pub fn resolveVersion(self: *Registry, name: []const u8, version_range: []const u8) ![]const u8 {
        const metadata = try self.getPackageMetadata(name);
        defer metadata.deinit();

        const versions = metadata.value.object.get("versions").?.array.items;
        
        if (std.mem.eql(u8, version_range, "latest")) {
            return try self.allocator.dupe(u8, metadata.value.object.get("latest").?.string);
        }

        // Simple SemVer resolution - would be enhanced in next section
        for (versions) |version_obj| {
            const version = version_obj.object.get("version").?.string;
            if (std.mem.eql(u8, version, version_range)) {
                return try self.allocator.dupe(u8, version);
            }
        }

        return error.VersionNotFound;
    }
};
