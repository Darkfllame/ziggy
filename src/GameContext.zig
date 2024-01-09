const index = @import("index.zig");
const ziglua = @import("ziglua");
const luaModule = @import("LuaModule.zig");
const std = index.std;
const sdl = index.sdl;

const Allocator = std.mem.Allocator;

const SDLWindow = sdl.SDL_Window;
const SDLRenderer = sdl.SDL_Renderer;
const SDLTexture = sdl.SDL_Texture;

const checkNull = index.checkNull;
const checkError = index.checkError;
const errorWithMessage = index.errorWithMessage;

const DestroyWindow = sdl.SDL_DestroyWindow;
const DestroyRenderer = sdl.SDL_DestroyRenderer;
const DestroyTexture = sdl.SDL_DestroyTexture;

pub const UpdateFn = *const fn (game: *Game, dt: f128) anyerror!void;
pub const RenderFn = *const fn (game: *Game, renderer: *Game.Renderer) anyerror!void;

pub const InitFlags = struct {
    fullscreen: bool = false,
    fullscreenDesktop: bool = false,
    opengl: bool = false,
    vulkan: bool = false,
    shown: bool = true,
    hidden: bool = false,
    borderless: bool = false,
    resizable: bool = false,
    minimized: bool = false,
    maximized: bool = false,
    inputGrabbed: bool = false,
    inputFocus: bool = false,
    mouseFocus: bool = false,
    foreign: bool = false,
    allowHighDPI: bool = false,
    mouseCapture: bool = false,
    alwaysOnTop: bool = false,
    skipTaskbar: bool = false,
    utility: bool = false,
    tooltip: bool = false,
    popupMenu: bool = false,
};

pub const Color = struct {
    pub const White = Color{
        .r = 255,
        .g = 255,
        .b = 255,
    };
    pub const Red = Color{
        .r = 255,
    };
    pub const Green = Color{
        .g = 255,
    };
    pub const Blue = Color{
        .b = 255,
    };

    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0xFF,

    pub fn format(self: Color, comptime fmt: []const u8, _: std.fmt.FormatOptions, stream: anytype) !void {
        if (comptime std.mem.eql(u8, fmt, "x")) {
            try stream.print("{X:0<2}{X:0<2}{X:0<2}{X:0<2}", self);
        } else if (comptime std.mem.eql(u8, fmt, "c")) {
            try stream.print("Color{{ .r = {d:0<3}, .g = {d:0<3}, .b = {d:0<3}, .a = {d:0<3} }}", self);
        } else if (comptime std.mem.eql(u8, fmt, "cx")) {
            try stream.print("Color{{ .r = {X:0<2}, .g = {X:0<2}, .b = {X:0<2}, .a = {X:0<2} }}", self);
        } else {
            @compileError("Format not available. Expected 'x', 'c' or 'cx', got '" ++ fmt ++ "'");
        }
    }
};
pub const FColor = struct {
    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 1,

    pub fn mul(self: FColor, scalar: f32) FColor {
        return .{
            self.r * scalar,
            self.g * scalar,
            self.b * scalar,
            self.a * scalar,
        };
    }

    pub fn toColor(self: FColor) Color {
        return .{
            .r = @intFromFloat(self.r * 255),
            .g = @intFromFloat(self.g * 255),
            .b = @intFromFloat(self.b * 255),
            .a = @intFromFloat(self.a * 255),
        };
    }

    pub fn format(self: FColor, comptime _: []const u8, _: std.fmt.FormatOptions, stream: anytype) !void {
        try stream.print("Color{{ .r = {d:0<3}%, .g = {d:0<3}%, .b = {d:0<3}%, .a = {d:0<3}% }}", self.mul(100));
    }
};

pub const Rect = struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,

    pub fn format(self: Rect, comptime _: []const u8, _: std.fmt.FormatOptions, stream: anytype) !void {
        try stream.print("Rect{{ .x = {d}, .y = {d}, .w = {d}, .h = {d} }}", .{ self.x, self.y, self.w, self.h });
    }
};
pub const FRect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn format(self: FRect, comptime _: []const u8, _: std.fmt.FormatOptions, stream: anytype) !void {
        try stream.print("Rect{{ .x = {d}, .y = {d}, .w = {d}, .h = {d} }}", .{ self.x, self.y, self.w, self.h });
    }
};

