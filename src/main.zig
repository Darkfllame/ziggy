const index = @import("index.zig");
const ziglua = @import("ziglua");
const luaModule = @import("LuaModule.zig");

const sdl = index.sdl;
const std = index.std;
const gameContext = index.GameContext;

const wrap = ziglua.wrap;
const Lua = ziglua.Lua;

const Game = gameContext.Game;
const Color = gameContext.Color;
const String = index.String;

var gLua: luaModule = undefined;

pub fn main() !void {
    defer index.clearError();

    var ha: std.heap.HeapAllocator = std.heap.HeapAllocator.init();
    defer ha.deinit();
    const allocator = ha.allocator();

    var game = try Game.init(allocator, "Hello", 800, 600, .{});
    defer game.deinit();

    var lua = try ziglua.Lua.init(allocator);
    defer lua.deinit();

    lua.openLibs();
    gLua = luaModule.init(&lua, game);

    (runblock: {
        lua.pushFunction(wrap(luaModule.msghandler));
        const msgh = lua.getTop();
        lua.loadFile("main.lua", .text) catch |e| break :runblock e;
        lua.protectedCall(0, 0, msgh) catch |e| break :runblock e;
    } catch {
        const err = lua.toString(-1) catch unreachable;
        std.debug.print("{s}\n", .{err});
        return;
    });

    game.setUpdateFn(update);
    game.setRenderFn(render);

    mouse = game.getMouse();
    keyboard = game.getKeyboard();

    game.run() catch |e| {
        const msg = index.getError();
        nosuspend std.io.getStdOut().writer().print("[ERROR | {}] {s}\n", .{ e, msg }) catch return;
        return;
    };
}

var mouse: *Game.Mouse = undefined;
var keyboard: *Game.Keyboard = undefined;
var timer: i64 = 0;

fn update(game: *Game, dt: f128) anyerror!void {
    var arena = game.createArena();
    defer arena.deinit();
    const allocator = arena.allocator();

    var new_title = String.init(allocator);
    var writer = new_title.writer();
    try writer.print("Hello | {d:.0} FPS", .{@as(f64, @floatCast(1 / dt))});
    try game.window.setTitle(new_title.str());

    try gLua.update(dt);
}
fn render(game: *Game, renderer: *Game.Renderer) anyerror!void {
    _ = game; // autofix
    try gLua.render(renderer);
}
