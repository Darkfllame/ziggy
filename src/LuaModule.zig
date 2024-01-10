const index = @import("index.zig");
const ziglua = @import("ziglua");

const std = index.std;
const String = index.String;
const gameContext = index.GameContext;
const Key = index.Key;

const Game = gameContext.Game;
const Color = gameContext.Color;
const MouseButton = Game.Mouse.Button;

const Lua = ziglua.Lua;
const wrap = ziglua.wrap;
const LuaType = ziglua.LuaType;

fn getRegistry(lua: *Lua, i: anytype) void {
    pushAny(lua, i);
    _ = lua.getTable(ziglua.registry_index);
}
fn setRegistry(lua: *Lua, i: anytype, value: anytype) void {
    pushAny(lua, i);
    pushAny(lua, value);
    lua.setTable(ziglua.registry_index);
}
fn setRegistryIndex(lua: *Lua, i: i32, vi: i32) void {
    if (!(i == -2 and vi == -1)) {
        if (vi < 0)
            // offset vi by 1 if it is a pseudo-index
            vi -= 1;
        lua.pushValue(i);
        lua.pushValue(vi);
    }
    lua.setTable(ziglua.registry_index);
}
fn getRegistryIndex(lua: *Lua, i: i32) void {
    if (i != -1)
        lua.pushValue(i);
    _ = lua.getTable(ziglua.registry_index);
}

fn pushType(lua: *Lua, comptime T: type) void {
    const tinfo = @typeInfo(T);
    switch (tinfo) {
        .Enum => |data| {
            lua.newTable();
            inline for (data.fields) |field| {
                pushAny(lua, @field(T, field.name));
                const nName = std.heap.c_allocator.alloc(u8, field.name.len + 1) catch unreachable;
                defer std.heap.c_allocator.free(nName);
                std.mem.copyForwards(u8, nName, field.name);
                nName[field.name.len] = 0;
                lua.setField(-2, nName[0..field.name.len :0]);
            }
        },
        else => @compileError("Cannot push unsuported type '" ++ T ++ "'"),
    }
}
fn pushStruct(lua: *Lua, value: anytype) void {
    const T = @TypeOf(value);
    const tinfo = @typeInfo(T);
    if (tinfo != .Struct)
        @compileError("'value' must be a struct");
    const fields = tinfo.Struct.fields;
    lua.newTable();
    inline for (fields) |field| {
        pushAny(lua, @field(value, field.name));
        const nName = std.heap.c_allocator.alloc(u8, field.name.len + 1) catch unreachable;
        defer std.heap.c_allocator.free(nName);
        std.mem.copyForwards(u8, nName, field.name);
        nName[field.name.len] = 0;
        lua.setField(-2, nName[0..field.name.len :0]);
    }
}
fn pushAny(lua: *Lua, value: anytype) void {
    const T = @TypeOf(value);
    const tinfo = @typeInfo(T);
    switch (tinfo) {
        .Struct => pushStruct(lua, value),
        .Fn => switch (T) {
            ziglua.ZigFn => lua.pushFunction(ziglua.wrap(value)),
            ziglua.CFn => lua.pushFunction(value),
            else => @compileError("Unknown function type '" ++ @typeName(T) ++ "'"),
        },
        .Int, .ComptimeInt => lua.pushInteger(@intCast(value)),
        .Bool => lua.pushBoolean(value),
        .Float, .ComptimeFloat => lua.pushNumber(@floatCast(value)),
        .Null => lua.pushNil(),
        .Optional => if (value) |v| pushAny(lua, v) else lua.pushNil(),
        .Void => lua.pushNil(),
        .Enum => lua.pushInteger(@intFromEnum(value)),
        .Type => pushType(lua, value),
        .Array => |data| blk: {
            if (data.child == u8) {
                _ = lua.pushString(&value);
                break :blk;
            }
            lua.newTable();
            for (value, 0..data.len) |v, i| {
                pushAny(lua, v);
                lua.setIndex(-2, @intCast(i));
            }
        },
        .Pointer => |data| blk: {
            if (data.size == .Slice) {
                if (data.child == u8) {
                    const str = std.heap.c_allocator.alloc(u8, value.len + 1) catch lua.raiseErrorStr("Cannot allocate memory", .{});
                    defer std.heap.c_allocator.free(str);
                    std.mem.copyForwards(u8, str, value);
                    str[value.len] = 0;
                    lua.pushString(str.ptr);
                } else {
                    lua.newTable();
                    for (value, 0..data.len) |v, i| {
                        lua.pushInteger(@intCast(i));
                        pushAny(lua, v);
                        lua.setTable(-3);
                    }
                }
                break :blk;
            } else if (data.size == .One) {
                pushAny(lua, value.*);
            } else if (data.size == .Many or data.size == .C) @compileError("Cannot push C pointers and pointers to many");
        },
        else => @compileError("Cannot convert '" ++ @typeName(T) ++ "'' to a lua object"),
    }
}

