const std = @import("std");
const Package = @import("package.zig").Package;

pub const Cache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Cache {
        const cache_dir = try std.fs.path.join(allocator, &[_][]const u8{ ".zel", "cache" });
        try std.fs.cwd().makePath(cache_dir);
        return .{
            .allocator = allocator,
            .cache_dir = cache_dir,
        };
    }

    pub fn deinit(self: *Cache) void {
        self.allocator.free(self.cache_dir);
    }

    pub fn hasPackage(self: *Cache, name: []const u8, version: []const u8) !bool {
        const pkg_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, name, version });
        defer self.allocator.free(pkg_dir);

        std.fs.cwd().access(pkg_dir, .{}) catch |err| {
            if (err == error.FileNotFound) return false;
            return err;
        };
        return true;
    }

    pub fn addPackage(self: *Cache, name: []const u8, version: []const u8, source_dir: []const u8) !void {
        const dest_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, name, version });
        defer self.allocator.free(dest_dir);

        try std.fs.cwd().makePath(dest_dir);
        try utils.copyDirectory(source_dir, dest_dir);
    }

    pub fn getPackagePath(self: *Cache, name: []const u8, version: []const u8) ![]const u8 {
        return std.fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, name, version });
    }
};
