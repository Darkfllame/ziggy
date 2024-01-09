unpack = unpack or table.unpack

local function update(dt)
    if game.Keyboard:IsPressed("Escape") then
        return game.Quit()
    end
end
local function render(renderer)
    local scope = game.Static {
        timer = game.Time
    }
    for k, v in ipairs(scope) do
        print(k, v)
    end
    if game.Keyboard:IsPressed("E") then
        scope.timer = game.Time
    else
        renderer.color = {r = 255}
    end
    if game.Time - scope.timer < 0.2 then
        renderer.color = {g = 255}
    end
    local mpos = game.Mouse:GetPosition()
    renderer:fillRect(mpos.x-25, mpos.y-25, 50, 50)
end

game.AddUpdateCallback(update)
game.AddRenderCallback(render)