fn setGlobal(lua: *Lua, i: [:0]const u8, v: anytype) void {
    pushAny(lua, v);
    lua.setGlobal(i);
}

fn lua_raiseErrorFmt(lua: *Lua, comptime fmt: []const u8, args: anytype) noreturn {
    var str = String.init(std.heap.c_allocator);
    std.fmt.format(str.writer(), fmt, args) catch {
        lua.raiseErrorStr("Cannot format string, out of memory ?", .{});
    };
    str.writer().writeByte(0) catch {
        lua.raiseErrorStr("Cannot format string, out of memory ?", .{});
    };
    const nstr = lua.pushString(str.str()[0 .. str.len() - 1 :0]);
    str.deinit();
    lua.raiseErrorStr(nstr, .{});
    unreachable;
}

const ArgumentGuardOptions = struct {
    /// Negative value mean that it can get any argument count
    expectedArgc: i32 = -1,
    /// Mode to use for argument length check
    mode: enum {
        /// Requires the exact same number of arguments
        exact,
        /// Requires less that the arguments count
        less,
        /// Requires more that the arguments count
        greater,
        /// Requires more or same number of arguments
        greaterEqual,
        /// Requires less or same number of arguments
        lessEqual,
    } = .exact,
};
/// Returns normally on expected arguments, else raise a lua error.
/// Calls this function at the top of your native lua functions to check argument count and type.
/// If options.typecheck is disabled, then it will only check for argument count.
fn argumentGuard(lua: *Lua, comptime options: ArgumentGuardOptions, arguments: []const LuaType) void {
    // fields.len = expected argc
    const argc = lua.getTop();

    // goofy ahh switch statement 💀
    // and broken formatter
    if (options.expectedArgc >= 0 and switch (options.mode) {
        .exact => argc != options.expectedArgc,
        .less => !(argc < options.expectedArgc),
        .greater => !(argc > options.expectedArgc),
        .lessEqual => !(argc <= options.expectedArgc),
        .greaterEqual => !(argc >= options.expectedArgc),
    })
        lua_raiseErrorFmt(lua, "Expected {[exp]d} argument{[punc]s}, got {[argc]d}", .{
            .exp = options.expectedArgc,
            .argc = argc,
            .punc = if (options.expectedArgc > 1) "s" else "",
        });

    for (arguments, 1..) |arg_type, i| {
        @call(.always_inline, checkArgument, .{ lua, @as(u32, @intCast(i)), arg_type });
    }
}
fn checkArgument(lua: *Lua, argument: u32, arg_type: LuaType) void {
    const l_type = lua.typeOf(@intCast(argument));
    if (l_type != arg_type) {
        lua_raiseErrorFmt(lua, "Argument #{d}: Expected {s}, got {s}", .{
            argument,
            @tagName(arg_type),
            @tagName(l_type),
        });
    }
}
fn checkArgumentUserdata(lua: *Lua, comptime T: type, argument: u32, arg_type: [:0]const u8) *T {
    const l_type = lua.typeOf(@intCast(argument));
    if (l_type != .userdata and l_type != .light_userdata) {
        lua_raiseErrorFmt(lua, "Argument #{d}: Expected userdata, got {s}", .{
            argument,
            @tagName(l_type),
        });
    }
    const field_type = lua.getMetaField(@intCast(argument), "__name") catch {
        lua_raiseErrorFmt(lua, "Cannot get metafield '__name' from userdata", .{});
    };
    if (field_type != .string) {
        lua_raiseErrorFmt(lua, "Userdata metafield is {s}, expected string", .{@tagName(field_type)});
    }
    const type_name = lua.toString(-1) catch unreachable;
    lua.len(-1);
    const name_len: usize = @intCast(lua.toInteger(-1) catch unreachable);
    if (!std.mem.eql(u8, type_name[0..name_len], arg_type)) {
        lua_raiseErrorFmt(lua, "Expected userdata type {s}, got {s}", .{ arg_type, type_name });
    }

    lua.pop(2);

    return lua.toUserdata(T, @intCast(argument)) catch unreachable;
}

fn getTableFields(lua: *Lua, i: i32, fields: []const [:0]const u8) void {
    if (i != -1) {
        lua.pushValue(i);
    }
    const register_index = lua.getTop();

    for (fields) |field| {
        lua.pushValue(register_index);
        const l_type = lua.typeOf(-1);
        if (l_type != .table and l_type != .userdata)
            lua_raiseErrorFmt(lua, "Expected table, got {s}", .{@tagName(l_type)});
        if (l_type == .userdata) {
            _ = lua.getMetaField(-1, "__index") catch
                lua_raiseErrorFmt(lua, "Userdata got no 'index' metafield", .{});
            lua.pop(1);
        }
        _ = lua.getField(-1, field);
        lua.copy(-1, register_index);
        lua.pop(2);
    }
}
inline fn getRegistryFields(lua: *Lua, fields: []const [:0]const u8) void {
    getTableFields(lua, ziglua.registry_index, fields);
}

