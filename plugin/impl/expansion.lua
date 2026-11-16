local Expansion = {}
Expansion.__index = Expansion

local borderParts = { "top", "topLeft", "topRight", "left", "right" }
local maxHeight = 280
local edgeGap = 8
local borderOverlap = 2
local backgroundColour = 0x2D2A23FF

function Expansion.Find(host)
    local frame = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__MES_WINDOW)
    local content = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__MES_WINDOW_CONTENT)

    if host == nil or not host.visibleGlobal or frame == nil or content == nil or not frame.visibleGlobal then
        return
    end

    while host ~= nil and host ~= content do
        host = host.parent
    end

    if host ~= nil and content.parent == frame then
        return frame, content
    end
end

-- Native dialogue borders are layers populated with dynamic sprite components.
local function readBorder(border)
    if border == nil or not border.visibleGlobal then
        return
    end

    local parts = {}
    local centre = border.xyGlobal.x + border.width / 2

    border:IterateDynamicComponents(function(child)
        if child.type == ui.ComponentType.SPRITE and child.visibleGlobal then
            local sprite = child.spriteID
            local right = child.xyGlobal.x > centre

            if sprite == id.Sprite.RS3_MAIN_MODAL_TOP_TILE then
                parts.top = child
            elseif sprite == id.Sprite.RS3_MAIN_MODAL_TOP_CORNER then
                parts[right and "topRight" or "topLeft"] = child
            elseif sprite == id.Sprite.RS3_MAIN_MODAL_SIDE_TILE then
                parts[right and "right" or "left"] = child
            end
        end

        return false
    end)

    for _, name in ipairs(borderParts) do
        if parts[name] == nil then
            return
        end
    end

    return parts
end

function Expansion:New(frame, content, viewport, owner, border)
    local parts = readBorder(border)

    if parts == nil then
        error("ConversationHistory: native header artwork not recognized.")
    end

    return setmetatable({
        frame = frame,
        content = content,
        viewport = viewport,
        owner = owner,
        border = border,
        parts = parts,
        controls = {}
    }, self)
end

function Expansion:Attach()
    local background = prettyui.NewComponent(ui.Rectangle, self.viewport, { categoryID = "auto" })
    self.controls.fill = background
    background.hidden = true
    background.clickthrough = true
    background.fill = true
    background.rgba = backgroundColour

    for _, name in ipairs(borderParts) do
        local sprite = self.parts[name]
        local control = prettyui.NewComponent(ui.Sprite, self.viewport, { categoryID = "auto" })
        self.controls[name] = control
        control.hidden = true
        control.clickthrough = true
        control:SetConfig(sprite:GetConfigCopy())

        if sprite.runtimeSprite ~= nil then
            control.sprite = sprite.runtimeSprite
        else
            control.spriteID = sprite.spriteID
        end
    end
end

function Expansion:Update()
    local origin, edge = self.viewport.xyGlobal, self.border.xyGlobal
    local height = math.min(maxHeight, math.max(0, edge.y - origin.y - edgeGap))

    if height < 64 then
        return false
    end

    local x, y = edge.x - origin.x, edge.y - origin.y - height
    local width = self.border.width

    if self.controls.fill == nil then
        self:Attach()
    end

    if self.x ~= x or self.y ~= y or self.width ~= width or self.height ~= height then
        local function place(name, px, py, w, h)
            self.controls[name]:SetPos(x + px, y + py)
            self.controls[name]:SetSize(w, h)
        end

        local parts = self.parts
        local left, right, top = parts.left.width, parts.right.width, parts.top.height
        -- Overlap the transparent outer edge, preserving the native gold divider.
        local bottom = height + borderOverlap

        place("fill", left, top, width - left - right, bottom - top)
        place("top", parts.topLeft.width, 0, width - parts.topLeft.width - parts.topRight.width, top)
        place("topLeft", 0, 0, parts.topLeft.width, parts.topLeft.height)
        place("topRight", width - parts.topRight.width, 0, parts.topRight.width, parts.topRight.height)
        place("left", 0, parts.topLeft.height, left, bottom - parts.topLeft.height)
        place("right", width - right, parts.topRight.height, right, bottom - parts.topRight.height)
    end

    self.x, self.y, self.width, self.height = x, y, width, height

    return true
end

function Expansion:Show()
    for _, control in pairs(self.controls) do
        control.hidden = false
    end
end

function Expansion:Destroy()
    local controls = self.controls
    self.controls = {}

    for _, control in pairs(controls) do
        pcall(function()
            control:Destroy()
        end)
    end
end

return Expansion
