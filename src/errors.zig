const std = @import("std");

pub const ZelError = error{
    PackageNotFound,
    VersionNotFound,
    DependencyConflict,
    DownloadFailed,
    ChecksumMismatch,
    InvalidPackageFormat,
    RegistryUnavailable,
    BuildFailed,
    IoError,
    NetworkError,
    OutOfMemory,
};

pub fn formatError(err: anyerror, writer: anytype) !void {
    switch (err) {
        error.PackageNotFound => try writer.writeAll("Package not found in registry"),
        error.VersionNotFound => try writer.writeAll("Requested version not found"),
        error.DependencyConflict => try writer.writeAll("Dependency version conflict detected"),
        error.DownloadFailed => try writer.writeAll("Failed to download package"),
        error.ChecksumMismatch => try writer.writeAll("Package checksum verification failed"),
        error.InvalidPackageFormat => try writer.writeAll("Invalid package format"),
        error.RegistryUnavailable => try writer.writeAll("Registry service unavailable"),
        error.BuildFailed => try writer.writeAll("Project build failed"),
        error.IoError => try writer.writeAll("Filesystem operation failed"),
        error.NetworkError => try writer.writeAll("Network operation failed"),
        error.OutOfMemory => try writer.writeAll("Out of memory"),
        else => try writer.print("Unknown error: {any}", .{err}),
    }
}

pub fn printError(comptime prefix: []const u8, err: anyerror) void {
    std.debug.print("{s}Error: ", .{prefix});
    formatError(err, std.io.getStdErr().writer()) catch {};
    std.debug.print("\n", .{});
}

pub fn printErrorWithDetails(comptime prefix: []const u8, err: anyerror, details: []const u8) void {
    std.debug.print("{s}Error: ", .{prefix});
    formatError(err, std.io.getStdErr().writer()) catch {};
    std.debug.print(" - {s}\n", .{details});
}
