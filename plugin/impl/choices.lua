local text = require("impl/text")

local Choices = {}
Choices.__index = Choices

local hookID = "conversationHistory.choice"
local hooks = { ui.Hook.ONCLICK, ui.Hook.ONOP }
local keys = {}

for index = 1, 5 do
    keys[GameKey["_" .. index]] = index
end

local function visible(control)
    return control ~= nil and control.visibleGlobal and control.alpha > 0
end

local function get(prefix, suffix)
    return ui.Interfaces:GetComponent(id.Component[prefix .. "__" .. suffix])
end

local function actionable(control)
    if not visible(control) then
        return false
    end

    -- Native actions can work with the Lua enabled flag off.
    local ops, named = control.opConfig, false

    for index = 1, ops and ops.numOpNames or 0 do
        local name = ops:GetOpName(index)

        if name ~= nil and name ~= "" then
            named = true

            if not ops:TestOpIsHidden(index) then
                return true
            end
        end
    end

    return not named
end

local function option(prefix, index)
    local button = get(prefix, "OPTION_" .. index)
    local row = get(prefix, "OPTION_" .. index .. "_TEXT")
    local label = get(prefix, "OPTION_TEXT_" .. index)
    local body = ""

    -- OPTION_n_TEXT is a container; OPTION_TEXT_n is the response.
    if button ~= nil and row ~= nil and row.parent == button and visible(label) and label.parent == row
        and text.Plain(label.content) ~= "" then
        body = label.content
    end

    return { text = body, button = button, available = body ~= "" and actionable(button) }
end

function Choices:New(history)
    return setmetatable({ history = history }, self)
end

function Choices:Select(menu, index)
    if self.menu ~= menu or menu.selected then
        return
    end

    local selected = menu.options[index]

    if selected == nil or not selected.available then
        return
    end

    -- Native input can hide/replace the menu before our callback runs.
    menu.selected = true

    local player = PlayerList and PlayerList.Self()
    local name = text.Plain(player and player.displayName)

    local _, entry = self.history:Observe({ speaker = name ~= "" and name or "You", text = selected.text })
    self.pending = entry and { id = entry.id, menu = menu } or nil
end

function Choices:Update(prefix)
    if prefix == nil then
        self:Stop(true)

        return
    end

    local window = get(prefix, "WINDOW")
    local root = get(prefix, "OPTIONS")

    if not visible(window) or not visible(root) then
        self:Stop(true)

        return
    end

    local options, previous = {}, self.menu
    local changed = previous == nil or previous.root ~= root or previous.prefix ~= prefix

    for index = 1, 5 do
        options[index] = option(prefix, index)

        local old = previous and previous.options[index]
        local new = options[index]

        if old == nil or old.text ~= new.text or old.button ~= new.button or old.available ~= new.available then
            changed = true
        end
    end

    if not changed then
        return
    end

    self:Stop(true)

    local menu = { prefix = prefix, root = root, options = options }
    self.menu = menu

    -- Keep the selected answer hidden while its menu is closing. Availability
    -- changes alone don't indicate that the next choice page has arrived.
    local pending = self.pending

    if pending ~= nil then
        local old = pending.menu

        if old.root ~= root or old.prefix ~= prefix then
            self.pending = nil
        else
            for index, entry in ipairs(options) do
                if entry.text ~= "" and entry.text ~= old.options[index].text then
                    self.pending = nil

                    break
                end
            end
        end
    end

    for index, entry in ipairs(options) do
        if entry.available then
            for _, hook in ipairs(hooks) do
                entry.button:Subscribe(hook, hookID, function()
                    self:Select(menu, index)

                    return true
                end)
            end
        end
    end
end

function Choices:OnKeyDown(event)
    if event.isRepeat or (event.modifiers or 0) ~= 0 or Keyboard.IsBlocked() then
        return
    end

    local menu, index = self.menu, keys[event.gameKey]

    if index == nil or menu == nil or not visible(menu.root) then
        return
    end

    self:Update(menu.prefix)

    if self.menu ~= nil then
        self:Select(self.menu, index)
    end
end

function Choices:Stop(keepPending)
    local menu = self.menu
    self.menu = nil

    if not keepPending then
        self.pending = nil
    end

    if menu == nil then
        return
    end

    for _, entry in ipairs(menu.options) do
        if entry.available then
            for _, hook in ipairs(hooks) do
                pcall(function()
                    entry.button:Unsubscribe(hook, hookID)
                end)
            end
        end
    end
end

return Choices
