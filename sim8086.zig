const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const print = std.debug.print;
const fmt = std.fmt;
const ArrayList = std.ArrayList;

const Args = struct { filePath: []const u8 };

fn processArgs() error{NoFile}!Args {
    var args = std.process.args();
    _ = args.skip();
    const filePath = args.next() orelse return error.NoFile;
    return Args{ .filePath = filePath };
}

fn readFile(filePath: []const u8) !std.fs.File.Reader {
    const file = try std.fs.cwd().openFile(filePath, .{});
    return file.reader();
}

pub fn main() !void {
    const args = try processArgs();
    const fileReader = try readFile(args.filePath);
    defer fileReader.context.close();
    // TODO: does buffer size make sense here? investigate other allocators
    var buffer: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    var list = ArrayList(u8).init(allocator);
    defer list.deinit();
    while (true) {
        init(&fileReader, &list.writer()) catch |err| {
            switch (err) {
                error.EndOfStream => break,
                else => |leftover_err| return leftover_err,
            }
        };
    }
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = bw.writer();
    try stdout.print("bits 16\n\n", .{});
    try stdout.print("{s}", .{list.items});
    try bw.flush();
}

pub fn init(fileReader: *const std.fs.File.Reader, writer: *const ArrayList(u8).Writer) !void {
    const byte = try fileReader.readByte();

    for (jump_table) |t| {
        if (byte == t.pattern) {
            var ji = RETInstruction{ .fileReader = fileReader, .writer = writer, .op = t.op };
            try ji.parse();
            return;
        }
    }

    for (table) |t| {
        if (byte >> t.shift == t.pattern) {
            var i = Instruction{ .fileReader = fileReader, .writer = writer, .instruction_type = t.ins, .op = t.op };
            i.firstByte(byte);
            try i.parse();
            return;
        }
    }
    return error.UnimplementedInstruction;
}

const InstructionType = enum {
    /// Address to Address MOV instruction:
    /// reg to/from mem or reg to/from reg
    /// e.g. mov cx, bx; mov al, [bx + si]
    /// ------10 76  543 210 [MOD=1|2] [--MOD=2]
    /// 100010DW mod reg r/m LO......  HI......
    /// RM=6 and mod=0 => direct address from HILO
    AddrToAddr,
    /// -------0 76  543 210 [MOD=1|2] [--MOD=2] ---- [--w=1]
    /// 1100011W mod 000 r/m LO......  HI......  data  data
    ImmediateToAddr,
    /// +---3210 +------+ [--w=1]
    /// 1011WREG data     data
    ImmediateToReg,
    /// +------0 +------+ +------+
    /// 1010000W addr-lo addr-hi
    MemToAcc,
    /// +------0 +------+ +------+
    /// 1010001W addr-lo addr-hi
    AccToMem,
    /// +------0 +------+ [--w=1]
    /// -------w data     data
    ImmediateToAcc,
};

const Op = enum {
    MOV,
    ADD,
    SUB,
    CMP,
    UNDEF,

    pub fn str(self: Op) !*const [3:0]u8 {
        return switch (self) {
            Op.MOV => "mov",
            Op.ADD => "add",
            Op.SUB => "sub",
            Op.CMP => "cmp",
            Op.UNDEF => error.UndefinedOp,
        };
    }
};

const RET = enum {
    JNZ,
    JE,
    JL,
    JLE,
    JB,
    JBE,
    JP,
    JO,
    JS,
    JNE,
    JNL,
    JG,
    JNB,
    JA,
    JNP,
    JNO,
    JNS,
    LOOP,
    LOOPZ,
    LOOPNZ,
    JCXZ,

    pub fn str(self: RET) []const u8 {
        return switch (self) {
            RET.JNZ => "jnz",
            RET.JE => "je",
            RET.JL => "jl",
            RET.JLE => "jle",
            RET.JB => "jb",
            RET.JBE => "jbe",
            RET.JP => "jp",
            RET.JO => "jo",
            RET.JS => "js",
            RET.JNE => "jne",
            RET.JNL => "jnl",
            RET.JG => "jg",
            RET.JNB => "jnb",
            RET.JA => "ja",
            RET.JNP => "jnp",
            RET.JNO => "jno",
            RET.JNS => "jns",
            RET.LOOP => "loop",
            RET.LOOPZ => "loopz",
            RET.LOOPNZ => "loopnz",
            RET.JCXZ => "jcxz",
        };
    }
};

