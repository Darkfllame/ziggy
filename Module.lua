---@meta

ZGE = {}

---@class Renderer
t_Renderer = {}

---@class Color
---@field r integer
---@field g integer
---@field b integer
t_Color = {}

---Add a callback on game update
---@param cb fun(dt: number)
function ZGE.AddUpdateCallback(cb)end
---Add a callback on game rendering
---@param cb fun(renderer: Renderer)
function ZGE.AddRenderCallback(cb)end