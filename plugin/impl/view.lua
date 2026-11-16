local Transcript = require("impl/transcript")
local Expansion = require("impl/expansion")

local View = {}
View.__index = View

local iconSize = 24
local titleTop = 8
local titleHeight = 30
local iconInset = 8

local function release(owner, key)
    local resource = owner[key]
    owner[key] = nil

    if resource ~= nil then
        pcall(function()
            resource:Destroy()
        end)
    end
end

local function keepScrollbarVisible(scroll)
    if scroll.scrollbarVisible then
        return
    end

    -- PrettyUI hides the bar when content fits. Reserve its normal gutter and
    -- show the full-height thumb without inflating the scrollable content.
    scroll.scrollbarVisible = true
    scroll.contentWidth = math.max(1, scroll.width - scroll.track.width - 2)
    scroll.viewport:SetSize(scroll.contentWidth, 0, 0, 1)
    scroll.viewport:SetScrollSize(scroll.contentWidth, scroll.scrollHeight)
    scroll.content:SetSize(scroll.contentWidth, scroll.scrollHeight)
    scroll.track.hidden, scroll.upArrow.hidden, scroll.downArrow.hidden = false, false, false
    scroll:_LayoutThumbDrag()
end

function View:New(history, dialogue)
    return setmetatable({
        history = history,
        dialogue = dialogue,
        open = false
    }, self)
end

function View:ReleaseExpansion()
    release(self, "scroll")
    release(self, "expansion")
    self.current = nil
end

function View:SetOpen(value)
    if not value then
        self.open = false
        self:ReleaseExpansion()
        self:UpdateLauncherSprite()

        return
    end

    if not self.dialogue.active or self.history.idle then
        return
    end

    self.failedHost = nil
    self.open = true
    self:UpdateLauncherSprite()

    if self.current ~= nil then
        self.current.forceLatest = true
    end
end

function View:Toggle()
    self:SetOpen(not self.open)
end

function View:UpdateLauncherSprite()
    if self.launcher == nil then
        return
    end

    if self.open then
        local image = self.launcherHovered and Plugin.resources.book_selected_hovered or Plugin.resources.book_selected

        if not image.loaded then
            image:Load()
        end

        if image.loaded then
            self.launcher.sprite = image

            return
        end
    end

    self.launcher.sprite = self.launcherHovered
        and id.Sprite.RS3_ICON_BOSS_COLLECTION_LOG_1 or id.Sprite.RS3_ICON_BOSS_COLLECTION_LOG_0
end

function View:AttachLauncher(host)
    local icon = prettyui.NewComponent(ui.Sprite, host)
    self.launcher = icon
    icon:SetSize(iconSize, iconSize)
    icon.enabled = true
    icon.clickthrough = false
    self.launcherHovered = false
    self:UpdateLauncherSprite()

    icon:Subscribe(ui.Hook.ONMOUSEOVER, function()
        self.launcherHovered = true
        self:UpdateLauncherSprite()
    end)

    icon:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        self.launcherHovered = false
        self:UpdateLauncherSprite()
    end)

    icon:Subscribe(ui.Hook.ONCLICK, function()
        self.dialogue:Capture()
        self:Toggle()

        return false
    end)
end

function View:UpdateLauncher()
    local host = Expansion.Find(self.dialogue.host) or self.dialogue.host

    if self.launcherHost ~= host then
        release(self, "launcher")
        self.launcherHost = host

        if host ~= nil then
            self:AttachLauncher(host)
        end
    end

    if host == nil then
        return
    end

    local border = self.dialogue.border or host
    local origin, edge = host.xyGlobal, border.xyGlobal
    local x = edge.x - origin.x + border.width - iconSize - iconInset
    -- Choice panels have no title label; use the regular dialogue title bounds.
    local y = edge.y - origin.y + titleTop + (titleHeight - iconSize) / 2
    local title = self.dialogue.title

    if title ~= nil and title.visibleGlobal and title.height > 0 then
        y = title.xyGlobal.y - origin.y + (title.height - iconSize) / 2
    end

    y = math.floor(y)

    if self.launcher.x ~= x or self.launcher.y ~= y then
        self.launcher:SetPos(x, y)
    end
end