pub fn msghandler(lua: *Lua) i32 {
    const msg = lua.toString(1) catch {
        lua.callMeta(1, "__tostring") catch unreachable;
        if (lua.isString(-1))
            return 1;
        _ = lua.pushString("fuck off bro :/");
        return 1;
    };
    lua.traceback(lua, std.mem.span(msg), 1);
    return 1;
}

pub const Error = error{
    LuaRuntime,
};

const LuaModule = @This();

lua: *Lua,

pub fn init(lua: *Lua, game: *Game) LuaModule {
    const startTop = lua.getTop();

    // initialize registry
    std.debug.print("initializing registry...\n", .{});
    setRegistry(lua, "ZGE", .{
        .updateCallbacks = .{},
        .renderCallbacks = .{},
        .Statics = .{},
        .Game = .{
            .__name = "ZGE.Game",
            .__index = l_game__index,
        },
        .Renderer = .{
            .__name = "ZGE.Renderer",
            .__index = l_renderer__index,
            .__newindex = l_renderer__newindex,
        },
        .Keyboard = .{
            .__name = "ZGE.Keyboard",
            .__index = l_keyboard__index,
        },
        .Mouse = .{
            .__name = "ZGE.Mouse",
            .__index = l_mouse__index,
        },
    });

    std.debug.print("initializing globals...\n", .{});
    // initialize globals
    const l_game = lua.newUserdata(*Game, 0);
    l_game.* = game;
    getRegistryFields(lua, &.{ "ZGE", "Game" });
    lua.setMetatable(-2);
    lua.setGlobal("game");

    lua.pop(lua.getTop() - startTop);

    return .{
        .lua = lua,
    };
}

pub fn update(self: *LuaModule, dt: f128) !void {
    const lua = self.lua;
    const startTop = lua.getTop();
    getRegistryFields(lua, &.{ "ZGE", "updateCallbacks" });
    const table_index = lua.getTop();

    lua.len(-1);
    const len: usize = @intCast(lua.toInteger(-1) catch unreachable);
    lua.pop(1);

    lua.pushFunction(wrap(msghandler));
    const msgh = lua.getTop();
    for (0..len) |i| {
        _ = lua.getIndex(table_index, @intCast(i + 1));
        pushAny(lua, dt);
        lua.protectedCall(1, 0, msgh) catch {
            const err = lua.toString(-1) catch unreachable;
            return index.errorWithMessage(Error, std.mem.span(err), Error.LuaRuntime);
        };
    }
    lua.pop(lua.getTop() - startTop);
}
pub fn render(self: *LuaModule, renderer: *Game.Renderer) !void {
    const lua = self.lua;
    const startTop = lua.getTop();
    getRegistryFields(lua, &.{ "ZGE", "renderCallbacks" });
    const table_index = lua.getTop();

    lua.len(-1);
    const len: usize = @intCast(lua.toInteger(-1) catch unreachable);
    lua.pop(1);

    lua.pushFunction(wrap(msghandler));
    const msgh = lua.getTop();
    for (0..len) |i| {
        _ = lua.getIndex(table_index, @intCast(i + 1));
        pushRenderer(lua, renderer);
        lua.protectedCall(1, 0, msgh) catch {
            const err = lua.toString(-1) catch unreachable;
            return index.errorWithMessage(Error, std.mem.span(err), Error.LuaRuntime);
        };
    }
    lua.pop(lua.getTop() - startTop);
}

fn l_game__index(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
        .string,
    });
    const game = checkArgumentUserdata(lua, *Game, 1, "ZGE.Game").*;
    const field = lua.toString(2) catch unreachable;

    const hash = String.hashOf;

    switch (hash(std.mem.span(field))) {
        hash("AddUpdateCallback") => pushAny(lua, l_AddUpdateCallback),
        hash("AddRenderCallback") => pushAny(lua, l_AddRenderCallback),
        hash("Keyboard") => {
            const l_keyboard = lua.newUserdata(*Game.Keyboard, 0);
            l_keyboard.* = game.getKeyboard();
            getRegistryFields(lua, &.{ "ZGE", "Keyboard" });
            lua.setMetatable(-2);
        },
        hash("Mouse") => {
            const l_mouse = lua.newUserdata(*Game.Mouse, 0);
            l_mouse.* = game.getMouse();
            getRegistryFields(lua, &.{ "ZGE", "Mouse" });
            lua.setMetatable(-2);
        },
        hash("Time") => {
            const time_ns = Game.nanoTime();
            const time_s = @as(f128, @floatFromInt(time_ns)) / @as(f128, @floatFromInt(Game.time.ns_per_s));
            pushAny(lua, time_s);
        },
        hash("Static") => pushAny(lua, l_Static),
        hash("Quit") => pushAny(lua, l_Quit),
        hash("Key") => pushAny(lua, Key),
        hash("Button") => pushAny(lua, Game.Mouse.Button),
        else => lua.raiseErrorStr("Cannot find field '{s}' from ZGE.Game object", .{field}),
    }
    return 1;
}

