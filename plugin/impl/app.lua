local History = require("impl/history")
local Dialogue = require("impl/dialogue")
local View = require("impl/view")

local app = {}
local eventID = "conversationHistory"
local history, dialogue, view
local subscriptions = {}
local lastError

local function subscribe(event, callback)
    event.Subscribe(eventID, function(payload)
        local ok, message = pcall(callback, payload)

        if not ok then
            if view ~= nil then
                view:Abort()
            end

            if message ~= lastError then
                lastError = message
                print("Conversation History: " .. tostring(message))
            end
        end
    end)

    subscriptions[#subscriptions + 1] = event
end

function app.Start()
    if history ~= nil then
        return
    end

    history = History:New()
    dialogue = Dialogue:New(history)
    view = View:New(history, dialogue)

    subscribe(Event.VarTransmit, function(event)
        dialogue:OnVarTransmit(event)
    end)

    subscribe(Event.ServerLogic, function()
        dialogue:OnServerLogic()
    end)

    subscribe(Event.MiniMenuEntrySelected, function(event)
        dialogue:OnInteraction(event)
    end)

    subscribe(Event.Logic, function()
        dialogue:Capture(true)
    end)

    subscribe(Event.Draw, function()
        dialogue:Capture()
        view:Update()
    end)

    subscribe(Event.KeyDown, function(event)
        if Keyboard.IsBlocked() or event.isRepeat then
            return
        end

        dialogue.choices:OnKeyDown(event)

        if event.gameKey == GameKey.H and Keyboard.IsAltDown() then
            dialogue:Capture()
            view:Toggle()
        elseif not view.open and (event.gameKey == GameKey.SPACE or event.gameKey == GameKey.ENTER) then
            dialogue:Capture()
        end
    end)

    subscribe(Event.ContentLayerReady, function(event)
        view:MountRibbon(event.component)
    end)

    subscribe(Event.GameStateChanged, function(event)
        if event.newState == GameState.LOGINSCREEN or event.newState == GameState.LOBBY then
            dialogue:Stop()
            history:Clear()
            view:Stop()
        end
    end)
end

function app.Stop()
    for _, event in ipairs(subscriptions) do
        event.Unsubscribe(eventID)
    end

    subscriptions = {}

    if dialogue ~= nil then
        dialogue:Stop()
    end

    if view ~= nil then
        view:Stop()
    end

    history, dialogue, view, lastError = nil, nil, nil, nil
end

return app
