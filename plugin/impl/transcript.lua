local text = require("impl/text")

local Transcript = {}
Transcript.__index = Transcript

local bodyFont = id.Font.NOTOSANS_16
local nameFont = id.Font.NOTOSANS_SEMIBOLD_13
local separatorText = "New conversation"

local function label(parent, font, colour)
    local control = prettyui.NewComponent(ui.Text, parent)
    control.clickthrough = true
    control.font = font
    control.rgba = colour
    control.maxLines = 0
    control.isShadowed = true
    control:AlignTo(ui.AlignMode.TOPLEFT)

    return control
end

function Transcript:New(history, scroll, conversation)
    return setmetatable({
        history = history,
        scroll = scroll,
        conversation = conversation,
        rows = {},
        pool = {},
        forceLatest = true
    }, self)
end

function Transcript:BuildRows(width)
    local groups = {}

    for _, entry in ipairs(self.history.entries) do
        if entry.id ~= self.hiddenEntry and (self.conversation == nil or entry.conversation == self.conversation) then
            local group = groups[#groups]

            if group == nil or group.speaker ~= entry.speaker or group.conversation ~= entry.conversation then
                group = {
                    id = entry.id,
                    speaker = entry.speaker,
                    conversation = entry.conversation,
                    paragraphs = {}
                }
                groups[#groups + 1] = group
            end

            group.paragraphs[#group.paragraphs + 1] = entry.text .. "</col>"
        end
    end

    local font, speakerFont = config.Font.FromID(bodyFont), config.Font.FromID(nameFont)
    local top, previous = 0, nil
    self.separatorWidth = speakerFont:GetStringWidth(separatorText)

    for _, row in ipairs(groups) do
        row.text = table.concat(row.paragraphs, "<br><br>")
        row.paragraphs = nil
        row.name = text.Escape(row.speaker)
        row.separatorHeight = previous and previous ~= row.conversation
            and speakerFont:GetStringHeightAndLineCount(separatorText, width, speakerFont.baseline, false, false, false) or 0

        local separatorSpace = row.separatorHeight > 0 and row.separatorHeight + speakerFont.baseline or 0

        row.nameHeight = speakerFont:GetStringHeightAndLineCount(row.name, width, speakerFont.baseline, false, false, false)
        row.bodyHeight = font:GetStringHeightAndLineCount(row.text, width, font.baseline, false, false, false)
        row.top, row.nameTop, row.bodyTop = top, separatorSpace + 8, separatorSpace + row.nameHeight + 12
        row.height = row.bodyTop + row.bodyHeight + 16
        top, previous = top + row.height, row.conversation
    end

    self.rows = groups
    self.contentHeight = top
end

local function hideSeparator(row)
    if row.separator ~= nil then
        row.separator.hidden = true
        row.separatorLines.hidden = true
    end
end

function Transcript:RenderSeparator(row, entry, width)
    if entry.separatorHeight == 0 then
        hideSeparator(row)

        return
    end

    if row.separator == nil then
        row.separator = label(self.scroll.content, nameFont, 0xA0A0A0FF)
        row.separator.content = separatorText
        row.separator:AlignTo(ui.AlignMode.CENTRE, ui.AlignMode.TOPLEFT)
        row.separatorLines = prettyui.NewComponent(ui.Canvas, self.scroll.content)
        row.separatorLines.clickthrough = true
    end

    row.separator.hidden = false
    row.separator:SetPos(12, entry.top + 8)
    row.separator:SetSize(width, entry.separatorHeight)

    local lines = row.separatorLines
    local length = math.max(0, math.floor((width - self.separatorWidth) / 2) - 12)

    lines.hidden = length == 0
    lines:SetPos(12, entry.top + 8)
    lines:SetSize(width, entry.separatorHeight)
    lines:Clear()

    if length > 0 then
        local y = math.floor(entry.separatorHeight / 2)

        lines:AddGradientH(0, y, length, 1, 0xA0A0A000, 0xA0A0A0CC)
        lines:AddGradientH(width - length, y, length, 1, 0xA0A0A0CC, 0xA0A0A000)
    end
end

function Transcript:Render(width)
    local used, top = 0, self.scroll.scrollY

    for _, entry in ipairs(self.rows) do
        if entry.top >= top + self.scroll.height then
            break
        end

        if entry.top + entry.height > top then
            used = used + 1

            local row = self.pool[used]

            if row == nil then
                row = {
                    speaker = label(self.scroll.content, nameFont, 0xD8C695FF),
                    body = label(self.scroll.content, bodyFont, 0xEEEEEEFF)
                }
                self.pool[used] = row
            end

            self:RenderSeparator(row, entry, width)
            row.speaker.hidden, row.body.hidden = false, false
            row.speaker:SetPos(12, entry.top + entry.nameTop)
            row.speaker:SetSize(width, entry.nameHeight)
            row.speaker.content = entry.name
            row.body:SetPos(12, entry.top + entry.bodyTop)
            row.body:SetSize(width, entry.bodyHeight + 2)
            row.body.content = entry.text
        end
    end

    for index = used + 1, #self.pool do
        local row = self.pool[index]
        row.speaker.hidden, row.body.hidden = true, true
        hideSeparator(row)
    end
end

function Transcript:Update(conversation, hiddenEntry)
    if conversation ~= nil and conversation ~= self.conversation then
        self.conversation, self.revision, self.forceLatest = conversation, nil, true
    end

    -- Capture immediately, but reveal the line only after it leaves the native dialogue.
    if hiddenEntry ~= self.hiddenEntry then
        self.hiddenEntry = hiddenEntry
        self.revision = nil
    end

    local scroll = self.scroll
    local width = math.max(40, scroll.width - 42)
    local resized = width ~= self.width or scroll.height ~= self.height
    local changed = self.revision ~= self.history.revision
    local oldTop = scroll.scrollY
    local atEnd = oldTop >= math.max(0, scroll.contentHeight - scroll.height) - 2

    if resized or changed then
        local anchor, offset

        for _, row in ipairs(self.rows) do
            if row.top + row.height > oldTop then
                anchor, offset = row.id, oldTop - row.top

                break
            end
        end

        self:BuildRows(width)
        scroll:SetContentHeight(self.contentHeight)

        if not self.forceLatest and not atEnd and anchor ~= nil then
            for _, row in ipairs(self.rows) do
                if row.id == anchor then
                    scroll:SetScrollPosition(row.top + offset)

                    break
                end
            end
        end

        self.width, self.height, self.revision = width, scroll.height, self.history.revision
    end

    if self.forceLatest or (changed and atEnd) then
        scroll:SetScrollPosition(self.contentHeight)
        self.forceLatest = false
    end

    if resized or changed or self.renderedTop ~= scroll.scrollY then
        self:Render(width)
        self.renderedTop = scroll.scrollY
    end
end

return Transcript