fn l_AddUpdateCallback(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 1,
    }, &.{
        .function,
    });

    getRegistryFields(lua, &.{ "ZGE", "updateCallbacks" });

    lua.len(-1);
    const len = lua.toInteger(-1) catch unreachable;
    lua.pop(1);

    // registry.ZGE.updateCallbacks[(#registry.ZGE.updateCallbacks)+1] = function
    lua.pushValue(1);
    lua.setIndex(-2, len + 1);
    return 0;
}
fn l_AddRenderCallback(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 1,
    }, &.{
        .function,
    });

    getRegistryFields(lua, &.{ "ZGE", "renderCallbacks" });

    lua.len(-1);
    const len = lua.toInteger(-1) catch unreachable;
    lua.pop(1);

    // registry.ZGE.renderCallbacks[(#registry.ZGE.renderCallbacks)+1] = function
    lua.pushValue(1);
    lua.setIndex(-2, len + 1);
    return 0;
}
fn l_Static(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 1,
        .mode = .greaterEqual,
    }, &.{
        .table,
    });

    // static will be <source>:<line>

    var aa = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer aa.deinit();
    const allocator = aa.allocator();

    var infos = lua.getStack(1) catch unreachable;
    lua.getInfo(.{
        .S = true,
        .l = true,
    }, &infos);
    const s = infos.source;
    const l = infos.current_line orelse 1;
    const lSize: usize = @intCast(std.math.log10(@as(u32, @intCast(l))));
    // name length + ':' + size of integer + null terminator
    var str = String.init(allocator);
    str.allocate(s.len + lSize + 2) catch {
        aa.deinit();
        lua_raiseErrorFmt(lua, "Cannot allocate {d} bytes of memory", .{s.len + 1 + lSize});
    };
    // should be impossible to not allocate the formatter
    std.fmt.format(str.writer(), "{s}:{d}{c}", .{ s, l, 0 }) catch unreachable;

    getRegistryFields(lua, &.{ "ZGE", "Statics" });
    lua.len(-1);
    const len = lua.toInteger(-1) catch unreachable;
    _ = len; // autofix
    lua.pop(1);

    const fieldName = str.str()[0 .. str.len() - 1 :0];
    const l_type = lua.getField(-1, fieldName);
    if (l_type == .nil) {
        lua.copy(1, -1);
        lua.setField(-2, fieldName);
        lua.copy(1, -1);
    } else if (l_type != .table) {
        lua_raiseErrorFmt(lua, "bro why the FUCK did you modified my good made REGISTRY TABLE YOU FUCKER >:(", .{});
    }
    return 1;
}
fn l_Quit(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 0,
    }, &.{});
    Game.quit();
    return 0;
}

// game.Renderer.__metatable

fn pushRenderer(lua: *Lua, renderer: *Game.Renderer) void {
    const l_renderer = lua.newUserdata(*Game.Renderer, 0);
    l_renderer.* = renderer;
    getRegistryFields(lua, &.{ "ZGE", "Renderer" });
    lua.setMetatable(-2);
}

