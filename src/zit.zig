const std = @import("std");
const ArrayList = std.ArrayList;
const Bits = ArrayList(u1);
const Allocator = std.mem.Allocator;
const reverse = std.mem.reverse;

fn integer_to_Bits(raw : anytype, size: usize, allocator : Allocator) !Bits {
    var bits = Bits.init(allocator);
    var i : usize = 0;
    var copy = raw;
    while (i < size-1) : (i += 1) {
        try bits.append(@truncate(u1, copy));
        copy = copy >> 1;
    }
    try bits.append(@truncate(u1, copy));
    reverse(u1, bits.items);
    return bits;
}

fn to_Bits(raw : anytype, allocator: Allocator) !Bits {
    const typeinfo = @typeInfo(@TypeOf(raw));
    return switch (typeinfo) {
        .Int => try integer_to_Bits(raw, typeinfo.Int.bits, allocator),
        else => @compileError("Unsupported type")
    };
}

pub fn zit(raw_data : anytype, allocator: Allocator) !Zit {
    return Zit{
        .bits = try to_Bits(raw_data, allocator),
        .index = 0
    };
}

const ZitErrors = error {
    IndexOutOfRange
};

pub const Zit = struct {
    bits: Bits,
    index : usize,

    pub fn deinit(self: *Zit) void {
        self.bits.deinit();
    }

    fn does_forward_fit(self: *Zit, num: usize) bool {
        return self.index + num <= self.bits.items.len;
    }

    pub fn forward(self: *Zit, num: usize) ZitErrors!void {
        if(!self.does_forward_fit(num)) {
            return ZitErrors.IndexOutOfRange;
        }
        self.index += num;
    }

    pub fn move(self: *Zit, num: usize) ZitErrors!void {
        if(num >= self.bits.items.len) {
            return ZitErrors.IndexOutOfRange;
        }
        self.index = num;
    }

    pub fn rewind(self: *Zit, num: usize) ZitErrors!void {
        if(self.index - num < 0) {
            return ZitErrors.IndexOutOfRange;
        }
        self.index -= num;
    }

    fn take_int(self: *Zit, comptime T: type) ZitErrors!T {
        switch(@typeInfo(T).Int.signedness) {
            .signed => @compileError("negative integers unsupported yet"),
            .unsigned => {
                const size = @typeInfo(T).Int.bits;
                if(!self.does_forward_fit(size)) {
                    return ZitErrors.IndexOutOfRange;
                }
                var value : T = 0;
                var i : usize = 0;
                var slice = self.bits.items[self.index .. self.index + size];
                while( i < size) : ( i += 1 ) {
                    value = value << 1;
                    value += slice[i];
                }
                self.forward(size) catch unreachable;
                return value;
            }
        }
    }

    pub fn take(self: *Zit, comptime T: type) ZitErrors!T {
        return switch (@typeInfo(T)) {
            .Int => try self.take_int(T),
            else => @compileError("Unsupport type to take"),
        };
    }
};

const testing = std.testing;
const testing_allocator = testing.allocator;
const expect = testing.expect;
const expectEqual = testing.expectEqual;

test "with_u32" {
    const value : u32 = 0xFFFF;
    var zitter = try zit(value, testing_allocator);
    var first : u16 = try zitter.take(u16);
    var second : u16 = try zitter.take(u16);

    try expectEqual( @intCast(u16, 0), first);
    try expectEqual( @intCast(u16, 0xFFFF), second);

    defer zitter.deinit();
}