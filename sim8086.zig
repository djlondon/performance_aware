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
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    var list = ArrayList(u8).init(allocator);
    defer list.deinit();
    while (true) {
        var ins = Instruction.init(&fileReader, &list.writer());
        if (ins) |*ins_| {
            try ins_.parse();
        } else |err| switch (err) {
            error.EndOfStream => break,
            else => |leftover_err| return leftover_err,
        }
    }
    print("bits 16\n\n", .{});
    print("{s}", .{list.items});
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
};

const Op = enum {
    MOV,
    ADD,
    SUB,
    CMP,

    pub fn str(self: Op) *const [3:0]u8 {
        return switch (self) {
            Op.MOV => "mov",
            Op.ADD => "add",
            Op.SUB => "sub",
            Op.CMP => "cmp",
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
    .{ .pattern = 0b0100010, .shift = 2, .ins = InstructionType.AddrToAddr, .op = Op.MOV },
    .{ .pattern = 0b1100011, .shift = 1, .ins = InstructionType.ImmediateToAddr, .op = Op.MOV },
    .{ .pattern = 0b0001011, .shift = 4, .ins = InstructionType.ImmediateToReg, .op = Op.MOV },
    .{ .pattern = 0b1010000, .shift = 1, .ins = InstructionType.MemToAcc, .op = Op.MOV },
    .{ .pattern = 0b1010001, .shift = 1, .ins = InstructionType.AccToMem, .op = Op.MOV },
    .{ .pattern = 0b0000000, .shift = 2, .ins = InstructionType.AddrToAddr, .op = Op.ADD },
    .{ .pattern = 0b0000010, .shift = 1, .ins = InstructionType.MemToAcc, .op = Op.ADD },
    .{ .pattern = 0b0001010, .shift = 2, .ins = InstructionType.AddrToAddr, .op = Op.SUB },
    .{ .pattern = 0b0010110, .shift = 1, .ins = InstructionType.MemToAcc, .op = Op.SUB },
    .{ .pattern = 0b0001110, .shift = 2, .ins = InstructionType.AddrToAddr, .op = Op.CMP },
    .{ .pattern = 0b0011110, .shift = 1, .ins = InstructionType.MemToAcc, .op = Op.CMP },
    // In this case, the op is determined by the second byte, op can be ADD, SUB or CMP
    .{ .pattern = 0b0100000, .shift = 2, .ins = InstructionType.ImmediateToAddr, .op = undefined },
};

const Instruction = struct {
    const Self = @This();
    fileReader: *const std.fs.File.Reader,
    writer: *const ArrayList(u8).Writer,
    instruction_type: InstructionType,
    op: Op,
    // TODO: implement s
    s: u1 = undefined,
    d: u1 = undefined,
    w: u1 = undefined,
    mod_: u2 = undefined,
    reg: u3 = undefined,
    rm: u3 = undefined,
    disp_lo: i8 = undefined,
    disp: i16 = undefined,
    data_lo: i8 = undefined,
    data: i16 = undefined,

    pub fn init(fileReader: *const std.fs.File.Reader, writer: *const ArrayList(u8).Writer) !Self {
        var instruction_type: InstructionType = undefined;
        var op: Op = undefined;
        const byte = try fileReader.readByte();

        for (table) |t| {
            if (byte >> t.shift == t.pattern) {
                instruction_type = t.ins;
                op = t.op;
                break;
            }
        } else {
            return error.UnimplementedInstruction;
        }
        var ret = Self{ .fileReader = fileReader, .writer = writer, .instruction_type = instruction_type, .op = op };
        ret.firstByte(byte);
        return ret;
    }

    pub fn parse(self: *Self) !void {
        switch (self.instruction_type) {
            InstructionType.AddrToAddr => {
                self.secondByte(try self.fileReader.readByte());
                if (self.mod_ == 1 or self.mod_ == 2 or (self.rm == 6 and self.mod_ == 0)) {
                    self.thirdByte(try self.fileReader.readByte());
                }
                if (self.mod_ == 2 or (self.rm == 6 and self.mod_ == 0)) {
                    self.fourthByte(try self.fileReader.readByte());
                }
            },
            InstructionType.ImmediateToReg => {
                self.immRegSecondByte(try self.fileReader.readByte());
                if (self.w == 1) {
                    self.immRegThirdByte(try self.fileReader.readByte());
                }
            },
            InstructionType.ImmediateToAddr => {
                try self.immAddrSecondByte(try self.fileReader.readByte());
                if (self.mod_ == 1 or self.mod_ == 2 or (self.rm == 6 and self.mod_ == 0)) {
                    self.thirdByte(try self.fileReader.readByte());
                }
                if (self.mod_ == 2 or (self.rm == 6 and self.mod_ == 0)) {
                    self.fourthByte(try self.fileReader.readByte());
                }
                self.immRegSecondByte(try self.fileReader.readByte());
                if (self.w == 1) {
                    self.immRegThirdByte(try self.fileReader.readByte());
                }
            },
            InstructionType.MemToAcc, InstructionType.AccToMem => {
                self.immRegSecondByte(try self.fileReader.readByte());
                self.immRegThirdByte(try self.fileReader.readByte());
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
                    try self.writer.print("{s} {s}, {s}\n", .{ self.op.str(), reg, rm.items });
                } else {
                    try self.writer.print("{s} {s}, {s}\n", .{ self.op.str(), rm.items, reg });
                }
            },
            (InstructionType.ImmediateToReg) => {
                const reg = regMap(self.reg, self.w);
                const data = switch (self.w) {
                    0 => self.data_lo,
                    1 => self.data,
                };
                try self.writer.print("{s} {s}, {}\n", .{ self.op.str(), reg, data });
            },
            (InstructionType.ImmediateToAddr) => {
                try rmMap(self.rm, self.mod_, self.w, self.disp, &rm.writer());
                const data = switch (self.w) {
                    0 => self.data_lo,
                    1 => self.data,
                };
                const size = if (self.w == 1) "word" else "byte";
                try self.writer.print("{s} {s}, {s} {}\n", .{ self.op.str(), rm.items, size, data });
            },
            InstructionType.MemToAcc, InstructionType.AccToMem => {
                const acc = switch (self.w) {
                    0 => "al",
                    1 => "ax",
                };
                if (self.instruction_type == InstructionType.MemToAcc) {
                    try self.writer.print("{s} {s}, [{}]\n", .{ self.op.str(), acc, self.data });
                } else {
                    try self.writer.print("{s} [{}], {s}\n", .{ self.op.str(), self.data, acc });
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
            InstructionType.ImmediateToAddr, InstructionType.MemToAcc, InstructionType.AccToMem => {
                // XXXX_XXXW
                // XXXX_XXSW
                self.w = @truncate(byte);
                if (self.op != Op.MOV) {
                    self.s = @truncate(byte >> 1);
                }
            },
            InstructionType.ImmediateToReg => {
                // 1011WREG
                self.reg = @truncate(byte);
                self.w = @truncate(byte >> 3);
            },
        }
    }

    fn secondByte(self: *Self, byte: u8) void {
        // 76  543 210
        // MOD REG R/M
        self.mod_ = @truncate(byte >> 6);
        self.reg = @truncate(byte >> 3);
        self.rm = @truncate(byte);
    }

    fn thirdByte(self: *Self, byte: u8) void {
        self.disp_lo = @bitCast(byte);
        self.disp = byte;
    }

    fn fourthByte(self: *Self, byte: u8) void {
        self.disp += (@as(i16, byte) << 8);
    }

    fn immRegSecondByte(self: *Self, byte: u8) void {
        self.data_lo = @bitCast(byte);
        self.data = byte;
    }

    fn immRegThirdByte(self: *Self, byte: u8) void {
        self.data += (@as(i16, byte) << 8);
    }

    fn immAddrSecondByte(self: *Self, byte: u8) !void {
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