fn l_renderer__index(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
        .string,
    });

    const renderer = checkArgumentUserdata(lua, *Game.Renderer, 1, "ZGE.Renderer").*;
    const field = lua.toString(2) catch unreachable;

    const hash = String.hashOf;

    switch (hash(std.mem.span(field))) {
        hash("color") => pushStruct(lua, renderer.getDrawColor() catch |e| {
            const message = index.getError();
            lua_raiseErrorFmt(lua, "[ERROR | {any}] {s}", .{ e, message });
        }),
        hash("fillRect") => pushAny(lua, l_renderer_fillrect),
        hash("drawRect") => pushAny(lua, l_renderer_drawrect),
        hash("drawLine") => pushAny(lua, l_renderer_drawline),
        hash("drawPoint") => pushAny(lua, l_renderer_drawpoint),
        hash("fillRects") => pushAny(lua, l_renderer_fillrects),
        hash("drawRects") => pushAny(lua, l_renderer_drawrects),
        hash("drawLines") => pushAny(lua, l_renderer_drawlines),
        hash("drawPoints") => pushAny(lua, l_renderer_drawpoints),
        else => lua.raiseErrorStr("Cannot find field '{s}' from ZGE.Renderer object", .{field}),
    }
    return 1;
}
fn l_renderer__newindex(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 3,
    }, &.{
        .userdata,
        .string,
        // leave third argument empty for any type
    });

    const renderer = checkArgumentUserdata(lua, *Game.Renderer, 1, "ZGE.Renderer").*;
    const field = lua.toString(2) catch unreachable;

    const hash = String.hashOf;

    switch (hash(std.mem.span(field))) {
        hash("color") => {
            checkArgument(lua, 3, .table);
            const r: u8 = ifr: {
                if (lua.getField(3, "r") != .number) {
                    lua.pop(1);
                    if (lua.getIndex(3, 1) != .number) {
                        lua.pop(1);
                        break :ifr 0;
                    }
                }
                break :ifr @intCast(lua.toInteger(-1) catch unreachable);
            };
            const g: u8 = ifg: {
                if (lua.getField(3, "g") != .number) {
                    lua.pop(1);
                    if (lua.getIndex(3, 2) != .number) {
                        lua.pop(1);
                        break :ifg 0;
                    }
                }
                break :ifg @intCast(lua.toInteger(-1) catch unreachable);
            };
            const b: u8 = ifb: {
                if (lua.getField(3, "b") != .number) {
                    lua.pop(1);
                    if (lua.getIndex(3, 3) != .number) {
                        lua.pop(1);
                        break :ifb 0;
                    }
                }
                break :ifb @intCast(lua.toInteger(-1) catch unreachable);
            };
            const a: u8 = ifa: {
                if (lua.getField(3, "a") != .number) {
                    lua.pop(1);
                    if (lua.getIndex(3, 4) != .number) {
                        lua.pop(1);
                        break :ifa 255;
                    }
                }
                break :ifa @intCast(lua.toInteger(-1) catch unreachable);
            };

            renderer.setDrawColor(.{
                .r = r,
                .g = g,
                .b = b,
                .a = a,
            }) catch |e| {
                const message = index.getError();
                lua_raiseErrorFmt(lua, "[ERROR | {any}] {s}", .{ e, message });
            };
        },
        else => lua.raiseErrorStr("Cannot find field '{s}' from ZGE.Renderer object", .{field}),
    }
    return 0;
}
fn l_renderer_fillrect(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 5,
    }, &.{
        .userdata,
        .number,
        .number,
        .number,
        .number,
    });
    const renderer = checkArgumentUserdata(lua, *Game.Renderer, 1, "ZGE.Renderer").*;
    const x = lua.toInteger(2) catch unreachable;
    const y = lua.toInteger(3) catch unreachable;
    const w = lua.toInteger(4) catch unreachable;
    const h = lua.toInteger(5) catch unreachable;
    renderer.fillRect(.{
        .x = @intCast(x),
        .y = @intCast(y),
        .w = @intCast(w),
        .h = @intCast(h),
    }) catch |e| {
        const message = index.getError();
        lua_raiseErrorFmt(lua, "[ERROR | {any}] {s}", .{ e, message });
    };
    return 0;
}
fn l_renderer_drawrect(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 5,
    }, &.{
        .userdata,
        .number,
        .number,
        .number,
        .number,
    });
    const renderer = checkArgumentUserdata(lua, *Game.Renderer, 1, "ZGE.Renderer").*;
    const x = lua.toInteger(2) catch unreachable;
    const y = lua.toInteger(3) catch unreachable;
    const w = lua.toInteger(4) catch unreachable;
    const h = lua.toInteger(5) catch unreachable;
    renderer.drawRect(.{
        .x = @intCast(x),
        .y = @intCast(y),
        .w = @intCast(w),
        .h = @intCast(h),
    }) catch {
        const message = index.getError();
        lua_raiseErrorFmt(lua, "{s}", .{message});
    };
    return 0;
}
fn l_renderer_drawline(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 5,
    }, &.{
        .userdata,
        .number,
        .number,
        .number,
        .number,
    });
    const renderer = checkArgumentUserdata(lua, *Game.Renderer, 1, "ZGE.Renderer").*;
    const x = lua.toInteger(2) catch unreachable;
    const y = lua.toInteger(3) catch unreachable;
    const x2 = lua.toInteger(4) catch unreachable;
    const y2 = lua.toInteger(5) catch unreachable;
    renderer.drawLine(.{
        .x = @intCast(x),
        .y = @intCast(y),
    }, .{
        .x = @intCast(x2),
        .y = @intCast(y2),
    }) catch {
        const message = index.getError();
        lua_raiseErrorFmt(lua, "{s}", .{message});
    };
    return 0;
}
fn l_renderer_drawpoint(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 3,
    }, &.{
        .userdata,
        .number,
        .number,
    });
    const renderer = checkArgumentUserdata(lua, *Game.Renderer, 1, "ZGE.Renderer").*;
    const x = lua.toInteger(2) catch unreachable;
    const y = lua.toInteger(3) catch unreachable;
    renderer.drawPoint(.{
        .x = @intCast(x),
        .y = @intCast(y),
    }) catch {
        const message = index.getError();
        lua_raiseErrorFmt(lua, "{s}", .{message});
    };
    return 0;
}
fn l_renderer_fillrects(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
        .table,
    });

    const allocator = std.heap.c_allocator;

    const renderer = checkArgumentUserdata(lua, *Game.Renderer, 1, "ZGE.Renderer").*;
    lua.len(-1);
    const len: i32 = @intCast(lua.toInteger(-1) catch unreachable);
    lua.pop(1);
    if (@mod(len, 4) != 0) {
        lua_raiseErrorFmt(lua, "Expected a length of a multiple of 2, got length {d}", .{len});
    }
    const rects = allocator.alloc(gameContext.Rect, @intCast(@divFloor(len, 4))) catch {
        lua_raiseErrorFmt(lua, "Cannot allocate memory", .{});
    };
    for (0..rects.len) |i| {
        if (lua.getIndex(2, @intCast(i * 4 + 1)) != .number) {
            allocator.free(rects);
            lua_raiseErrorFmt(lua, "Expected table at index 1, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        if (lua.getIndex(2, @intCast(i * 4 + 2)) != .number) {
            allocator.free(rects);
            lua_raiseErrorFmt(lua, "Expected table at index 2, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        if (lua.getIndex(2, @intCast(i * 4 + 3)) != .number) {
            allocator.free(rects);
            lua_raiseErrorFmt(lua, "Expected table at index 3, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        if (lua.getIndex(2, @intCast(i * 4 + 4)) != .number) {
            allocator.free(rects);
            lua_raiseErrorFmt(lua, "Expected table at index 4, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        const x = lua.toInteger(-4) catch unreachable;
        const y = lua.toInteger(-3) catch unreachable;
        const w = lua.toInteger(-2) catch unreachable;
        const h = lua.toInteger(-1) catch unreachable;
        rects[i] = .{
            .x = @intCast(x),
            .y = @intCast(y),
            .w = @intCast(w),
            .h = @intCast(h),
        };
    }
    renderer.fillRects(rects) catch {
        const message = index.getError();
        allocator.free(rects);
        lua_raiseErrorFmt(lua, "{s}", .{message});
    };
    allocator.free(rects);
    return 0;
}
fn l_renderer_drawrects(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
        .table,
    });

    const allocator = std.heap.c_allocator;

    const renderer = checkArgumentUserdata(lua, *Game.Renderer, 1, "ZGE.Renderer").*;
    lua.len(-1);
    const len: i32 = @intCast(lua.toInteger(-1) catch unreachable);
    lua.pop(1);
    if (@mod(len, 4) != 0) {
        lua_raiseErrorFmt(lua, "Expected a length of a multiple of 2, got length {d}", .{len});
    }
    const rects = allocator.alloc(gameContext.Rect, @intCast(@divFloor(len, 4))) catch {
        lua_raiseErrorFmt(lua, "Cannot allocate memory", .{});
    };
    for (0..rects.len) |i| {
        if (lua.getIndex(2, @intCast(i * 4 + 1)) != .number) {
            allocator.free(rects);
            lua_raiseErrorFmt(lua, "Expected table at index 1, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        if (lua.getIndex(2, @intCast(i * 4 + 2)) != .number) {
            allocator.free(rects);
            lua_raiseErrorFmt(lua, "Expected table at index 2, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        if (lua.getIndex(2, @intCast(i * 4 + 3)) != .number) {
            allocator.free(rects);
            lua_raiseErrorFmt(lua, "Expected table at index 3, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        if (lua.getIndex(2, @intCast(i * 4 + 4)) != .number) {
            allocator.free(rects);
            lua_raiseErrorFmt(lua, "Expected table at index 4, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        const x = lua.toInteger(-4) catch unreachable;
        const y = lua.toInteger(-3) catch unreachable;
        const w = lua.toInteger(-2) catch unreachable;
        const h = lua.toInteger(-1) catch unreachable;
        rects[i] = .{
            .x = @intCast(x),
            .y = @intCast(y),
            .w = @intCast(w),
            .h = @intCast(h),
        };
    }
    renderer.drawRects(rects) catch {
        const message = index.getError();
        allocator.free(rects);
        lua_raiseErrorFmt(lua, "{s}", .{message});
    };
    allocator.free(rects);
    return 0;
}
fn l_renderer_drawlines(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
        .table,
    });

    const allocator = std.heap.c_allocator;

    const renderer = checkArgumentUserdata(lua, *Game.Renderer, 1, "ZGE.Renderer").*;
    lua.len(-1);
    const len: i32 = @intCast(lua.toInteger(-1) catch unreachable);
    lua.pop(1);
    if (@mod(len, 4) != 0) {
        lua_raiseErrorFmt(lua, "Expected a length of a multiple of 2, got length {d}", .{len});
    }
    const points = allocator.alloc(gameContext.Point, @intCast(@divFloor(len, 2))) catch {
        lua_raiseErrorFmt(lua, "Cannot allocate memory", .{});
    };
    for (0..points.len) |i| {
        if (lua.getIndex(2, @intCast(i * 2 + 1)) != .number) {
            allocator.free(points);
            lua_raiseErrorFmt(lua, "Expected table at index 1, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        if (lua.getIndex(2, @intCast(i * 2 + 2)) != .number) {
            allocator.free(points);
            lua_raiseErrorFmt(lua, "Expected table at index 2, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        if (lua.getIndex(2, @intCast(i * 2 + 3)) != .number) {
            allocator.free(points);
            lua_raiseErrorFmt(lua, "Expected table at index 3, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        if (lua.getIndex(2, @intCast(i * 2 + 3)) != .number) {
            allocator.free(points);
            lua_raiseErrorFmt(lua, "Expected table at index 4, got {s}", .{lua.typeName(lua.typeOf(-1))});
        }
        const x = lua.toInteger(-4) catch unreachable;
        const y = lua.toInteger(-3) catch unreachable;
        const x2 = lua.toInteger(-2) catch unreachable;
        const y2 = lua.toInteger(-1) catch unreachable;
        points[i] = .{
            .x = @intCast(x),
            .y = @intCast(y),
        };
        points[i + 1] = .{
            .x = @intCast(x2),
            .y = @intCast(y2),
        };
    }
    renderer.drawLines(points) catch {
        const message = index.getError();
        allocator.free(points);
        lua_raiseErrorFmt(lua, "{s}", .{message});
    };
    allocator.free(points);
    return 0;
}
fn l_renderer_drawpoints(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
        .table,
    });

    const allocator = std.heap.c_allocator;

    const renderer = checkArgumentUserdata(lua, *Game.Renderer, 1, "ZGE.Renderer").*;
    lua.len(-1);
    const len: i32 = @intCast(lua.toInteger(-1) catch unreachable);
    lua.pop(1);
    if (@mod(len, 2) != 0) {
        lua_raiseErrorFmt(lua, "Expected a length of a multiple of 2, got length {d}", .{len});
    }
    const points = allocator.alloc(gameContext.Point, @intCast(@divFloor(len, 2))) catch {
        lua_raiseErrorFmt(lua, "Cannot allocate memory", .{});
    };
    for (points, 0..) |*p, i| {
        if (lua.getIndex(2, @intCast(i * 2 + 1)) != .number) {
            allocator.free(points);
            lua_raiseErrorFmt(lua, "Expected table at index {d}, got {s}", .{ i, lua.typeName(lua.typeOf(-1)) });
        }
        if (lua.getIndex(2, @intCast(i * 2 + 2)) != .number) {
            allocator.free(points);
            lua_raiseErrorFmt(lua, "Expected table at index {d}, got {s}", .{ i, lua.typeName(lua.typeOf(-1)) });
        }
        const x = lua.toInteger(-2) catch unreachable;
        const y = lua.toInteger(-1) catch unreachable;
        p.* = .{
            .x = @intCast(x),
            .y = @intCast(y),
        };
    }
    renderer.drawPoints(points) catch {
        const message = index.getError();
        allocator.free(points);
        lua_raiseErrorFmt(lua, "{s}", .{message});
    };
    allocator.free(points);
    return 0;
}

// game.Keyboard.__metatable

fn l_keyboard__index(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
        .string,
    });

    const keyboard = checkArgumentUserdata(lua, *Game.Keyboard, 1, "ZGE.Keyboard").*;
    _ = keyboard;
    const field = lua.toString(2) catch unreachable;

    const hash = String.hashOf;

    switch (hash(std.mem.span(field))) {
        hash("IsDown") => pushAny(lua, l_keyboard_IsDown),
        hash("IsPressed") => pushAny(lua, l_keyboard_IsPressed),
        hash("IsReleased") => pushAny(lua, l_keyboard_IsReleased),
        else => lua.raiseErrorStr("Cannot find field '{s}' from ZGE.Keyboard object", .{field}),
    }
    return 1;
}
fn keyFromLua(lua: *Lua, argument: i32) Key {
    const startTop = lua.getTop();
    defer lua.pop(lua.getTop() - startTop);

    const l_type = lua.typeOf(argument);
    return switch (l_type) {
        .number => @enumFromInt(lua.toInteger(argument) catch unreachable),
        .string => blk: {
            const absIndex = lua.absIndex(argument);
            _ = lua.getGlobal("game") catch unreachable;
            getTableFields(lua, -1, &.{ "Key", std.mem.span(lua.toString(absIndex) catch unreachable) });
            break :blk keyFromLua(lua, -1);
        },
        .nil, .none => .Any,
        else => lua_raiseErrorFmt(lua, "All keys are defined in game.Key, you can also pass the key as a string.", .{}),
    };
}
fn l_keyboard_IsDown(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
        .mode = .lessEqual,
    }, &.{
        .userdata,
    });
    const keyboard = checkArgumentUserdata(lua, *Game.Keyboard, 1, "ZGE.Keyboard").*;
    const key = keyFromLua(lua, 2);
    pushAny(lua, keyboard.isKeyDown(key));
    return 1;
}
fn l_keyboard_IsPressed(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
    });
    const keyboard = checkArgumentUserdata(lua, *Game.Keyboard, 1, "ZGE.Keyboard").*;
    const key = keyFromLua(lua, 2);
    if (key == .Any)
        lua_raiseErrorFmt(lua, "Cannot check for any key presssed (idk how to do it) :/", .{});
    pushAny(lua, keyboard.isKeyPressed(key));
    return 1;
}
fn l_keyboard_IsReleased(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
    });
    const keyboard = checkArgumentUserdata(lua, *Game.Keyboard, 1, "ZGE.Keyboard").*;
    const key = keyFromLua(lua, 2);
    if (key == .Any)
        lua_raiseErrorFmt(lua, "Cannot check for any key released (idk how to do it) :/", .{});
    pushAny(lua, keyboard.isKeyReleased(key));
    return 1;
}

