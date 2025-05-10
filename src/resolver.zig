const std = @import("std");
const Package = @import("package.zig").Package;
const Registry = @import("registry.zig").Registry;
const SemVer = @import("semver.zig");

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

    pub fn findPackage(self: *Resolution, name: []const u8) ?*Package {
        for (self.packages.items) |*pkg| {
            if (std.mem.eql(u8, pkg.name, name)) {
                return pkg;
            }
        }
        return null;
    }
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    registry: Registry,
    resolution: Resolution,
    conflicts: std.StringHashMapUnmanaged(std.ArrayListUnmanaged([]const u8)),

    pub fn init(allocator: std.mem.Allocator) !Resolver {
        return .{
            .allocator = allocator,
            .registry = Registry.init(allocator),
            .resolution = Resolution.init(allocator),
            .conflicts = .{},
        };
    }

    pub fn deinit(self: *Resolver) void {
        self.registry.deinit();
        self.resolution.deinit();
        
        var it = self.conflicts.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.items) |version| {
                self.allocator.free(version);
            }
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.conflicts.deinit(self.allocator);
    }

    pub fn resolve(self: *Resolver, root_dependencies: anytype) !void {
        var dep_queue = std.ArrayList(struct { name: []const u8, range: []const u8 }).init(self.allocator);
        defer {
            for (dep_queue.items) |dep| {
                self.allocator.free(dep.name);
                self.allocator.free(dep.range);
            }
            dep_queue.deinit();
        }

        // Add root dependencies to queue
        var it = root_dependencies.iterator();
        while (it.next()) |entry| {
            try dep_queue.append(.{
                .name = try self.allocator.dupe(u8, entry.key_ptr.*),
                .range = try self.allocator.dupe(u8, entry.value_ptr.*),
            });
        }

        // Process queue
        while (dep_queue.popOrNull()) |dep| {
            defer {
                self.allocator.free(dep.name);
                self.allocator.free(dep.range);
            }

            if (self.resolution.findPackage(dep.name)) |existing| {
                // Check if existing version satisfies the new requirement
                const existing_ver = try SemVer.Version.parse(self.allocator, existing.version);
                defer existing_ver.deinit(self.allocator);

                if (!existing_ver.satisfies(dep.range)) {
                    // Record conflict
                    try self.recordConflict(dep.name, existing.version, dep.range);
                }
                continue;
            }

            // Resolve version from registry
            const version = try self.registry.resolveVersion(dep.name, dep.range);
            defer self.allocator.free(version);

            // Create package
            var pkg = Package{
                .name = try self.allocator.dupe(u8, dep.name),
                .version = try self.allocator.dupe(u8, version),
                .source = .{
                    .git = .{
                        .url = try self.allocator.dupe(u8, try std.fmt.allocPrint(
                            self.allocator,
                            "https://github.com/{s}.git",
                            .{dep.name},
                        )),
                        .rev = try self.allocator.dupe(u8, "HEAD"),
                    },
                },
            };

            // Get package dependencies
            const metadata = try self.registry.getPackageMetadata(dep.name);
            defer metadata.deinit();

            if (metadata.value.object.get("dependencies")) |deps| {
                var dep_it = deps.object.iterator();
                while (dep_it.next()) |entry| {
                    try pkg.dependencies.append(self.allocator, .{
                        .name = try self.allocator.dupe(u8, entry.key_ptr.*),
                        .version_range = try self.allocator.dupe(u8, entry.value_ptr.*.string),
                    });
                    try dep_queue.append(.{
                        .name = try self.allocator.dupe(u8, entry.key_ptr.*),
                        .range = try self.allocator.dupe(u8, entry.value_ptr.*.string),
                    });
                }
            }

            try self.resolution.packages.append(self.allocator, pkg);
        }

        if (self.conflicts.count() > 0) {
            return error.DependencyConflict;
        }
    }

    fn recordConflict(self: *Resolver, name: []const u8, existing_version: []const u8, new_range: []const u8) !void {
        const entry = try self.conflicts.getOrPut(self.allocator, try self.allocator.dupe(u8, name));
        if (!entry.found_existing) {
            entry.value_ptr.* = std.ArrayListUnmanaged([]const u8){};
        }

        try entry.value_ptr.append(self.allocator, try std.fmt.allocPrint(
            self.allocator,
            "required: {s}, existing: {s}",
            .{ new_range, existing_version },
        ));
    }

    pub fn formatConflicts(self: *Resolver, writer: anytype) !void {
        var it = self.conflicts.iterator();
        while (it.next()) |entry| {
            try writer.print("Package: {s}\n", .{entry.key_ptr.*});
            for (entry.value_ptr.items) |conflict| {
                try writer.print("  - {s}\n", .{conflict});
            }
        }
    }
};
