const std = @import("std");
const fmt = std.fmt;

/// A parser that consumes one full reply and discards it. It's written as a
/// dedicated parser because it doesn't require recursion to consume the right
/// amount of input. Originally this was implemented as a type case inside
/// each t_TYPE parser, but it caused errorset inference to break.
/// Additionally, the compiler probably would not know that it can the
/// recursive version can become a loop. Error replies don't get consumed and
/// cause error.GotErrorReply. This parser has different method names and is
/// the only one that doesn't recur through the root parser.
pub const VoidParser = struct {
    pub fn discardAttributes(msg: var) !void {
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
        size *= 2;

        var i: usize = 0;
        while (i < size) : (i += 1) {
            try discardOne(try msg.readByte(), msg);
        }
    }

    pub fn discardOne(tag: u8, msg: var) !void {
        // When we start, we have one item to consume.
        // As we inspect it we might discover that it's a container and have to
        // increase our items count.
        var itemTag = tag;
        var itemsToConsume: usize = 1;
        while (itemsToConsume > 0) {
            itemsToConsume -= 1;
            switch (itemTag) {
                else => std.debug.panic("Found `{}` in the *VOID* parser's switch." ++
                    " Probably a bug in a type that implements `Redis.Parser`.", itemTag),
                '-', '!' => return error.GotErrorReply,
                '_' => try msg.skipBytes(2), // `_\r\n`
                '#' => try msg.skipBytes(3), // `#t\r\n`, `#t\r\n`
                '$', '=' => {
                    // Lenght-prefixed string
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
                    var size = try fmt.parseInt(usize, buf[0..end], 10);
                    try msg.skipBytes(1 + size + 2);
                },
                ':', ',', '+' => {
                    // Simple element with final `\r\n`
                    var ch = try msg.readByte();
                    while (ch != '\n') ch = try msg.readByte();
                },
                '|' => {
                    // Attributes are metadata that precedes a proper reply
                    // item and do not count towards the original
                    // `itemsToConsume` count. Consume the attribute element
                    // without counting the current item as consumed.

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
                    size *= 2;

                    // Add all the new items to the pile that needs to be
                    // consumed, plus the one that we did not consume this
                    // loop.
                    itemsToConsume += size + 1;
                },
                '*', '%' => {
                    // Lists, Maps

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

                    // the '|' case is handled in the beginning
                    if (tag == '%') size *= 2;
                    itemsToConsume += size;
                },
            }

            // If we still have items to consume, read the tag.
            if (itemsToConsume > 0) itemTag = try msg.readByte();
        }
        return;
    }
};