const InstructionTable = struct {
    pattern: u8,
    shift: u3,
    ins: InstructionType,
    op: Op,
};
const table = [_]InstructionTable{
    .{ .pattern = 0b0001011, .shift = 4, .ins = InstructionType.ImmediateToReg, .op = Op.MOV },
    .{ .pattern = 0b0100010, .shift = 2, .ins = InstructionType.AddrToAddr, .op = Op.MOV },
    // In this case, the op is determined by the second byte, op can be ADD, SUB or CMP
    .{ .pattern = 0b100000, .shift = 2, .ins = InstructionType.ImmediateToAddr, .op = Op.UNDEF },
    .{ .pattern = 0b0001110, .shift = 2, .ins = InstructionType.AddrToAddr, .op = Op.CMP },
    .{ .pattern = 0b0000000, .shift = 2, .ins = InstructionType.AddrToAddr, .op = Op.ADD },
    .{ .pattern = 0b0001010, .shift = 2, .ins = InstructionType.AddrToAddr, .op = Op.SUB },
    .{ .pattern = 0b1100011, .shift = 1, .ins = InstructionType.ImmediateToAddr, .op = Op.MOV },
    .{ .pattern = 0b1010000, .shift = 1, .ins = InstructionType.MemToAcc, .op = Op.MOV },
    .{ .pattern = 0b1010001, .shift = 1, .ins = InstructionType.AccToMem, .op = Op.MOV },
    .{ .pattern = 0b0000000, .shift = 2, .ins = InstructionType.AddrToAddr, .op = Op.ADD },
    .{ .pattern = 0b0000010, .shift = 1, .ins = InstructionType.ImmediateToAcc, .op = Op.ADD },
    .{ .pattern = 0b0010110, .shift = 1, .ins = InstructionType.ImmediateToAcc, .op = Op.SUB },
    .{ .pattern = 0b0011110, .shift = 1, .ins = InstructionType.ImmediateToAcc, .op = Op.CMP },
};

const RETInstructionTable = struct {
    pattern: u8,
    op: RET,
};

const jump_table = [_]RETInstructionTable{
    .{ .pattern = 0b01110100, .op = RET.JE },
    .{ .pattern = 0b01111100, .op = RET.JL },
    .{ .pattern = 0b01111110, .op = RET.JLE },
    .{ .pattern = 0b01110010, .op = RET.JB },
    .{ .pattern = 0b01110110, .op = RET.JBE },
    .{ .pattern = 0b01111010, .op = RET.JP },
    .{ .pattern = 0b01110000, .op = RET.JO },
    .{ .pattern = 0b01111000, .op = RET.JS },
    .{ .pattern = 0b01110101, .op = RET.JNE },
    .{ .pattern = 0b01111101, .op = RET.JNL },
    .{ .pattern = 0b01111111, .op = RET.JG },
    .{ .pattern = 0b01110011, .op = RET.JNB },
    .{ .pattern = 0b01110111, .op = RET.JA },
    .{ .pattern = 0b01111011, .op = RET.JNP },
    .{ .pattern = 0b01110001, .op = RET.JNO },
    .{ .pattern = 0b01111001, .op = RET.JNS },
    .{ .pattern = 0b11100010, .op = RET.LOOP },
    .{ .pattern = 0b11100001, .op = RET.LOOPZ },
    .{ .pattern = 0b11100000, .op = RET.LOOPNZ },
    .{ .pattern = 0b11100011, .op = RET.JCXZ },
};

const RETInstruction = struct {
    const Self = @This();
    fileReader: *const std.fs.File.Reader,
    writer: *const ArrayList(u8).Writer,
    op: RET,
    offset: i8 = undefined,

    pub fn parse(self: *Self) !void {
        self.offset = @bitCast(try self.fileReader.readByte());
        try self.str();
    }

    fn str(self: *Self) !void {
        // nasm requires the offset to be in form $+2+(offset)
        // where 2 represents the instruction length since all RET operations are 2 bytes long
        try self.writer.print("{s} $+2+{}\n", .{ self.op.str(), self.offset });
    }
};

