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
    print("{s}\n", .{list.items});
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
};

const Instruction = struct {
    const Self = @This();
    fileReader: *const std.fs.File.Reader,
    writer: *const ArrayList(u8).Writer,
    instruction_type: InstructionType,
    d: u1 = undefined,
    w: u1 = undefined,
    mod_: u2 = undefined,
    reg: u3 = undefined,
    rm: u3 = undefined,
    disp_lo: u8 = undefined,
    disp_hi: u8 = undefined,
    data_lo: i8 = undefined,
    data: i16 = undefined,

    pub fn init(fileReader: *const std.fs.File.Reader, writer: *const ArrayList(u8).Writer) !Self {
        var instruction_type: InstructionType = undefined;
        const byte = try fileReader.readByte();
        if (byte >> 2 == 0b100010) {
            instruction_type = InstructionType.AddrToAddr;
        } else if (byte >> 1 == 0b1100011) {
            instruction_type = InstructionType.ImmediateToAddr;
        } else if (byte >> 4 == 0b1011) {
            instruction_type = InstructionType.ImmediateToReg;
        } else {
            return error.UnimplementedInstruction;
        }
        var ret = Self{ .fileReader = fileReader, .writer = writer, .instruction_type = instruction_type };
        ret.firstByte(byte);
        return ret;
    }

    pub fn parse(self: *Self) !void {
        switch (self.instruction_type) {
            (InstructionType.AddrToAddr) => {
                self.secondByte(try self.fileReader.readByte());
                if (self.mod_ == 1 or self.mod_ == 2) {
                    self.thirdByte(try self.fileReader.readByte());
                }
                if (self.mod_ == 2) {
                    self.fourthByte(try self.fileReader.readByte());
                }
            },
            (InstructionType.ImmediateToReg) => {
                self.immRegSecondByte(try self.fileReader.readByte());
                if (self.w == 1) {
                    self.immRegThirdByte(try self.fileReader.readByte());
                }
            },
            else => return error.Uninmplemented,
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
                try rmMap(self.rm, self.mod_, self.w, self.disp_lo, self.disp_hi, &rm.writer());
                const reg = regMap(self.reg, self.w);
                if (self.d == 1) {
                    try self.writer.print("mov {s}, {s}\n", .{ reg, rm.items });
                } else {
                    try self.writer.print("mov {s}, {s}\n", .{ rm.items, reg });
                }
            },
            (InstructionType.ImmediateToReg) => {
                const reg = regMap(self.reg, self.w);
                const data = switch (self.w) {
                    0 => self.data_lo,
                    1 => self.data,
                };
                try self.writer.print("mov {s}, {}\n", .{ reg, data });
            },
            else => return error.Uninmplemented,
        }
    }

    fn firstByte(self: *Self, byte: u8) void {
        switch (self.instruction_type) {
            (InstructionType.AddrToAddr) => {
                // 1000_10DW
                self.d = @truncate(byte >> 1);
                self.w = @truncate(byte);
            },
            (InstructionType.ImmediateToAddr) => {
                // 1100_011W
                self.w = @truncate(byte);
            },
            (InstructionType.ImmediateToReg) => {
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
        self.disp_lo = byte;
    }

    fn fourthByte(self: *Self, byte: u8) void {
        self.disp_hi = byte;
    }

    fn immRegSecondByte(self: *Self, byte: u8) void {
        self.data_lo = @bitCast(byte);
        self.data = byte;
    }

    fn immRegThirdByte(self: *Self, byte: u8) void {
        self.data += (@as(i16, byte) << 8);
    }
};

/// Given RM, MOD and W, determine the address.
/// Writes result to out.
/// If MOD = 011, this is the same as regMap.
fn rmMap(rm: u3, mod_: u2, W: u1, disp_lo: u8, disp_hi: u8, writer: *const ArrayList(u8).Writer) !void {
    if (mod_ == 3) {
        try writer.print("{s}", .{&regMap(rm, W)});
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
        6 => if (mod_ == 0) "DA" else "bp",
        7 => "bx",
    };
    try writer.print("[{s}", .{ins});
    if ((disp_lo == 0 and disp_hi == 0) or mod_ == 0) {
        try writer.print("]", .{});
    } else if (mod_ == 1) {
        try writer.print(" + {}]", .{disp_lo});
    } else if (mod_ == 2) {
        // TODO: move this logic to byte parsing step
        try writer.print(" + {}]", .{(@as(u16, disp_hi) << 8) + @as(u16, disp_lo)});
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
        .{ .rm = 6, .out = "[DA]" },
        .{ .rm = 7, .out = "[bx]" },
    };
    for (inputs) |values| {
        var list = ArrayList(u8).init(std.testing.allocator);
        defer list.deinit();
        try rmMap(values.rm, 0, 0, 0, 0, &list.writer());
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
        try rmMap(values.rm, 2, 0, 0b1, 0b1, &list.writer());
        assert(mem.eql(u8, values.out, list.items));
    }
}

test "rmMap lo displacement" {
    const TestVal = struct { rm: u3, out: []const u8 };
    const inputs = [_]TestVal{
        .{ .rm = 0, .out = "[bx + si + 124]" },
        .{ .rm = 1, .out = "[bx + di + 124]" },
        .{ .rm = 2, .out = "[bp + si + 124]" },
        .{ .rm = 3, .out = "[bp + di + 124]" },
        .{ .rm = 4, .out = "[si + 124]" },
        .{ .rm = 5, .out = "[di + 124]" },
        .{ .rm = 7, .out = "[bx + 124]" },
    };
    for (inputs) |values| {
        var list = ArrayList(u8).init(std.testing.allocator);
        defer list.deinit();
        try rmMap(values.rm, 1, 0, 124, 0, &list.writer());
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
