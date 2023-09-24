const std = @import("std");
const testing = std.testing;
const Log2T = std.math.Log2Int;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const ParseErrors = error{ NotEnoughInput, NotFound, NotAlignedWhenExpectingAlignement };
pub const ParseErrorsDynamicMemory = ParseErrors || Allocator.Error;

pub const Parser = struct {
    raw: []const u8,
    offset: usize,

    pub fn init(raw: []const u8) Parser {
        return Parser{ .raw = raw, .offset = 0 };
    }

    fn mask(v: anytype) @TypeOf(v) {
        return std.math.maxInt(@TypeOf(v));
    }

    fn UT(comptime T: type) type {
        return std.meta.Int(std.builtin.Signedness.unsigned, @bitSizeOf(T));
    }

    fn read(self: Parser, comptime T: type) ParseErrors!T {
        const size = @bitSizeOf(T);
        switch (@typeInfo(T)) {
            .Int, .Float => {
                const currentIndex = self.offset / 8;
                if (currentIndex + size / 8 > self.raw.len) {
                    return ParseErrors.NotEnoughInput;
                }
                var offsetedBuffer = self.raw[currentIndex..];
                var currentShift = self.offset % 8;

                const numBytesToWorkWith = if ((size + currentShift) % 8 == 0)
                    ((size + currentShift) / 8)
                else
                    ((size + currentShift) / 8) + 1;

                var temp: UT(T) = 0;
                var lenToDecode = @as(usize, size);

                for (0..numBytesToWorkWith) |i| {
                    if ((currentShift + lenToDecode) > 8) {
                        const decoded: UT(T) = 8 - @as(UT(T), @truncate(currentShift));
                        temp += @truncate(offsetedBuffer[i] & mask(decoded));
                        currentShift = 0;

                        if ((lenToDecode - decoded > 8) and size > 8) {
                            temp = temp << 8;
                        } else {
                            temp = temp << @as(Log2T(T), @truncate(lenToDecode - decoded));
                        }
                        lenToDecode -= decoded;
                    } else {
                        temp += @truncate((offsetedBuffer[i] >> @truncate(8 - lenToDecode - currentShift)) & @as(UT(T), @truncate(mask(lenToDecode))));
                    }
                }
                return @bitCast(temp);
            },
            else => @compileError("not managed yet"),
        }
        return ParseErrors.NotEnoughInput;
    }

    pub fn forward(self: *Parser, bitsize: anytype) ParseErrors!void {
        const size = comptime if (@typeInfo(@TypeOf(bitsize)) == .Type) @bitSizeOf(bitsize) else bitsize;
        const new_pos = self.offset + size;
        const new_index = new_pos / 8;
        if (new_index > self.raw.len) {
            return ParseErrors.NotEnoughInput;
        }
        self.offset = new_pos;
    }

    pub fn rewind(self: *Parser, bitsize: anytype) ParseErrors!void {
        const size = if (@typeInfo(bitsize) == .Type) @bitSizeOf(bitsize) else bitsize;
        const new_pos = self.offset - size;
        if (new_pos < 0) {
            return ParseErrors.NotEnoughInput;
        }
        self.index = new_pos;
    }

    fn ff(self: *Parser, bitsize: usize) void {
        return self.forward(bitsize) catch unreachable;
    }

    pub fn parse(self: *Parser, comptime T: type) ParseErrors!T {
        const typeinfo = @typeInfo(T);
        return switch (typeinfo) {
            .Int, .Float => blk: {
                const r: T = try self.read(T);
                self.ff(@bitSizeOf(T));
                break :blk r;
            },
            .Optional => {
                try self.parse(typeinfo.Optional.child);
            },
            else => @compileError("not managed yet"),
        };
    }

    pub fn char(self: *Parser, c: u8) ParseErrors!u8 {
        const r = try self.read(u8);
        if (r != c) {
            return ParseErrors.NotFound;
        }
        self.ff(8);
        return r;
    }

    fn is_in(x: anytype, matches: []const @TypeOf(x)) bool {
        for (matches) |value| {
            if (value == x) {
                return true;
            }
        }
        return false;
    }

    pub fn aligned_is_a(self: *Parser, matches: []const u8) ParseErrors![]const u8 {
        if ((self.offset % 8) != 0) {
            return ParseErrors.NotAlignedWhenExpectingAlignement;
        }
        var start_found = false;
        var start: usize = 0;
        var stop: usize = 0;
        while (self.parse(u8)) |c| {
            if (is_in(c, matches)) {
                if (!start_found) {
                    start = (self.offset - 8) / 8;
                    stop = start + 1;
                    start_found = true;
                } else {
                    stop += 1;
                }
            } else {
                if (start_found) {
                    break;
                }
            }
        } else |err| {
            if (err != ParseErrors.NotEnoughInput) {
                return err;
            }
        }
        return self.raw[start..stop];
    }

    pub fn is_a(self: *Parser, allocator: Allocator, matches: []const u8) ParseErrorsDynamicMemory!ArrayList(u8) {
        var result = ArrayList(u8).init(allocator);
        errdefer result.deinit();
        var started = false;

        while (self.parse(u8)) |c| {
            if (is_in(c, matches)) {
                if (!started) {
                    started = true;
                }
                try result.append(c);
            } else {
                if (started) {
                    break;
                }
            }
        } else |err| {
            if (err != ParseErrors.NotEnoughInput) {
                return err;
            }
        }
        return result;
    }
};

const expectEqual = testing.expectEqual;
const expectError = testing.expectError;
const expectEqualSlices = testing.expectEqualSlices;

test "char" {
    const first = "abc";
    var parser = Parser.init(first[0..]);
    var r = try parser.char('a');
    try expectEqual(@as(u8, 'a'), r);
    try expectEqual(@as(usize, 8), parser.offset);
    try expectEqual(@as(u8, 'a'), r);

    const second = " abc";
    parser = Parser.init(second[0..]);
    var re = parser.char('a');
    try expectError(ParseErrors.NotFound, re);
    try expectEqual(@as(usize, 0), parser.offset);

    const third = "bc";
    parser = Parser.init(third[0..]);
    re = parser.char('a');
    try expectError(ParseErrors.NotFound, re);
    try expectEqual(@as(usize, 0), parser.offset);

    const last = "";
    parser = Parser.init(last[0..]);
    re = parser.char('a');
    try expectError(ParseErrors.NotEnoughInput, re);
    try expectEqual(@as(usize, 0), parser.offset);
}

test "is_a" {
    const matches: []const u8 = "1234567890ABCDEF";
    const Check = struct { input: []const u8, expected: []const u8 };
    const tests = [_]Check{ Check{ .input = "123 and voila", .expected = "123" }, Check{ .input = "DEADBEEF and others", .expected = "DEADBEEF" }, Check{ .input = "BADBABEsomething", .expected = "BADBABE" }, Check{ .input = "D15EA5E", .expected = "D15EA5E" } };
    for (tests) |item| {
        var parser = Parser.init(item.input);
        var r = try parser.aligned_is_a(matches);
        try expectEqualSlices(u8, item.expected, r);
    }

    var alloc = testing.allocator;

    for (tests) |item| {
        var parser = Parser.init(item.input);
        var r = try parser.is_a(alloc, matches);
        defer r.deinit();
        try expectEqualSlices(u8, item.expected, r.items);
    }
}

test "casting" {
    const first = "abc";
    var parser = Parser.init(first[0..]);
    var r: u16 = try parser.parse(u5);
    _ = r;
}
