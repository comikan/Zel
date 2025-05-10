const std = @import("std");
const Package = @import("package.zig").Package;
const utils = @import("utils.zig");

pub const Resolution = struct {
    packages: std.ArrayListUnmanaged(Package),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Resolution {
        return .{
            .packages = std.ArrayListUnmanaged(Package).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Resolution) void {
        for (self.packages.items) |*pkg| {
            pkg.deinit(self.allocator);
        }
        self.packages.deinit(self.allocator);
    }
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    dependencies: std.StringHashMapUnmanaged([]const u8),
    resolved: std.StringHashMapUnmanaged(void),
    resolution: Resolution,

    pub fn init(allocator: std.mem.Allocator) !Resolver {
        return .{
            .allocator = allocator,
            .dependencies = .{},
            .resolved = .{},
            .resolution = Resolution.init(allocator),
        };
    }

    pub fn deinit(self: *Resolver) void {
        self.dependencies.deinit(self.allocator);
        self.resolved.deinit(self.allocator);
        self.resolution.deinit();
    }

    pub fn addDependency(self: *Resolver, name: []const u8, version: []const u8) !void {
        try self.dependencies.put(self.allocator, try self.allocator.dupe(u8, name), try self.allocator.dupe(u8, version));
    }

    pub fn resolve(self: *Resolver) !Resolution {
        var it = self.dependencies.iterator();
        while (it.next()) |entry| {
            if (!self.resolved.contains(entry.key_ptr.*)) {
                try self.resolvePackage(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        return self.resolution;
    }

    fn resolvePackage(self: *Resolver, name: []const u8, version_range: []const u8) !void {
        // In a real implementation, this would query a package registry
        // For now, we'll simulate resolving a package
        
        try self.resolved.put(self.allocator, try self.allocator.dupe(u8, name), {});
        
        // Determine actual version to use
        const version = if (std.mem.eql(u8, version_range, "latest"))
            "1.0.0"
        else
            version_range;
        
        // Create package
        var pkg = Package{
            .name = try self.allocator.dupe(u8, name),
            .version = try self.allocator.dupe(u8, version),
            .source = .{
                .git = .{
                    .url = try self.allocator.dupe(u8, try std.fmt.allocPrint(self.allocator, "https://github.com/{s}.git", .{name})),
                    .rev = try self.allocator.dupe(u8, "HEAD"),
                },
            },
        };
        
        // Simulate reading dependencies from package manifest
        if (std.mem.eql(u8, name, "zlib")) {
            try pkg.dependencies.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, "libc"),
                .version_range = try self.allocator.dupe(u8, "latest"),
            });
        }
        
        // Resolve transitive dependencies
        for (pkg.dependencies.items) |dep| {
            if (!self.resolved.contains(dep.name)) {
                try self.resolvePackage(dep.name, dep.version_range);
            }
        }
        
        try self.resolution.packages.append(self.allocator, pkg);
    }
};
