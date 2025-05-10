const std = @import("std");

pub const Package = struct {
    name: []const u8,
    version: []const u8,
    source: Source,
    dependencies: std.ArrayListUnmanaged(Dependency) = .{},

    pub const Source = union(enum) {
        git: GitSource,
        http: HttpSource,
        local: []const u8,

        pub const GitSource = struct {
            url: []const u8,
            rev: []const u8,
        };

        pub const HttpSource = struct {
            url: []const u8,
            sha256: []const u8,
        };
    };

    pub const Dependency = struct {
        name: []const u8,
        version_range: []const u8,
    };

    pub fn deinit(self: *Package, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        
        switch (self.source) {
            .git => |*git| {
                allocator.free(git.url);
                allocator.free(git.rev);
            },
            .http => |*http| {
                allocator.free(http.url);
                allocator.free(http.sha256);
            },
            .local => |path| {
                allocator.free(path);
            },
        }
        
        for (self.dependencies.items) |dep| {
            allocator.free(dep.name);
            allocator.free(dep.version_range);
        }
        self.dependencies.deinit(allocator);
    }
};
