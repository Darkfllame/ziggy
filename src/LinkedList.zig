const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn LinkedList(comptime T: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            value: T,
            next: ?*Node,
        };

        const Error = Allocator.Error || error{
            indexOutOfBounds,
        };

        allocator: Allocator,
        head: ?*Node = null,
        /// Get only, no set, if you do, imma go angry >:(
        length: usize = 0,

        pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, stream: anytype) !void {
            try stream.print("[{any}]{any}{{", .{ self.length, T });
            var current: ?*Node = self.head;
            while (current) |curr| : (current = curr.next) {
                try stream.print("{any}", .{curr.value});
                if (curr.next) |_|
                    try stream.print(" -> ", .{});
            }
            try stream.print("}}", .{});
        }
        pub fn jsonStringify(self: Self, stream: anytype) !void {
            try stream.print("[", .{});
            var current: ?*Node = self.head;
            while (current) |curr| : (current = curr.next) {
                try stream.print("{any}", .{curr.value});
                if (curr.next) |_|
                    try stream.print(",\n", .{});
            }
            try stream.print("]", .{});
        }
        pub fn jsonParse(allocator: std.mem.Allocator, source: *std.json.Scanner, _: std.json.ParseOptions) !Self {
            var tokens = LinkedList(std.json.Token).init(allocator);
            defer tokens.deinit();
            _ = try source.next();

            var token: std.json.Token = try source.next();
            var depth: u32 = 0;
            while (depth >= 0) : (token = source.next()) {
                switch (token) {
                    .array_begin => depth += 1,
                    .array_end => depth -= 1,
                    else => tokens.addElem(token) catch init(allocator),
                }
            }

            // TODO: parse tokens, don't forget objects dumbass
        }

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }
        pub fn deinit(self: Self) void {
            var current: ?*Node = self.head;
            while (current) |curr| {
                const next = curr.next;
                defer current = next;

                if (std.meta.hasFn(T, "deinit"))
                    curr.value.deinit();

                self.allocator.destroy(curr);
            }
        }

        fn getLast(self: Self) ?*Node {
            var current: ?*Node = self.head;
            while (current) |curr| {
                if (curr.next) |next| {
                    current = next;
                } else break;
            }
            return current;
        }
        pub fn recalculateLength(self: *Self) void {
            var i: usize = 0;
            var current: ?*Node = self.head;
            while (current) |curr| : (i += 1) {
                if (curr.next) |next|
                    current = next;
            }
            self.length = i;
        }

        pub fn addElem(self: *Self, value: T) Error!*T {
            const last = self.getLast();
            const new = try self.allocator.create(Node);
            errdefer self.allocator.destroy(new);
            new.value = value;
            new.next = null;
            if (last) |l| {
                l.next = new;
            } else {
                self.head = new;
            }
            self.length += 1;
            return &new.value;
        }
        pub fn removeElem(self: *Self, index: usize) Error!void {
            if (index > self.length - 1)
                return Error.indexOutOfBounds;
            var i: usize = 0;
            var last: ?*Node = null;
            var current: ?*Node = self.head;
            while (current) |curr| : (i += 1) {
                if (i >= index)
                    break;
                last = current;
                if (curr.next) |next|
                    current = next;
            }
            if (last) |l|
                l.next = current.?.next;
            self.allocator.destroy(current.?);
            self.length -= 1;
        }

        pub fn getElem(self: *Self, index: usize) Error!*T {
            if (index > self.length - 1)
                return Error.indexOutOfBounds;
            var i: usize = 0;
            var current: ?*Node = self.head;
            while (current) |curr| : (i += 1) {
                if (i >= index)
                    break;
                if (curr.next) |next|
                    current = next;
            }
            return &current.?.value;
        }

        // Iterator support
        pub usingnamespace struct {
            pub const LinkedListIterator = struct {
                node: ?Node,

                pub fn next(it: *LinkedListIterator) ?T {
                    if (it.node) |n| {
                        const retV = n.value;
                        it.node = n.next;
                        return retV;
                    }
                    return null;
                }
            };

            pub fn iterator(self: *const Self) LinkedListIterator {
                return .{
                    .node = self.head,
                };
            }
        };
    };
}
