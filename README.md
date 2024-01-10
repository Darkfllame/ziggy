# Ziggy
Dumb ass project. Just a zig game engine with lua implementation
## Lua implementation
You can add update & render callbacks with the `game.AddUpdateCallback` and `game.AddRenderCallback` functions respectively,
if you want the entire API, there it is:

> game : ZGE.Game
- > AddUpdateCallback(fn) : void
- > AddRenderCallback(fn) : void
- > Static(table) // makes a table one-time set, look in in test.lua
- > Keyboard : ZGE.Keyboard
  - > :IsDown(key) : boolean
    > 
    > Returns whether the given key is pressed (check out game.Key), you can pass nil or don't pass key to the function, same as IsDown(game.Key.Any)
  - > :IsPressed(key) : boolean
    > 
    > Returns whether the given key has just been pressed (not a callback, dumbass), you can pass game.Key.Any/nil/no value, will check for any key pressed
  - > :IsReleased(key) : boolean
    > 
    > Returns whether the given key has justb been released (still not a callback), you can pass game.Key.Any/nil/no value, will check for any key released
- > Mouse : ZGE.Mouse
  - > :IsDown(button) : boolean
    >
    > Same as Keyboard:IsDown() but with a game.Button
  - > :IsPressed(button) : boolean
    >
    > Same as Keyboard:IsPressed() but with a game.Button
  - > :IsReleased(button) : boolean
    >
    > Same as Keyboard:IsReleased() but with a game.Button
  - > :GetPosition() : {x: number, y: number}
    >
    > Return the current position of the mouse relative to the bottom left of the window
  - > :SetPosition(pos: {x: number, y: number}) : void
    >
    > Sets the current mouse position relative to the bottom left of the window
- > Time : number
  >
  > Nano time precision
- > Key : Enum
  >
  > All the keys are in src/Key.zig
- > Button : Enum
  >
  > Any / Left / Right / Middle / Right / Button4 / Button
> game.Renderer (not that much rn)
- > :fillRect(x, y, w, h) : void
  > :fillRects(array: {x: number, y: number, w: number, h: number}) : void

  > Fill a rectangle(s) on the screen (x, y from the bottom left)
- > :drawRect(x, y, w, h) : void
  > :drawRects(array: {x: number, y: number, w: number, h: number}) : void
  >
  > Draw a rectangle on the screen (x, y from the bottom left)
- > :drawLine(x, y, x2, y2) : void
  > :drawLines(array: {x: number, y: number, w: number, h: number}) : void
  >
  > Draw a line on the screen (x, y from the bottom left)
- > :drawPoint(x, y) : void
  > :drawPoints(array: {x: number, y: number}) : void
  >
  > Draw a pixel on the screen (x, y from the bottom left)
- > color : {r: number = 0, g: number = 0, b: number = 0, a: number = 255}
  >
  > Sets the color of the renderer (can be combined with drawing functions)