// game.Mouse.__metatable

fn l_mouse__index(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
        .string,
    });

    const mouse = checkArgumentUserdata(lua, *Game.Mouse, 1, "ZGE.Mouse").*;
    _ = mouse;
    const field = lua.toString(2) catch unreachable;

    const hash = String.hashOf;

    switch (hash(std.mem.span(field))) {
        hash("IsDown") => pushAny(lua, l_mouse_IsDown),
        hash("IsPressed") => pushAny(lua, l_mouse_IsPressed),
        hash("IsReleased") => pushAny(lua, l_mouse_IsReleased),
        hash("GetPosition") => pushAny(lua, l_mouse_GetPosition),
        else => lua.raiseErrorStr("Cannot find field '{s}' from ZGE.Mouse object", .{field}),
    }
    return 1;
}
fn buttonFromLua(lua: *Lua, argument: i32) Game.Mouse.Button {
    const startTop = lua.getTop();
    defer lua.pop(lua.getTop() - startTop);

    const l_type = lua.typeOf(argument);
    return switch (l_type) {
        .number => @enumFromInt(lua.toInteger(argument) catch unreachable),
        .string => blk: {
            const absIndex = lua.absIndex(argument);
            _ = lua.getGlobal("game") catch unreachable;
            getTableFields(lua, -1, &.{ "Button", std.mem.span(lua.toString(absIndex) catch unreachable) });
            break :blk buttonFromLua(lua, -1);
        },
        .nil, .none => .Any,
        else => lua_raiseErrorFmt(lua, "All buttons are defined in game.Button, you can also pass the button as a string.", .{}),
    };
}
fn l_mouse_IsDown(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
    });

    const mouse = checkArgumentUserdata(lua, *Game.Mouse, 1, "ZGE.Mouse").*;
    const button = buttonFromLua(lua, 2);
    pushAny(lua, mouse.isButtonDown(button));
    return 1;
}
fn l_mouse_IsPressed(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
    });

    const mouse = checkArgumentUserdata(lua, *Game.Mouse, 1, "ZGE.Mouse").*;
    const button = buttonFromLua(lua, 2);
    pushAny(lua, mouse.isButtonPressed(button));
    return 1;
}
fn l_mouse_IsReleased(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 2,
    }, &.{
        .userdata,
    });

    const mouse = checkArgumentUserdata(lua, *Game.Mouse, 1, "ZGE.Mouse").*;
    const button = buttonFromLua(lua, 2);
    pushAny(lua, mouse.isButtonReleased(button));
    return 1;
}
fn l_mouse_GetPosition(lua: *Lua) i32 {
    argumentGuard(lua, .{
        .expectedArgc = 1,
    }, &.{
        .userdata,
    });

    const mouse = checkArgumentUserdata(lua, *Game.Mouse, 1, "ZGE.Mouse").*;
    pushAny(lua, mouse.getPosition());
    return 1;
}