const Instruction = struct {
    const Self = @This();
    fileReader: *const std.fs.File.Reader,
    writer: *const ArrayList(u8).Writer,
    instruction_type: InstructionType,
    op: Op,
    s: u1 = 0, // same as if doesn't exist
    d: u1 = undefined,
    w: u1 = undefined,
    mod_: u2 = undefined,
    reg: u3 = undefined,
    rm: u3 = undefined,
    disp_lo: i8 = undefined,
    disp: i16 = undefined,
    data_lo: i8 = undefined,
    data: i16 = undefined,

    pub fn parse(self: *Self) !void {
        switch (self.instruction_type) {
            InstructionType.AddrToAddr => {
                self.modRegRmByte(try self.fileReader.readByte());
                if (self.mod_ == 1 or self.mod_ == 2 or (self.rm == 6 and self.mod_ == 0)) {
                    self.dispLoByte(try self.fileReader.readByte());
                }
                if (self.mod_ == 2 or (self.rm == 6 and self.mod_ == 0)) {
                    self.dispHiByte(try self.fileReader.readByte());
                }
            },
            InstructionType.ImmediateToReg, InstructionType.ImmediateToAcc => {
                self.dataLoByte(try self.fileReader.readByte());
                if (self.w == 1) {
                    self.dataHiByte(try self.fileReader.readByte());
                }
            },
            InstructionType.ImmediateToAddr => {
                try self.modRmByte(try self.fileReader.readByte());
                if (self.mod_ == 1 or self.mod_ == 2 or (self.rm == 6 and self.mod_ == 0)) {
                    self.dispLoByte(try self.fileReader.readByte());
                }
                if (self.mod_ == 2 or (self.rm == 6 and self.mod_ == 0)) {
                    self.dispHiByte(try self.fileReader.readByte());
                }
                self.dataLoByte(try self.fileReader.readByte());
                if (self.w == 1 and self.s == 0) {
                    self.dataHiByte(try self.fileReader.readByte());
                }
            },
            InstructionType.MemToAcc, InstructionType.AccToMem => {
                self.dataLoByte(try self.fileReader.readByte());
                self.dataHiByte(try self.fileReader.readByte());
            },
        }
        try self.str();
    }

    fn str(self: *Self) !void {
        var buffer: [30]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const allocator = fba.allocator();
        var rm = ArrayList(u8).init(allocator);
        defer rm.deinit();
        switch (self.instruction_type) {
            (InstructionType.AddrToAddr) => {
                const disp: i16 = switch (self.mod_) {
                    1 => self.disp_lo,
                    else => self.disp,
                };
                try rmMap(self.rm, self.mod_, self.w, disp, &rm.writer());
                const reg = regMap(self.reg, self.w);
                if (self.d == 1) {
                    try self.writer.print("{s} {s}, {s}\n", .{ try self.op.str(), reg, rm.items });
                } else {
                    try self.writer.print("{s} {s}, {s}\n", .{ try self.op.str(), rm.items, reg });
                }
            },
            (InstructionType.ImmediateToReg) => {
                const reg = regMap(self.reg, self.w);
                const data = switch (self.w) {
                    0 => self.data_lo,
                    1 => self.data,
                };
                try self.writer.print("{s} {s}, {}\n", .{ try self.op.str(), reg, data });
            },
            InstructionType.ImmediateToAcc => {
                const data = switch (self.w) {
                    0 => self.data_lo,
                    1 => self.data,
                };
                const acc = switch (self.w) {
                    0 => "al",
                    1 => "ax",
                };
                try self.writer.print("{s} {s}, {}\n", .{ try self.op.str(), acc, data });
            },
            (InstructionType.ImmediateToAddr) => {
                try rmMap(self.rm, self.mod_, self.w, self.disp, &rm.writer());
                const data = switch (self.w) {
                    0 => self.data_lo,
                    1 => self.data,
                };
                // TODO: work out how byte and word should be determined
                // this doesn't always match the listings
                const size = switch (self.mod_) {
                    0, 1 => " byte",
                    2 => " word",
                    else => "",
                };
                try self.writer.print("{s} {s},{s} {}\n", .{ try self.op.str(), rm.items, size, data });
            },
            InstructionType.MemToAcc, InstructionType.AccToMem => {
                const acc = switch (self.w) {
                    0 => "al",
                    1 => "ax",
                };
                if (self.instruction_type == InstructionType.MemToAcc) {
                    try self.writer.print("{s} {s}, [{}]\n", .{ try self.op.str(), acc, self.data });
                } else {
                    try self.writer.print("{s} [{}], {s}\n", .{ try self.op.str(), self.data, acc });
                }
            },
        }
    }

    fn firstByte(self: *Self, byte: u8) void {
        switch (self.instruction_type) {
            InstructionType.AddrToAddr => {
                // 1000_10DW
                self.d = @truncate(byte >> 1);
                self.w = @truncate(byte);
            },
            InstructionType.ImmediateToAddr => {
                self.w = @truncate(byte);
                if (self.op != Op.MOV) {
                    self.s = @truncate(byte >> 1);
                }
            },
            InstructionType.MemToAcc, InstructionType.AccToMem, InstructionType.ImmediateToAcc => {
                // XXXX_XXXW
                // XXXX_XXSW
                self.w = @truncate(byte);
            },
            InstructionType.ImmediateToReg => {
                // 1011WREG
                self.reg = @truncate(byte);
                self.w = @truncate(byte >> 3);
            },
        }
    }

    fn modRegRmByte(self: *Self, byte: u8) void {
        // 76  543 210
        // MOD REG R/M
        self.mod_ = @truncate(byte >> 6);
        self.reg = @truncate(byte >> 3);
        self.rm = @truncate(byte);
    }

    fn dispLoByte(self: *Self, byte: u8) void {
        self.disp_lo = @bitCast(byte);
        self.disp = byte;
    }

    fn dispHiByte(self: *Self, byte: u8) void {
        self.disp += (@as(i16, byte) << 8);
    }

    fn dataLoByte(self: *Self, byte: u8) void {
        self.data_lo = @bitCast(byte);
        self.data = byte;
    }

    fn dataHiByte(self: *Self, byte: u8) void {
        self.data += (@as(i16, byte) << 8);
    }

    fn modRmByte(self: *Self, byte: u8) !void {
        // 76  543 210
        // MOD 000 R/M
        const mid: u3 = @truncate(byte >> 3);
        if (self.op != Op.MOV) {
            self.op = switch (mid) {
                0 => Op.ADD,
                5 => Op.SUB,
                7 => Op.CMP,
                else => return error.UnimplementedInstruction,
            };
        }
        self.mod_ = @truncate(byte >> 6);
        self.rm = @truncate(byte);
    }
};

