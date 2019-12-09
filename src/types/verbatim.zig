const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const Verbatim = struct {
    format: Format,
    string: []u8,

    pub const Format = union(enum) {
        Simple: void,
        Err: void,
        Verbatim: [3]u8,
    };

    pub const Redis = struct {
        pub const Parser = struct {
            pub fn parse(tag: u8, comptime rootParser: type, msg: var) !Verbatim {
                @compileError("Verbatim requires an allocator, use `parseAlloc`.");
            }

            pub fn destroy(self: Verbatim, comptime _: type, allocator: *Allocator) void {
                allocator.free(self.string);
            }

            pub fn parseAlloc(tag: u8, comptime rootParser: type, allocator: *Allocator, msg: var) !Verbatim {
                switch (tag) {
                    else => return error.DecodingError,
                    '$', '+' => return Verbatim{
                        .format = Format{ .Simple = {} },
                        .string = try rootParser.parseAllocFromTag([]u8, tag, allocator, msg),
                    },
                    '=' => {
                        // TODO: write real implementation
                        var buf: [100]u8 = undefined;
                        var end: usize = 0;
                        for (buf) |*elem, i| {
                            const ch = try msg.readByte();
                            elem.* = ch;
                            if (ch == '\r') {
                                end = i;
                                break;
                            }
                        }

                        try msg.skipBytes(1);
                        var size = try fmt.parseInt(usize, buf[0..end], 10);

                        // We must consider the case in which a malformed
                        // verbatim string is received. By the protocol standard
                        // a verbatim string must start with a `<3 letter type>:`
                        // prefix, but since modules will be able to produce
                        // this kind of data, we should protect ourselves
                        // from potential errors.
                        var format: Format = undefined;
                        if (size >= 4) {
                            format = Format{
                                .Verbatim = [3]u8{
                                    try msg.readByte(),
                                    try msg.readByte(),
                                    try msg.readByte(),
                                },
                            };

                            // Skip the `:` character, subtract what we consumed
                            try msg.skipBytes(1);
                            size -= 4;
                        } else {
                            format = Format{ .Err = {} };
                        }

                        var res = try allocator.alloc(u8, size);
                        errdefer allocator.free(res);

                        try msg.readNoEof(res[0..size]);
                        try msg.skipBytes(2);

                        return Verbatim{ .format = format, .string = res };
                    },
                }
            }
        };
    };
};

test "verbatim" {
    const parser = @import("../parser.zig").RESP3Parser;
    const allocator = std.heap.direct_allocator;

    {
        const reply = try Verbatim.Redis.Parser.parseAlloc('+', parser, allocator, &MakeSimpleString().stream);
        testing.expectEqualSlices(u8, "Yayyyy I'm a string!", reply.string);
        switch (reply.format) {
            else => unreachable,
            .Simple => {},
        }
    }

    {
        const reply = try Verbatim.Redis.Parser.parseAlloc('$', parser, allocator, &MakeBlobString().stream);
        testing.expectEqualSlices(u8, "Hello World!", reply.string);
        switch (reply.format) {
            else => unreachable,
            .Simple => {},
        }
    }

    {
        const reply = try Verbatim.Redis.Parser.parseAlloc('=', parser, allocator, &MakeVerbatimString().stream);
        testing.expectEqualSlices(u8, "Oh hello there!", reply.string);
        switch (reply.format) {
            else => unreachable,
            .Verbatim => |format| testing.expectEqualSlices(u8, "txt", &format),
        }
    }

    {
        const reply = try Verbatim.Redis.Parser.parseAlloc('=', parser, allocator, &MakeBadVerbatimString().stream);
        testing.expectEqualSlices(u8, "t", reply.string);
        switch (reply.format) {
            else => unreachable,
            .Err => {},
        }
    }

    {
        const reply = try Verbatim.Redis.Parser.parseAlloc('=', parser, allocator, &MakeBadVerbatimString2().stream);
        testing.expectEqualSlices(u8, "", reply.string);
        switch (reply.format) {
            else => unreachable,
            .Verbatim => |format| testing.expectEqualSlices(u8, "mkd", &format),
        }
    }
}

fn MakeSimpleString() std.io.SliceInStream {
    return std.io.SliceInStream.init("+Yayyyy I'm a string!\r\n"[1..]);
}
fn MakeBlobString() std.io.SliceInStream {
    return std.io.SliceInStream.init("$12\r\nHello World!\r\n"[1..]);
}
fn MakeVerbatimString() std.io.SliceInStream {
    return std.io.SliceInStream.init("=19\r\ntxt:Oh hello there!\r\n"[1..]);
}
fn MakeBadVerbatimString() std.io.SliceInStream {
    return std.io.SliceInStream.init("=1\r\nt\r\n"[1..]);
}
fn MakeBadVerbatimString2() std.io.SliceInStream {
    return std.io.SliceInStream.init("=4\r\nmkd:\r\n"[1..]);
}
