const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;

// 0-- -- -- -- 1--- --- -- 3-- 4--
//  10 00 10 DW  mod reg rm  LO  HI
// reg/mem to/from reg/mem
// if first_byte.startswith(100010)
// D - direction, src => (REG) (R/M)
// W - word (L,H) (X,P,I)
// mod - 00 no LO/HI, 01 LO, 10 LOHI, 11 LOHI (reg)

// 1011WREG
// if the first 4 bytes 1011 (0xB), then the next four represent WREG */

fn regMap(rm: u3, W: u1) [2]u8 {
    var out: [2]u8 = undefined;
    if (rm == 0 or (rm == 4 and W == 0)) {
        out[0] = 'a';
    } else if (rm == 1 or (rm == 5 and W == 0)) {
        out[0] = 'c';
    } else if (rm == 2 or (rm == 6 and W == 0)) {
        out[0] = 'd';
    } else if (rm == 3 or (rm == 7 and W == 0)) {
        out[0] = 'b';
    } else if (W == 1) {
        if (rm == 4)
            out[0] = 's';
        if (rm == 5)
            out[0] = 'b';
        if (rm == 6)
            out[0] = 's';
        if (rm == 7)
            out[0] = 'd';
    }
    // out[1]
    if (W == 0) {
        if (rm < 4) {
            out[1] = 'l';
        } else {
            out[1] = 'h';
        }
    }
    if (W == 1) {
        if (rm < 4) {
            out[1] = 'x';
        } else if (rm < 6) {
            out[1] = 'p';
        } else {
            out[1] = 'i';
        }
    }
    return out;
}

test "regMap" {
    const out = regMap(0, 0);
    assert(mem.eql(u8, &out, "al"));
}
