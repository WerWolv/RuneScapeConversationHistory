local text = require("impl/text")
local Choices = require("impl/choices")

local Dialogue = {}
Dialogue.__index = Dialogue

local sources = {}
local captureHook = "conversationHistory.capture"
local idleTicks = 25

local function addSource(prefix, source)
    for _, key in ipairs({ "root", "frame", "body", "left", "right", "continue", "border", "close" }) do
        if source[key] ~= nil then
            source[key] = id.Component[prefix .. "__" .. source[key]]
        end
    end

    sources[#sources + 1] = source
end

-- Choices take priority over any stale message boxes.
for _, prefix in ipairs({ "CHOICE_V2_FREM", "CHOICE_V2_OVERLAY", "CHOICE_V2" }) do
    addSource(prefix, {
        root = "WINDOW",
        choices = true,
        border = "BORDER",
        close = "CLOSE",
        choicePrefix = prefix ~= "CHOICE_V2_FREM" and prefix or nil
    })
end

-- The two-chathead interface shares one title and message. Prefer it over
-- single-speaker panels that can remain loaded during the transition.
addSource("CHAT_V2_PAIR", {
    root = "LAYER_1",
    body = "CHAT_TEXT",
    left = "TITLE_TEXT",
    border = "BORDER",
    continue = "CLICK_CONTINUE_BUTTON"
})

for _, prefix in ipairs({ "CHAT_V2_LEFT", "CHAT_V2_RIGHT",
    "CHAT_V2_LEFT_OVERLAY", "CHAT_V2_RIGHT_OVERLAY" }) do
    addSource(prefix, {
        root = "LAYER_1",
        body = "CHAT_TEXT",
        left = "TITLE_TEXT",
        border = "BORDER",
        continue = "CLICK_CONTINUE_BUTTON"
    })
end

addSource("MESBOX_V2", {
    root = "CONTENT",
    body = "MESBOX_TEXT",
    border = "BORDER",
    continue = "CLICK_CONTINUE_BUTTON"
})

addSource("OBJBOX_V2", {
    root = "LAYER_1",
    body = "OBJBOX_TEXT",
    border = "BORDER",
    continue = "CLICK_CONTINUE_BUTTON"
})

addSource("OBJBOX_OVERLAY_V2", {
    root = "OBJBOX_TEXT",
    body = "OBJBOX_TEXT",
    noButton = true
})

for _, prefix in ipairs({ "CHAT_V3", "CHAT_V3_CHOICE", "CHAT_V3_OVERLAY" }) do
    local choice = prefix == "CHAT_V3_CHOICE"

    addSource(prefix, {
        root = choice and "CHAT_V3_CHOICE_HOLDER" or "CHAT_V3",
        frame = "CHAT_TEXT_FRAME_LAYER_1",
        body = "CHAT_TEXT",
        choices = choice,
        border = "BACKGROUND_FRAME_LAYER",
        left = not choice and "CHAT_LEFT_NAME_TEXT" or nil,
        right = "CHAT_RIGHT_NAME_TEXT",
        continue = prefix == "CHAT_V3" and "CLICK_CONTINUE" or nil
    })
end

local function component(componentID)
    return componentID and ui.Interfaces:GetComponent(componentID) or nil
end

local function visible(control)
    return control ~= nil and control.visibleGlobal and control.alpha > 0
end

local function content(componentID)
    local control = component(componentID)

    return visible(control) and control.content or ""
end

function Dialogue:New(history)
    return setmetatable({
        history = history,
        absentTicks = 0,
        choices = Choices:New(history)
    }, self)
end

function Dialogue:Read()
    local page

    for _, source in ipairs(sources) do
        local root = component(source.root)

        if visible(root) then
            local body = text.Format(content(source.body))

            if not text.IsPlaceholder(body) then
                local title = component(source.left)
                local speaker = text.Plain(visible(title) and title.content or "")

                if speaker == "" then
                    title = component(source.right)
                    speaker = text.Plain(visible(title) and title.content or "")
                end

                -- Speakerless choice prompts are UI, not dialogue.
                if source.choices and speaker == "" then
                    body = ""
                end

                page = {
                    root = root,
                    text = body,
                    speaker = speaker,
                    title = title,
                    source = source,
                    host = not source.noButton and (component(source.frame) or root) or nil
                }

                if text.Plain(body) ~= "" or (source.choices and source.body == nil) then
                    return page
                end
            end
        end
    end

    return page
end

function Dialogue:BindContinue(control)
    if control == self.continue then
        return
    end

    local previous = self.continue
    self.continue = control

    if previous ~= nil then
        pcall(function()
            previous:Unsubscribe(ui.Hook.ONCLICK, captureHook)
        end)
    end

    if control ~= nil then
        control:Subscribe(ui.Hook.ONCLICK, captureHook, function()
            self:Capture()

            return true
        end)
    end
end

function Dialogue:Capture(logicTick)
    local page = self:Read()
    local restart = self.restart

    -- Don't copy the still-visible old page after Talk-to; wait for a change or server refresh.
    if restart ~= nil and page ~= nil and not restart.ready and page.root == restart.page.root
        and page.text == restart.page.text and page.speaker == restart.page.speaker then
        return
    end

    self.restart = nil

    local source = page and page.source
    self.active = page ~= nil
    self.host = page and page.host
    self.title = page and page.title
    self.border = source and component(source.border)
    self.close = source and component(source.close)
    self:BindContinue(source and component(source.continue))
    self.choices:Update(source and source.choicePrefix)

    if page ~= nil then
        self.absentTicks = 0

        -- A conversation can open with choices before there is any spoken text.
        if source.choices then
            self.history:BeginConversation()
        end

        local _, entry, repeatedOpening = self.history:Observe(page)

        if entry ~= nil then
            self.choices.pending = nil
        end

        -- A suppressed restart reuses an existing history line; keep it visible.
        self.visibleEntry = entry and not repeatedOpening and entry.id
            or self.choices.pending and self.choices.pending.id
    else
        self.visibleEntry = self.choices.pending and self.choices.pending.id

        if logicTick then
            self.absentTicks = self.absentTicks + 1

            if self.absentTicks >= idleTicks then
                self.choices.pending = nil
                self.visibleEntry = nil
                self.history:EndConversation()
            end
        end
    end

    return page
end

function Dialogue:OnVarTransmit(event)
    local name = event.var.configName

    if name ~= "CHAT_V3_UPDATE_INTERFACE" and name ~= "PAGEPOS" then
        return
    end

    -- Equal-value transmissions matter too; the current label can still be the old page.
    if self.restart ~= nil then
        self.restart.signalled = true
    else
        self:Capture()
    end
end

function Dialogue:OnServerLogic()
    if self.restart ~= nil and self.restart.signalled then
        self.restart.ready = true
    end

    self:Capture()
end

function Dialogue:OnInteraction(event)
    local entry = event.entry

    if entry == nil or entry.actionEntryType ~= MiniMenuEntryType.NPC then
        return
    end

    local verb = text.Plain(entry.verbText):lower():gsub("[%s%-]", "")

    if verb ~= "talkto" and verb ~= "talk" and verb ~= "speakto" then
        return
    end

    self:Capture()

    local page = self:Read()

    -- Reset capture without detaching the still-visible dialogue while the
    -- replacement page is pending.
    self:BindContinue(nil)
    self.choices:Stop()
    self.absentTicks = 0
    self.history:EndConversation()
    self.restart = page and { page = page } or nil
end

function Dialogue:Stop()
    self:BindContinue(nil)
    self.choices:Stop()
    self.active = false
    self.absentTicks = 0
    self.host, self.title, self.border, self.close, self.restart = nil, nil, nil, nil, nil
    self.visibleEntry = nil
    self.history:EndConversation()
end

return Dialogue
