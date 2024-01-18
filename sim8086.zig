const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const print = std.debug.print;
const fmt = std.fmt;
const ArrayList = std.ArrayList;

// 0-- -- -- -- 1--- --- -- 3-- 4--
//  10 00 10 DW  mod reg rm  LO  HI
// reg/mem to/from reg/mem
// if first_byte.startswith(100010)
// D - direction, src => (REG) (R/M)
// W - word (L,H) (X,P,I)
// mod - 00 no LO/HI (unless R/M=110), 01 LO, 10 LOHI, 11 reg (no LO/HI)

// 1011WREG
// if the first 4 bytes 1011 (0xB), then the next four represent WREG */

pub fn main() !void {
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    var list = ArrayList(u8).init(allocator);
    defer list.deinit();
    try rmMap(0, 0, 0, &list);
    print("{s}\n", .{list.items});
}

/// Given RM, MOD and W, determine the address
/// Writes result to out
/// If MOD = 011, this is the same as regMap
fn rmMap(rm: u3, mod_: u2, W: u1, out: *std.ArrayList(u8)) !void {
    if (mod_ == 3) {
        try out.appendSlice(&regMap(rm, W));
        return;
    }
    const ins = switch (rm) {
        0 => "bx + si",
        1 => "bx + di",
        2 => "bp + si",
        3 => "bp + di",
        4 => "si",
        5 => "di",
        // TODO: implement direct address
        6 => if (mod_ == 0) "{}" else "bp",
        7 => "bx",
    };
    // TODO: implement displacement
    const disp = switch (mod_) {
        1 => " + D8",
        2 => " + D16",
        else => "",
    };
    try out.writer().print("[{s}{s}]", .{ ins, disp });
}

/// Given REG and and W, determine the register
fn regMap(reg: u3, W: u1) [2]u8 {
    var out: [2]u8 = undefined;
    out[0] = switch (W) {
        0 => switch (reg) {
            0, 4 => 'a',
            1, 5 => 'c',
            2, 6 => 'd',
            3, 7 => 'b',
        },
        1 => switch (reg) {
            0 => 'a',
            1 => 'c',
            2, 7 => 'd',
            3, 5 => 'b',
            4, 6 => 's',
        },
    };
    out[1] = switch (W) {
        0 => switch (reg) {
            0...3 => 'l',
            else => 'h',
        },
        1 => switch (reg) {
            0...3 => 'x',
            4...5 => 'p',
            else => 'i',
        },
    };
    return out;
}

test "rmMap no displacement" {
    const TestVal = struct { rm: u3, out: []const u8 };
    const inputs = [_]TestVal{
        .{ .rm = 0, .out = "[bx + si]" },
        .{ .rm = 1, .out = "[bx + di]" },
        .{ .rm = 2, .out = "[bp + si]" },
        .{ .rm = 3, .out = "[bp + di]" },
        .{ .rm = 4, .out = "[si]" },
        .{ .rm = 5, .out = "[di]" },
        .{ .rm = 6, .out = "[{}]" },
        .{ .rm = 7, .out = "[bx]" },
    };
    for (inputs) |values| {
        var list = ArrayList(u8).init(std.testing.allocator);
        defer list.deinit();
        try rmMap(values.rm, 0, 0, &list);
        // print("{} {}", .{ @typeInfo(@TypeOf(list.items)), @typeInfo(@TypeOf(values.out)) });
        assert(mem.eql(u8, values.out, list.items));
    }
}

test "byte regMap" {
    const TestVal = struct { rm: u3, out: *const [2:0]u8 };
    const inputs = [_]TestVal{
        .{ .rm = 0, .out = "al" },
        .{ .rm = 1, .out = "cl" },
        .{ .rm = 2, .out = "dl" },
        .{ .rm = 3, .out = "bl" },
        .{ .rm = 4, .out = "ah" },
        .{ .rm = 5, .out = "ch" },
        .{ .rm = 6, .out = "dh" },
        .{ .rm = 7, .out = "bh" },
    };
    for (inputs) |values| {
        const out = regMap(values.rm, 0);
        assert(mem.eql(u8, &out, values.out));
    }
}

test "word regMap" {
    const TestVal = struct { rm: u3, out: *const [2:0]u8 };
    const inputs = [_]TestVal{
        .{ .rm = 0, .out = "ax" },
        .{ .rm = 1, .out = "cx" },
        .{ .rm = 2, .out = "dx" },
        .{ .rm = 3, .out = "bx" },
        .{ .rm = 4, .out = "sp" },
        .{ .rm = 5, .out = "bp" },
        .{ .rm = 6, .out = "si" },
        .{ .rm = 7, .out = "di" },
    };
    for (inputs) |values| {
        const out = regMap(values.rm, 1);
        assert(mem.eql(u8, &out, values.out));
    }
}