pub const Point = struct {
    x: i32 = 0,
    y: i32 = 0,

    pub fn format(self: Point, comptime _: []const u8, _: std.fmt.FormatOptions, stream: anytype) !void {
        try stream.print("Point{{ .x = {d}, .y = {d} }}", .{ self.x, self.y });
    }
};
pub const FPoint = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn format(self: FPoint, comptime _: []const u8, _: std.fmt.FormatOptions, stream: anytype) !void {
        try stream.print("FPoint{{ .x = {d}, .y = {d} }}", .{ self.x, self.y });
    }
};

pub const Flip = enum(u32) {
    None = @intCast(sdl.SDL_FLIP_NONE),
    Horizontal = @intCast(sdl.SDL_FLIP_HORIZONTAL),
    Vertical = @intCast(sdl.SDL_FLIP_VERTICAL),
};

inline fn rect2sdl(r: Rect) sdl.SDL_Rect {
    return .{
        .x = @intCast(r.x),
        .y = @intCast(r.y),
        .w = @intCast(r.w),
        .h = @intCast(r.h),
    };
}
inline fn frect2sdl(r: Rect) sdl.SDL_FRect {
    return @as(sdl.SDL_FRect, r);
}
inline fn point2sdl(p: Point) sdl.SDL_Point {
    return .{
        .x = @intCast(p.x),
        .y = @intCast(p.y),
    };
}
inline fn fpoint2sdl(p: FPoint) sdl.SDL_FPoint {
    return @as(sdl.SDL_FPoint, p);
}
inline fn flags2Int(f: InitFlags) u32 {
    var i: u32 = 0;

    // this is trash ik, but i didn't found an easier solution

    if (f.fullscreen) {
        i |= sdl.SDL_WINDOW_FULLSCREEN;
    }
    if (f.fullscreenDesktop) {
        i |= sdl.SDL_WINDOW_FULLSCREEN_DESKTOP;
    }
    if (f.opengl) {
        i |= sdl.SDL_WINDOW_OPENGL;
    }
    if (f.vulkan) {
        i |= sdl.SDL_WINDOW_VULKAN;
    }
    if (f.shown) {
        i |= sdl.SDL_WINDOW_SHOWN;
    }
    if (f.hidden) {
        i |= sdl.SDL_WINDOW_HIDDEN;
    }
    if (f.borderless) {
        i |= sdl.SDL_WINDOW_BORDERLESS;
    }
    if (f.resizable) {
        i |= sdl.SDL_WINDOW_RESIZABLE;
    }
    if (f.minimized) {
        i |= sdl.SDL_WINDOW_MINIMIZED;
    }
    if (f.maximized) {
        i |= sdl.SDL_WINDOW_MAXIMIZED;
    }
    if (f.inputGrabbed) {
        i |= sdl.SDL_WINDOW_INPUT_GRABBED;
    }
    if (f.inputFocus) {
        i |= sdl.SDL_WINDOW_INPUT_FOCUS;
    }
    if (f.foreign) {
        i |= sdl.SDL_WINDOW_FOREIGN;
    }
    if (f.allowHighDPI) {
        i |= sdl.SDL_WINDOW_ALLOW_HIGHDPI;
    }
    if (f.mouseCapture) {
        i |= sdl.SDL_WINDOW_MOUSE_CAPTURE;
    }
    if (f.alwaysOnTop) {
        i |= sdl.SDL_WINDOW_ALWAYS_ON_TOP;
    }
    if (f.skipTaskbar) {
        i |= sdl.SDL_WINDOW_SKIP_TASKBAR;
    }
    if (f.utility) {
        i |= sdl.SDL_WINDOW_UTILITY;
    }
    if (f.tooltip) {
        i |= sdl.SDL_WINDOW_TOOLTIP;
    }
    if (f.popupMenu) {
        i |= sdl.SDL_WINDOW_POPUP_MENU;
    }

    return i;
}

