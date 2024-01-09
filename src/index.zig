pub const std = @import("std");
pub const GameContext = @import("GameContext.zig");
pub const Key = @import("Key.zig").Key;
pub const LinkedList = @import("LinkedList.zig").LinkedList;
pub const String = @import("String.zig").String;
pub const sdl = @import("sdl2");
pub const FileWriter = std.io.Writer(std.fs.File, std.fs.File.WriteError, std.fs.File.write);
pub const FileReader = std.io.Reader(std.fs.File, std.fs.File.ReadError, std.fs.File.read);

var errorMessage: ?[]const u8 = null;

pub fn checkNull(comptime E: type, value: ?*anyopaque, errMessage: []const u8, err: E) E!void {
    if (value == null)
        return errorWithMessage(E, errMessage, err);
}

pub fn checkError(comptime E: type, ret: c_int, errMessage: []const u8, err: E) E!void {
    if (ret < 0)
        return errorWithMessage(E, errMessage, err);
}

pub fn errorWithMessage(comptime E: type, message: []const u8, err: E) E {
    var str = String.init(std.heap.c_allocator);
    defer str.deinit();
    std.fmt.format(str.writer(), "{[message]s}: {[err]s}", .{
        .err = sdl.SDL_GetError(),
        .message = message,
    }) catch std.os.exit(1);
    errorMessage = str.toOwned() catch unreachable;
    return err;
}

pub fn getError() []const u8 {
    return if (errorMessage) |m| m else "";
}
/// Call this function at the end of your program to clear the error
/// because i'm a bad programmer and said that the internal error message
/// buffer is allocated by an arbitrary allocator (don't do that on your
/// projects please)
pub fn clearError() void {
    if (errorMessage) |m| std.heap.c_allocator.free(m);
}

pub fn getWorkingDirectory() std.fs.Dir {
    return std.fs.cwd();
}
var projectDir: ?std.fs.Dir = null;
/// null means that no project has been opened
pub fn getProjectDirectory() ?std.fs.Dir {
    return projectDir;
}
pub fn setProjectDirectory(path: []const u8) std.fs.Dir {
    projectDir = getWorkingDirectory().openDir(path, .{});
    return projectDir.?;
}