/// Given RM, MOD and W, determine the address.
/// Writes result to out.
/// If MOD = 011, this is the same as regMap.
fn rmMap(rm: u3, mod_: u2, W: u1, disp: i16, writer: *const ArrayList(u8).Writer) !void {
    if (mod_ == 3) {
        try writer.print("{s}", .{&regMap(rm, W)});
        return;
    }
    if (rm == 6 and mod_ == 0) {
        try writer.print("[{}", .{disp});
    } else {
        try writer.print("[{s}", .{switch (rm) {
            0 => "bx + si",
            1 => "bx + di",
            2 => "bp + si",
            3 => "bp + di",
            4 => "si",
            5 => "di",
            6 => "bp",
            7 => "bx",
        }});
    }
    if (disp == 0 or mod_ == 0) {
        try writer.print("]", .{});
    } else {
        try writer.print(" + {}]", .{disp});
    }
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
        .{ .rm = 6, .out = "[0]" },
        .{ .rm = 7, .out = "[bx]" },
    };
    for (inputs) |values| {
        var list = ArrayList(u8).init(std.testing.allocator);
        defer list.deinit();
        try rmMap(values.rm, 0, 0, 0, &list.writer());
        assert(mem.eql(u8, values.out, list.items));
    }
}

test "rmMap displacement" {
    const TestVal = struct { rm: u3, out: []const u8 };
    const inputs = [_]TestVal{
        .{ .rm = 0, .out = "[bx + si + 257]" },
        .{ .rm = 1, .out = "[bx + di + 257]" },
        .{ .rm = 2, .out = "[bp + si + 257]" },
        .{ .rm = 3, .out = "[bp + di + 257]" },
        .{ .rm = 4, .out = "[si + 257]" },
        .{ .rm = 5, .out = "[di + 257]" },
        .{ .rm = 7, .out = "[bx + 257]" },
    };
    for (inputs) |values| {
        var list = ArrayList(u8).init(std.testing.allocator);
        defer list.deinit();
        try rmMap(values.rm, 2, 0, 257, &list.writer());
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