pub const Error = Allocator.Error || error{
    GameAlreadyInitialized,
    GameNotInitialized,
    GameAlreadyRunning,
    Initialization,
    OutOfMemory,
    SdlError,
    ImgError,
    MixError,
};

pub const Game = struct {
    pub const Window = GameWindow;
    pub const Renderer = GameRenderer;
    pub const Mouse = GameMouse;
    pub const Keyboard = GameKeyboard;
    pub const ArenaAllocator = std.heap.ArenaAllocator;

    pub const print = std.debug.print;
    pub const sleepNanos = time.sleep;
    pub const nanoTime = time.nanoTimestamp;
    pub const microTime = time.microTimestamp;
    pub const milliTime = time.milliTimestamp;
    pub const time = std.time;

    pub fn sleepMicros(us: u64) void {
        sleepNanos(us * 1_000);
    }
    pub fn sleepMillis(ms: u64) void {
        sleepMicros(ms * 1_000);
    }

    var game: ?Game = null;
    var running: bool = false;

    allocator: Allocator,

    window: Window,
    renderer: Renderer,

    updateFn: ?UpdateFn = null,
    renderFn: ?RenderFn = null,

    gKeyboard: ?Keyboard = null,
    gMouse: ?Mouse = null,

    pub fn createArena(self: *Game) ArenaAllocator {
        return ArenaAllocator.init(self.allocator);
    }

    /// Transform the point coordinates : screen <=> local
    ///
    /// local means the y: 0 is at the bottom left
    ///
    /// screen means the y: 0 is at the top left
    pub fn transformCoord(self: *Game, p: Point) Point {
        return .{
            .x = p.x,
            .y = self.window.getSize().y - p.y,
        };
    }

    pub fn getGame() Error!*Game {
        return if (game != null) &game.? else Error.GameNotInitialized;
    }

    pub fn init(allocator: Allocator, title: []const u8, width: u32, height: u32, flags: InitFlags) Error!*Game {
        if (game != null)
            return Error.GameAlreadyInitialized;

        // SDL_Init(SDL_INIT_EVERYTHING)
        try checkError(
            Error,
            sdl.SDL_Init(sdl.SDL_INIT_EVERYTHING),
            "Cannot initialize SDL",
            Error.Initialization,
        );
        errdefer sdl.SDL_Quit();

        // IMG_Init(IMG_INIT_PNG | IMG_INIT_JPG)
        if (!(sdl.IMG_Init(sdl.IMG_INIT_PNG | sdl.IMG_INIT_JPG) & sdl.IMG_INIT_PNG | sdl.IMG_INIT_JPG > 0))
            return errorWithMessage(Error, "Cannot intialize SDL_image", Error.Initialization);
        errdefer sdl.IMG_Quit();

        const window = sdl.SDL_CreateWindow(
            title.ptr,
            sdl.SDL_WINDOWPOS_CENTERED,
            sdl.SDL_WINDOWPOS_CENTERED,
            @intCast(width),
            @intCast(height),
            flags2Int(flags),
        );
        try checkNull(Error, window, "Cannot create Window", Error.OutOfMemory);
        errdefer DestroyWindow(window);

        const renderer = sdl.SDL_CreateRenderer(
            window,
            -1,
            sdl.SDL_RENDERER_PRESENTVSYNC | sdl.SDL_RENDERER_TARGETTEXTURE,
        );
        try checkNull(Error, renderer, "Cannot create renderer", Error.OutOfMemory);
        errdefer DestroyRenderer(renderer);

        const renderTexture = sdl.SDL_CreateTexture(
            renderer,
            sdl.SDL_PIXELFORMAT_RGBA8888,
            sdl.SDL_TEXTUREACCESS_TARGET,
            @intCast(width),
            @intCast(height),
        );
        try checkNull(Error, renderTexture, "Cannot create rendering texture", Error.OutOfMemory);

        game = .{
            .allocator = allocator,
            .window = Window.init(allocator, window.?),
            .renderer = Renderer.init(renderer.?, renderTexture.?),
        };
        return &game.?;
    }
    pub fn deinit(self: *Game) void {
        if (self.gKeyboard) |_|
            self.gKeyboard.?.deinit();
        self.renderer.deinit();
        self.window.deinit();
        sdl.IMG_Quit();
        sdl.SDL_Quit();
    }

    pub fn quit() void {
        running = false;
    }

    pub fn run(self: *Game) anyerror!void {
        if (running)
            return Error.GameAlreadyRunning;
        running = true;
        defer running = false;

        var firstLoop: bool = true;

        var lt: i128 = 0;
        while (running) {
            const dt: f128 = blk: {
                const now = std.time.nanoTimestamp();
                const delta = now - lt;
                lt = now;
                break :blk @as(f128, @floatFromInt(delta)) / @as(f128, 1_000_000_000.0);
            };
            if (firstLoop) {
                // sweet sweet start 60 fps
                std.time.sleep(16_000_000);
                firstLoop = false;
                continue;
            }

            if (self.gKeyboard) |_|
                try self.gKeyboard.?.update();
            if (self.gMouse) |_|
                self.gMouse.?.update();

            pollAllEvents(self.window.window, &running);
            if (!running) return;

            if (self.updateFn) |f|
                try f(self, dt);

            try self.renderer.begin(.{ .a = 255 });

            if (self.renderFn) |f|
                try f(self, &self.renderer);

            try self.renderer.end();
        }
    }

    pub fn setUpdateFn(self: *Game, func: ?UpdateFn) void {
        self.updateFn = func;
    }
    pub fn setRenderFn(self: *Game, func: ?RenderFn) void {
        self.renderFn = func;
    }

    pub fn getMouse(self: *Game) *Mouse {
        if (self.gMouse) |_|
            return @constCast(&self.gMouse.?);

        self.gMouse = Mouse{
            .game = self,
        };
        return &self.gMouse.?;
    }
    pub fn getKeyboard(self: *Game) *Keyboard {
        if (self.gKeyboard) |_|
            return @constCast(&self.gKeyboard.?);

        var len: u32 = 0;
        var arr = sdl.SDL_GetKeyboardState(@ptrCast(&len));
        self.gKeyboard = Keyboard{
            .allocator = self.allocator,
            .keys = arr[0..len],
        };
        return &self.gKeyboard.?;
    }
};

