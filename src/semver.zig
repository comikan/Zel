const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,
    pre: ?[]const u8,
    build: ?[]const u8,

    pub fn parse(allocator: Allocator, version_str: []const u8) !Version {
        var iter = std.mem.split(u8, version_str, ".");
        const major_str = iter.next() orelse return error.InvalidVersion;
        const minor_str = iter.next() orelse return error.InvalidVersion;
        const patch_pre = iter.rest();

        var patch_str = patch_pre;
        var pre: ?[]const u8 = null;
        
        if (std.mem.indexOf(u8, patch_pre, "-")) |idx| {
            patch_str = patch_pre[0..idx];
            pre = patch_pre[idx+1..];
        }

        return Version{
            .major = try std.fmt.parseInt(u32, major_str, 10),
            .minor = try std.fmt.parseInt(u32, minor_str, 10),
            .patch = try std.fmt.parseInt(u32, patch_str, 10),
            .pre = if (pre) |p| try allocator.dupe(u8, p) else null,
            .build = null, // Not handling build metadata for now
        };
    }

    pub fn deinit(self: *Version, allocator: Allocator) void {
        if (self.pre) |p| allocator.free(p);
        if (self.build) |b| allocator.free(b);
    }

    pub fn satisfies(self: Version, range: []const u8) bool {
        if (std.mem.eql(u8, range, "*") or std.mem.eql(u8, range, "latest")) {
            return true;
        }

        const op = range[0];
        const version_str = range[1..];
        
        // Simple comparison for now - would implement full SemVer range parsing
        const other = Version.parse(std.heap.page_allocator, version_str) catch return false;
        defer other.deinit(std.heap.page_allocator);

        return switch (op) {
            '^' => self.major == other.major and self.minor >= other.minor,
            '~' => self.major == other.major and self.minor == other.minor and self.patch >= other.patch,
            '>' => self.compare(other) == .gt,
            '<' => self.compare(other) == .lt,
            '=' => self.compare(other) == .eq,
            else => false,
        };
    }

    pub fn compare(self: Version, other: Version) std.math.Order {
        if (self.major != other.major) return std.math.order(self.major, other.major);
        if (self.minor != other.minor) return std.math.order(self.minor, other.minor);
        if (self.patch != other.patch) return std.math.order(self.patch, other.patch);
        
        // Compare pre-release versions if they exist
        if (self.pre != null or other.pre != null) {
            if (self.pre == null) return .gt;
            if (other.pre == null) return .lt;
            return std.mem.order(u8, self.pre.?, other.pre.?);
        }
        
        return .eq;
    }
};