function View:RestoreCloseButton()
    local control, hidden = self.closeButton, self.closeHidden
    self.closeButton, self.closeHidden = nil, nil

    if control ~= nil then
        pcall(function()
            if control.hidden then
                control.hidden = hidden
            end
        end)
    end
end

function View:UpdateCloseButton()
    local close

    if self.dialogue.active and (not self.history.idle or self.dialogue.restart ~= nil)
        and Expansion.Find(self.dialogue.host) ~= nil then
        close = self.dialogue.close
    end

    if self.closeButton ~= close then
        self:RestoreCloseButton()
        self.closeButton = close
        self.closeHidden = close and close.hidden
    end

    if close ~= nil then
        close.hidden = true
    end
end

function View:UpdateHistory(host)
    local frame, content = Expansion.Find(self.dialogue.host)
    local expansion = self.expansion

    if expansion ~= nil and (expansion.frame ~= frame or expansion.content ~= content
        or expansion.viewport ~= host or expansion.owner ~= self.dialogue.host
        or expansion.border ~= self.dialogue.border or not self.open) then
        self:ReleaseExpansion()
    end

    if not self.open or host == nil or frame == nil then
        return
    end

    if self.expansion == nil then
        self.expansion = Expansion:New(frame, content, host, self.dialogue.host, self.dialogue.border)
    end

    if not self.expansion:Update() then
        self:ReleaseExpansion()

        return
    end

    local x, y = self.expansion.x + 12, self.expansion.y + 12
    local width = math.max(1, self.expansion.width - 24)
    local height = self.expansion.height - 24

    if self.scroll == nil then
        self.scroll = prettyui.SimpleView.new(host, {
            categoryID = "auto",
            x = x,
            y = y,
            width = width,
            height = height,
            scrollStep = 40
        })
        self.scroll.root.hidden = true
        self.scroll.isVisible = function()
            return self.open and frame.visibleGlobal and self.dialogue.host ~= nil and self.dialogue.host.visibleGlobal
        end
        self.current = Transcript:New(self.history, self.scroll, self.history.conversation)
    elseif self.scroll.width ~= width or self.scroll.height ~= height then
        self.scroll:SetSize(width, height)
    end

    if self.scroll.root.x ~= x or self.scroll.root.y ~= y then
        self.scroll.root:SetPos(x, y)
        self.scroll:Refresh()
    end

    self.current:Update(self.dialogue.active and not self.history.idle and self.history.conversation or nil)
    self.expansion:Show()
    self.scroll.root.hidden = false
    self.launcher:MoveToFront()
end

function View:UpdateRibbon()
    if self.ribbon == nil then
        return
    end

    local parent = self.ribbonParent
    local width, height = math.max(1, parent.width), math.max(1, parent.height)

    if width ~= self.ribbon.width or height ~= self.ribbon.height then
        self.ribbon:SetSize(width, height)
    end

    local visible = parent.visibleGlobal ~= false

    if visible ~= self.ribbonVisible then
        self.ribbonVisible = visible
        self.ribbon:_StopDrag()
    end

    if visible then
        self.recent:Update()
    end
end

function View:Update()
    local host = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__VIEWPORT)

    if host ~= nil and host == self.failedHost then
        return
    end

    self.host = host
    self:UpdateCloseButton()
    self:UpdateLauncher()
    self:UpdateHistory(host)
    self:UpdateRibbon()
end

function View:MountRibbon(parent)
    release(self, "ribbon")
    self.recent = nil
    self.failedHost = nil
    self.ribbonParent = parent
    self.ribbon = prettyui.SimpleView.new(parent, {
        categoryID = "auto",
        width = math.max(1, parent.width),
        height = math.max(1, parent.height),
        scrollStep = 40
    })
    self.ribbon.root.hidden = true
    self.ribbon.isVisible = function()
        return parent.visibleGlobal ~= false
    end
    self.ribbon.onLayout = keepScrollbarVisible
    self.recent = Transcript:New(self.history, self.ribbon)
    self.recent:Update()
    self.ribbon.root.hidden = false
end

function View:Stop()
    release(self, "launcher")
    self:SetOpen(false)
    self:RestoreCloseButton()
    release(self, "ribbon")
    self.launcherHost = nil
    self.launcherHovered = nil
    self.recent, self.ribbonParent, self.ribbonVisible = nil, nil, nil
    self.host = nil
end

function View:Abort()
    self.failedHost = self.host
    self:Stop()
end

return View