const GameWindow = struct {
    allocator: Allocator,
    window: *SDLWindow,

    pub fn init(allocator: Allocator, window: *SDLWindow) GameWindow {
        return .{
            .allocator = allocator,
            .window = window,
        };
    }
    pub fn deinit(self: *GameWindow) void {
        sdl.SDL_DestroyWindow(self.window);
    }

    pub fn getPosition(self: *GameWindow) Point {
        var p = Point{};
        sdl.SDL_GetWindowPosition(self.window, @ptrCast(&p.x), @ptrCast(&p.y));
        return p;
    }
    pub fn setPosition(self: *GameWindow, p: Point) void {
        sdl.SDL_SetWindowPosition(self.window, @intCast(p.x), @intCast(p.y));
    }

    pub fn getSize(self: *GameWindow) Point {
        var p = Point{};
        sdl.SDL_GetWindowSize(self.window, @ptrCast(&p.x), @ptrCast(&p.y));
        return p;
    }
    pub fn setSize(self: *GameWindow, p: Point) void {
        sdl.SDL_SetWindowSize(self.window, @intCast(p.x), @intCast(p.y));
    }

    pub fn getTitle(self: *GameWindow) []const u8 {
        const t = sdl.SDL_GetWindowTitle(self.window);
        const sz = std.mem.len(t);
        return t[0..sz];
    }
    pub fn setTitle(self: *GameWindow, title: []const u8) !void {
        const t = try self.allocator.alloc(u8, title.len + 1);
        defer self.allocator.free(t);
        std.mem.copyForwards(u8, t, title);
        t[t.len - 1] = 0;
        sdl.SDL_SetWindowTitle(self.window, t.ptr);
    }
};

