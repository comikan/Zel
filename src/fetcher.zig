const std = @import("std");
const Package = @import("package.zig").Package;
const Cache = @import("cache.zig");

pub const Fetcher = struct {
    allocator: std.mem.Allocator,
    cache: Cache,

    pub fn init(allocator: std.mem.Allocator) !Fetcher {
        return .{
            .allocator = allocator,
            .cache = try Cache.init(allocator),
        };
    }

    pub fn deinit(self: *Fetcher) void {
        self.cache.deinit();
    }

    pub fn fetch(self: *Fetcher, pkg: Package) !void {
        const pkg_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ "zel-packages", pkg.name });
        defer self.allocator.free(pkg_dir);

        if (try self.cache.hasPackage(pkg.name, pkg.version)) {
            std.debug.print("Using cached {s}@{s}\n", .{ pkg.name, pkg.version });
            return;
        }

        std.debug.print("Fetching {s}@{s}\n", .{ pkg.name, pkg.version });

        switch (pkg.source) {
            .git => |git| {
                try self.fetchGit(git.url, git.rev, pkg_dir);
            },
            .http => |http| {
                try self.fetchHttp(http.url, http.sha256, pkg_dir);
            },
            .local => |path| {
                try self.fetchLocal(path, pkg_dir);
            },
        }

        try self.cache.addPackage(pkg.name, pkg.version, pkg_dir);
    }

    fn fetchGit(self: *Fetcher, url: []const u8, rev: []const u8, dest: []const u8) !void {
        std.debug.print("Cloning {s} at {s}\n", .{ url, rev });

        // Create temp dir
        const tmp_dir = "tmp-git-clone";
        defer std.fs.cwd().deleteTree(tmp_dir) catch {};

        // Clone repo
        try utils.runCommand(&.{ "git", "clone", url, tmp_dir });

        // Checkout specific revision if needed
        if (!std.mem.eql(u8, rev, "HEAD")) {
            try utils.runCommand(&.{ "git", "-C", tmp_dir, "checkout", rev });
        }

        // Move to destination
        try std.fs.cwd().rename(tmp_dir, dest);
    }

    fn fetchHttp(self: *Fetcher, url: []const u8, sha256: []const u8, dest: []const u8) !void {
        _ = sha256; // TODO: Verify checksum
        std.debug.print("Downloading {s}\n", .{url});

        // Create temp file
        const tmp_file = "tmp-download";
        defer std.fs.cwd().deleteFile(tmp_file) catch {};

        // Download file
        try utils.runCommand(&.{ "curl", "-L", "-o", tmp_file, url });

        // Extract archive
        try std.fs.cwd().makeDir(dest);
        try utils.runCommand(&.{ "tar", "-xzf", tmp_file, "-C", dest });
    }

    fn fetchLocal(self: *Fetcher, path: []const u8, dest: []const u8) !void {
        std.debug.print("Linking local package {s}\n", .{path});

        try std.fs.cwd().symLink(path, dest, .{ .is_directory = true });
    }
};
