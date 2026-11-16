local text = {}

-- Keep dialogue colours and line breaks, but not native interaction/animation tags.
-- Literal < and > are represented with the client's own escape tags.
function text.Format(value)
    if type(value) ~= "string" then
        return ""
    end

    value = value:gsub("\r\n", "\n"):gsub("\r", "\n")
    value = value:gsub("<([^>]*)>", function(tag)
        local lower = tag:lower()

        if lower == "br" or lower == "br/" then
            return "<br>"
        end

        if lower == "lt" or lower == "gt" or lower == "/col" or lower:match("^col=%x%x%x%x%x%x$") then
            return "<" .. lower .. ">"
        end

        return ""
    end)

    return (value:gsub("\n", "<br>"):gsub("^%s+", ""):gsub("%s+$", ""))
end

function text.Plain(value)
    return (text.Format(value):gsub("<br>", " "):gsub("<lt>", "\1"):gsub("<gt>", "\2")
        :gsub("<[^>]*>", ""):gsub("\1", "<"):gsub("\2", ">")
        :gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

function text.Escape(value)
    return (value:gsub("[<>]", { ["<"] = "<lt>", [">"] = "<gt>" }))
end

function text.IsPlaceholder(value)
    -- Native default text can surface through several dialogue components,
    -- with colour tags, line breaks, non-breaking spaces or different punctuation.
    local key = text.Plain(value):lower():gsub("[^a-z]", "")

    return key == "youhavejustbeenhandedthisitem"
end

return text