const GameRenderer = struct {
    renderer: *SDLRenderer,
    renderTexture: *SDLTexture,

    pub fn init(renderer: *SDLRenderer, renderTexture: *SDLTexture) GameRenderer {
        return .{
            .renderer = renderer,
            .renderTexture = renderTexture,
        };
    }
    pub fn deinit(self: *GameRenderer) void {
        DestroyTexture(self.renderTexture);
        DestroyRenderer(self.renderer);
    }

    fn setTarget(self: *GameRenderer, target: ?*SDLTexture) Error!void {
        try checkError(
            Error,
            sdl.SDL_SetRenderTarget(self.renderer, target),
            "cannot change rendering target",
            Error.SdlError,
        );
    }
    fn clear(self: *GameRenderer) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderClear(self.renderer),
            "cannot clear renderer",
            Error.SdlError,
        );
    }

    pub fn setDrawColor(self: *GameRenderer, color: Color) Error!void {
        try checkError(
            Error,
            sdl.SDL_SetRenderDrawColor(self.renderer, color.r, color.g, color.b, color.a),
            "Cannot change drawing color",
            Error.SdlError,
        );
    }
    pub fn getDrawColor(self: *GameRenderer) Error!Color {
        var color: Color = .{};
        try checkError(
            Error,
            sdl.SDL_GetRenderDrawColor(self.renderer, &color.r, &color.g, &color.b, &color.a),
            "Cannot change drawing color",
            Error.SdlError,
        );
        return color;
    }

    pub fn copy(self: *GameRenderer, texture: *SDLTexture, srcRect: ?Rect, dstRect: ?Rect) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderCopy(
                self.renderer,
                texture,
                if (srcRect) |r| &rect2sdl(r) else null,
                if (dstRect) |r| &rect2sdl(r) else null,
            ),
            "Cannot copy texture to renderer",
            Error.SdlError,
        );
    }
    pub fn copyEx(
        self: *GameRenderer,
        texture: *SDLTexture,
        srcRect: ?Rect,
        dstRect: ?Rect,
        rotation: f64,
        center: ?Point,
        flip: Flip,
    ) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderCopyEx(
                self.renderer,
                texture,
                if (srcRect) |r| &rect2sdl(r) else null,
                if (dstRect) |r| &rect2sdl(r) else null,
                rotation,
                if (center) |p| &point2sdl(p) else null,
                @intFromEnum(flip),
            ),
            "Cannot copy texture to renderer",
            Error.SdlError,
        );
    }

    pub fn begin(self: *GameRenderer, bg: Color) Error!void {
        try self.setTarget(self.renderTexture);
        try self.setDrawColor(bg);
        try self.clear();
    }
    pub fn end(self: *GameRenderer) Error!void {
        try self.setTarget(null);
        try self.setDrawColor(.{});
        try self.clear();
        try self.copyEx(self.renderTexture, null, null, 0.0, null, .Vertical);
        sdl.SDL_RenderPresent(self.renderer);
    }

    pub fn drawRect(self: *GameRenderer, rect: Rect) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawRect(self.renderer, rect2sdl(rect)),
            "Cannot draw rectangle",
            Error.SdlError,
        );
    }
    pub fn drawRects(self: *GameRenderer, rects: []const Rect) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawRects(self.renderer, @ptrCast(rects.ptr), rects.len),
            "Cannot draw rectangles",
            Error.SdlError,
        );
    }

    pub fn fillRect(self: *GameRenderer, rect: Rect) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderFillRect(self.renderer, &rect2sdl(rect)),
            "Cannot fill rectangle",
            Error.SdlError,
        );
    }
    pub fn fillRects(self: *GameRenderer, rects: []const Rect) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderFillRects(self.renderer, @ptrCast(rects.ptr), @intCast(rects.len)),
            "Cannot fill rectangles",
            Error.SdlError,
        );
    }

    pub fn drawPoint(self: *GameRenderer, point: Point) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawPoint(self.renderer, &point2sdl(point)),
            "Cannot draw point",
            Error.SdlError,
        );
    }
    pub fn drawPoints(self: *GameRenderer, points: []const Point) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawPoints(self.renderer, @ptrCast(points.ptr), @intCast(points.len)),
            "Cannot draw points",
            Error.SdlError,
        );
    }

    pub fn drawLine(self: *GameRenderer, point1: Point, point2: Point) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawLine(
                self.renderer,
                @intCast(point1.x),
                @intCast(point1.y),
                @intCast(point2.x),
                @intCast(point2.y),
            ),
            "Cannot draw line",
            Error.SdlError,
        );
    }
    pub fn drawLines(self: *GameRenderer, points: []const Point) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawLine(self.renderer, @ptrCast(points.ptr), @intCast(points.len)),
            "Cannot draw line",
            Error.SdlError,
        );
    }

    pub fn drawRectF(self: *GameRenderer, rect: FRect) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawRectF(self.renderer, frect2sdl(rect)),
            "Cannot draw rectangle (float)",
            Error.SdlError,
        );
    }
    pub fn drawRectsF(self: *GameRenderer, rects: []const FRect) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawRectsF(self.renderer, @ptrCast(rects.ptr), @intCast(rects.len)),
            "Cannot draw rectangles (float)",
            Error.SdlError,
        );
    }

    pub fn fillRectF(self: *GameRenderer, rect: FRect) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderFillRectF(self.renderer, &frect2sdl(rect)),
            "Cannot fill rectangle (float)",
            Error.SdlError,
        );
    }
    pub fn fillRectsF(self: *GameRenderer, rects: []const FRect) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderFillRectsF(self.renderer, @ptrCast(rects.ptr), @intCast(rects.len)),
            "Cannot fill rectangles (float)",
            Error.SdlError,
        );
    }

    pub fn drawPointF(self: *GameRenderer, point: FPoint) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawPointF(self.renderer, &fpoint2sdl(point)),
            "Cannot draw point (float)",
            Error.SdlError,
        );
    }
    pub fn drawPointsF(self: *GameRenderer, points: []const FPoint) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawPointsF(self.renderer, @ptrCast(points.ptr), @intCast(points.len)),
            "Cannot draw points (float)",
            Error.SdlError,
        );
    }

    pub fn drawLineF(self: *GameRenderer, point1: FPoint, point2: FPoint) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawLineF(
                self.renderer,
                point1.x,
                point1.y,
                point2.x,
                point2.y,
            ),
            "Cannot draw line (float)",
            Error.SdlError,
        );
    }
    pub fn drawLinesF(self: *GameRenderer, points: []const FPoint) Error!void {
        try checkError(
            Error,
            sdl.SDL_RenderDrawLineF(self.renderer, @ptrCast(points.ptr), @intCast(points.len)),
            "Cannot draw line (float)",
            Error.SdlError,
        );
    }
};

