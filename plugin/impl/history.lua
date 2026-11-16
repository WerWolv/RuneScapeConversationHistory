local text = require("impl/text")

local History = {}
History.__index = History

function History:New(limit)
    return setmetatable({
        entries = {},
        limit = limit or 500,
        revision = 0,
        nextID = 1,
        conversation = 0,
        idle = true
    }, self)
end

function History:Observe(snapshot)
    if snapshot == nil then
        return false
    end

    local body = text.Format(snapshot.text)

    if text.Plain(body) == "" or text.IsPlaceholder(body) then
        return false
    end

    local speaker = text.Plain(snapshot.speaker)

    if speaker == "" then
        speaker = "Narrator"
    end

    local key = speaker .. "\0" .. body

    if key == self.lastKey then
        return false
    end

    self:BeginConversation()
    self.lastKey = key
    self.entries[#self.entries + 1] = {
        id = self.nextID,
        speaker = speaker,
        text = body,
        conversation = self.conversation
    }
    self.nextID = self.nextID + 1

    if #self.entries > self.limit then
        table.remove(self.entries, 1)
    end

    self.revision = self.revision + 1

    return true
end

function History:BeginConversation()
    if self.idle then
        self.conversation = self.conversation + 1
        self.idle = false
    end
end

function History:EndConversation()
    self.lastKey = nil
    self.idle = true
end

function History:Clear()
    self.entries = {}
    self.revision = self.revision + 1
    -- Keep lastKey while dialogue remains visible, so Clear stays empty until it advances.
end

return History
