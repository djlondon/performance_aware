const std = @import("std");

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    const filePath = args.next() orelse return error.NoFile;
    const file = try std.fs.cwd().openFile(filePath, .{});
    defer file.close();
    var buffer: [100]u8 = undefined;    
    const bytes_read = try file.readAll(&buffer);
    std.debug.print("{x}", .{buffer[0..bytes_read]});
}
