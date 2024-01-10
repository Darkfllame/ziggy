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
    if game.Mouse:IsPressed("Left") then
        scope.timer = game.Time
    else
        renderer.color = {r = 255}
    end
    if game.Time - scope.timer < 0.2 then
        renderer.color = {g = 255}
    end
    local mpos = game.Mouse:GetPosition()
    mpos.x = mpos.x - 25
    mpos.y = mpos.y - 25
    renderer:drawRects({
        mpos.x,         mpos.y     , 50, 50,
        mpos.x - 75,    mpos.y     , 50, 50,
        mpos.x + 75,    mpos.y     , 50, 50,
        mpos.x,         mpos.y - 75, 50, 50,
        mpos.x,         mpos.y + 75, 50, 50,
    })
end

game.AddUpdateCallback(update)
game.AddRenderCallback(render)