const GameMouse = struct {
    pub const Button = enum(u32) {
        Any = @truncate(-1),
        Unknown = 0,
        Left = sdl.SDL_BUTTON_LMASK,
        Middle = sdl.SDL_BUTTON_MIDDLE,
        Right = sdl.SDL_BUTTON_RIGHT,
        /// On the side of the mouse, farther to your wrist
        Button4 = sdl.SDL_BUTTON_X1MASK,
        /// On the side of the mouse, closer to your wrist
        Button5 = sdl.SDL_BUTTON_X2MASK,
    };

    game: *Game,
    lastState: u32 = 0,

    /// Should not be called externally
    pub fn update(self: *GameMouse) void {
        self.lastState = sdl.SDL_GetMouseState(null, null);
    }
    pub fn isButtonDown(self: *GameMouse, button: Button) bool {
        _ = self;
        const state = sdl.SDL_GetMouseState(null, null);
        if (button == .Any)
            return state > 0;

        return state & @intFromEnum(button) > 0;
    }
    pub fn isButtonPressed(self: *GameMouse, button: Button) bool {
        if (button == .Any) {
            const fields = @typeInfo(Button).Enum.fields;
            inline for (fields) |field| {
                const value: Button = @enumFromInt(field.value);
                if (value == .Any)
                    continue;
                if (self.isButtonPressed(value))
                    return true;
            }
            return false;
        }
        return !(self.lastState & @intFromEnum(button) > 0) and self.isButtonDown(button);
    }
    pub fn isButtonReleased(self: *GameMouse, button: Button) bool {
        if (button == .Any) {
            const fields = @typeInfo(Button).Enum.fields;
            inline for (fields) |field| {
                const value: Button = @enumFromInt(field.value);
                if (value == .Any)
                    continue;
                if (self.isButtonReleased(value))
                    return true;
            }
            return false;
        }
        return self.lastState & @intFromEnum(button) > 0 and !self.isButtonDown(button);
    }
    pub fn getPosition(self: *GameMouse) Point {
        var p = Point{};
        _ = sdl.SDL_GetMouseState(@ptrCast(&p.x), @ptrCast(&p.y));
        return self.game.transformCoord(p);
    }
    pub fn setPosition(self: *GameMouse, pos: Point) void {
        const game = self.game;
        const p = self.game.transformCoord(pos);
        sdl.SDL_WarpMouseInWindow(game.window.window, @intCast(p.x), @intCast(p.y));
    }
};

