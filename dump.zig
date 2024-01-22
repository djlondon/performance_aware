const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    const filePath = args.next() orelse return error.NoFile;
    const file = try std.fs.cwd().openFile(filePath, .{});
    defer file.close();
    const reader = file.reader();
    while (reader.readByte()) |byte| {
        std.debug.print("{x} ", .{byte});
    } else |_| {
        std.debug.print("\n", .{});
    }
}
