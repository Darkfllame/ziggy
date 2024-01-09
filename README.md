# Ziggy
Dumb ass project. Just a zig game engine with lua implementation
## Lua implementation
You can add update & render callbacks with the `game.AddUpdateCallback` and `game.AddRenderCallback` functions respectively,
if you want the entire API, there it is: (not finished)
- game : ZGE.Game
- - > AddUpdateCallback(fn) : void
- - > AddRenderCallback(fn) : void
- - > Static(table) // makes a table one-time set, look in in test.lua
- - > Keyboard : ZGE.Keyboard
- - - > IsDown(key) : boolean // returns whether the given key is pressed (check out game.Key), you can pass nil or don't pass key to the function, same as IsDown(game.Key.Any)
- - - > IsPressed(key) : boolean // returns whether the given key has just been pressed (not a callback, dumbass), you can pass game.Key.Any/nil/no value, will check for any key pressed
- - - > IsReleased(key) : boolean // returns whether the given key has justb been released (still not a callback), you can pass game.Key.Any/nil/no value, will check for any key released
- - > Mouse : ZGE.Mouse
- - - > IsDown(button)
- - > Time : number
- - > Key : Enum // All the keys are in src/Key.zig
- - > Button : Enum // Any / Left / Right / Middle / Right / Button4 / Button5