const GameKeyboard = struct {
    pub const Key = index.Key;

    allocator: Allocator,
    keys: []const u8,
    oldKeys: ?[]u8 = null,

    /// Should not be called externally
    pub fn update(self: *GameKeyboard) Error!void {
        self.deinit();
        const mem = try self.allocator.alloc(u8, self.keys.len);
        errdefer self.allocator.free(mem);
        @memcpy(mem, self.keys);
        self.oldKeys = mem;
    }
    /// Should not be called externally
    pub fn deinit(self: *GameKeyboard) void {
        if (self.oldKeys) |ks|
            self.allocator.free(ks);
        self.oldKeys = null;
    }

    pub fn isKeyDown(self: *GameKeyboard, key: Key) bool {
        if (key == .Any) {
            return self.keys.len > 0;
        }
        return self.keys[@intFromEnum(key)] > 0;
    }
    /// Return whether key has been pressed on last frame and not this frame
    pub fn isKeyPressed(self: *GameKeyboard, key: Key) bool {
        if (self.oldKeys == null) {
            std.debug.print("Old keys not found\n", .{});
            return false;
        }
        if (key == .Any) {
            const fields = @typeInfo(Key).Enum.fields;
            inline for (fields) |field| {
                const value: Key = @enumFromInt(field.value);
                if (value == .Any)
                    continue;
                if (self.isKeyPressed(value))
                    return true;
            }
            return false;
        }
        return !(self.oldKeys.?[@intFromEnum(key)] > 0) and self.isKeyDown(key);
    }
    /// Return whether key has been released on last frame and not this frame
    pub fn isKeyReleased(self: *GameKeyboard, key: Key) bool {
        if (self.oldKeys == null) {
            std.debug.print("Old keys not found\n", .{});
            return false;
        }
        if (key == .Any) {
            const fields = @typeInfo(Key).Enum.fields;
            inline for (fields) |field| {
                const value: Key = @enumFromInt(field.value);
                if (value == .Any)
                    continue;
                if (self.isKeyReleased(value))
                    return true;
            }
            return false;
        }
        return self.oldKeys.?[@intFromEnum(key)] > 0 and !self.isKeyDown(key);
    }
};

fn pollAllEvents(window: ?*SDLWindow, running: *bool) void {
    while (pollEvent()) |event| {
        switch (event.type) {
            sdl.SDL_QUIT => running.* = false, // end the program
            sdl.SDL_WINDOWEVENT => {
                switch (event.window.event) {
                    sdl.SDL_WINDOWEVENT_CLOSE => {
                        if (event.window.windowID == sdl.SDL_GetWindowID(window))
                            running.* = false;
                    },
                    else => {},
                }
            },
            else => {},
        }
        if (!running.*) return;
    }
}

fn pollEvent() ?sdl.SDL_Event {
    var event: sdl.SDL_Event = undefined;
    if (sdl.SDL_PollEvent(@constCast(&event)) > 0) return event;
    return null;
}
