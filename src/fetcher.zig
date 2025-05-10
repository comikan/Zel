const std = @import("std");
const Package = @import("package.zig").Package;
const Cache = @import("cache.zig").Cache;
const ThreadPool = std.Thread.Pool;
const Atomic = std.atomic.Atomic;

pub const Fetcher = struct {
    allocator: std.mem.Allocator,
    cache: Cache,
    pool: ThreadPool,
    errors: std.ArrayListUnmanaged(ErrorInfo),
    error_flag: Atomic(bool),

    const ErrorInfo = struct {
        pkg_name: []const u8,
        err: anyerror,
        message: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) !Fetcher {
        var pool = ThreadPool.init(.{ .allocator = allocator });
        try pool.spawnWorkers(std.Thread.getCpuCount() catch 4);

        return .{
            .allocator = allocator,
            .cache = try Cache.init(allocator),
            .pool = pool,
            .errors = .{},
            .error_flag = Atomic(bool).init(false),
        };
    }

    pub fn deinit(self: *Fetcher) void {
        self.cache.deinit();
        self.pool.deinit();
        
        for (self.errors.items) |err| {
            self.allocator.free(err.pkg_name);
            self.allocator.free(err.message);
        }
        self.errors.deinit(self.allocator);
    }

    pub fn fetchAll(self: *Fetcher, packages: []const Package) !void {
        var context = Context{
            .fetcher = self,
            .packages = packages,
        };

        // Schedule all downloads
        for (packages, 0..) |pkg, i| {
            try self.pool.spawn(fetchWorker, .{ &context, i });
        }

        // Wait for completion
        self.pool.waitAndWork();

        if (self.error_flag.load(.SeqCst)) {
            return error.DownloadFailed;
        }
    }

    const Context = struct {
        fetcher: *Fetcher,
        packages: []const Package,
    };

    fn fetchWorker(ctx: *Context, index: usize) void {
        const pkg = ctx.packages[index];
        const fetcher = ctx.fetcher;

        if (fetcher.cache.hasPackage(pkg.name, pkg.version) catch false) {
            std.debug.print("Using cached {s}@{s}\n", .{ pkg.name, pkg.version });
            return;
        }

        std.debug.print("Downloading {s}@{s}\n", .{ pkg.name, pkg.version });

        const pkg_dir = std.fmt.allocPrint(fetcher.allocator, "zel-packages/{s}", .{pkg.name}) catch {
            fetcher.recordError(pkg.name, error.OutOfMemory, "Failed to allocate path") catch {};
            return;
        };
        defer fetcher.allocator.free(pkg_dir);

        switch (pkg.source) {
            .git => |git| {
                fetcher.fetchGit(pkg.name, git.url, git.rev, pkg_dir) catch |err| {
                    fetcher.recordError(pkg.name, err, "Git download failed") catch {};
                };
            },
            .http => |http| {
                fetcher.fetchHttp(pkg.name, http.url, http.sha256, pkg_dir) catch |err| {
                    fetcher.recordError(pkg.name, err, "HTTP download failed") catch {};
                };
            },
            .local => |path| {
                fetcher.fetchLocal(pkg.name, path, pkg_dir) catch |err| {
                    fetcher.recordError(pkg.name, err, "Local package link failed") catch {};
                };
            },
        }

        if (!fetcher.error_flag.load(.SeqCst)) {
            fetcher.cache.addPackage(pkg.name, pkg.version, pkg_dir) catch |err| {
                fetcher.recordError(pkg.name, err, "Failed to cache package") catch {};
            };
        }
    }

    fn recordError(self: *Fetcher, pkg_name: []const u8, err: anyerror, message: []const u8) !void {
        self.error_flag.store(true, .SeqCst);
        
        try self.errors.append(self.allocator, .{
            .pkg_name = try self.allocator.dupe(u8, pkg_name),
            .err = err,
            .message = try self.allocator.dupe(u8, message),
        });
    }

    pub fn formatErrors(self: *Fetcher, writer: anytype) !void {
        for (self.errors.items) |err| {
            try writer.print("{s}: {s} - {any}\n", .{
                err.pkg_name,
                err.message,
                err.err,
            });
        }
    }
};
