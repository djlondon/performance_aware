const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;

// 0-- -- -- -- 1--- --- -- 3-- 4--
//  10 00 10 DW  mod reg rm  LO  HI
// reg/mem to/from reg/mem
// if first_byte.startswith(100010)
// D - direction, src => (REG) (R/M)
// W - word (L,H) (X,P,I)
// mod - 00 no LO/HI (unless R/M=110), 01 LO, 10 LOHI, 11 reg (no LO/HI)

// 1011WREG
// if the first 4 bytes 1011 (0xB), then the next four represent WREG */

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
