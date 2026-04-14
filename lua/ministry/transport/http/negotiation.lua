local M = {}

local function normalize_media_type(value)
    if type(value) ~= 'string' then
        return nil
    end

    local media_type = vim.trim(value):match('^[^;]+')
    if media_type == nil or media_type == '' then
        return nil
    end

    return media_type:lower()
end

local function parse_qvalue(value)
    if value == nil then
        return 1
    end

    local number = tonumber(vim.trim(value))
    if number == nil or number < 0 then
        return 0
    end

    if number > 1 then
        return 1
    end

    return number
end

local function parse_media_range(value)
    if type(value) ~= 'string' then
        return nil
    end

    local media_type = nil
    local q = 1

    for part in value:gmatch('[^;]+') do
        local trimmed = vim.trim(part)

        if media_type == nil then
            media_type = trimmed:lower()
        else
            local name, param_value = trimmed:match('^([^=]+)=(.*)$')
            if name ~= nil and name:lower() == 'q' then
                q = parse_qvalue(param_value)
            end
        end
    end

    if media_type == nil or media_type == '' then
        return nil
    end

    local main_type, sub_type = media_type:match('^([^/]+)/([^/]+)$')
    if main_type == nil or sub_type == nil then
        return nil
    end

    return {
        media_type = media_type,
        main_type = main_type,
        sub_type = sub_type,
        q = q,
    }
end

local function content_type_match_specificity(media_range, content_type)
    if media_range == nil then
        return nil
    end

    local normalized_content_type = normalize_media_type(content_type)
    if normalized_content_type == nil then
        return nil
    end

    if media_range.media_type == normalized_content_type then
        return 3
    end

    local content_main, content_sub = normalized_content_type:match('^([^/]+)/([^/]+)$')
    if content_main == nil or content_sub == nil then
        return nil
    end

    if media_range.main_type == content_main and media_range.sub_type == content_sub then
        return 2
    end

    local media_suffix = media_range.sub_type:match('^%*%+(.+)$')
    local content_suffix = content_sub:match('%+(.+)$')
    if media_range.main_type == content_main and media_suffix ~= nil and media_suffix == content_suffix then
        return 1
    end

    local media_structured_suffix = media_range.sub_type:match('^.+%+(.+)$')
    if
        media_range.main_type == content_main
        and media_structured_suffix ~= nil
        and media_structured_suffix == content_sub
    then
        return 1
    end

    if media_range.main_type == content_main and media_range.sub_type == '*' then
        return 0
    end

    if media_range.main_type == '*' and media_range.sub_type == '*' then
        return -1
    end

    return nil
end

---@param content_type string?
---@return boolean
function M.content_type_is_json(content_type)
    local normalized_content_type = normalize_media_type(content_type)
    if normalized_content_type == nil then
        return false
    end

    local media_type = vim.trim(normalized_content_type:match('^[^;]+') or '')

    return media_type == 'application/json'
        or media_type == 'application/jsonrpc'
        or media_type:match('^application/.+%+json$') ~= nil
end

local function content_type_preference(accept_header, content_type)
    if accept_header == nil then
        return {
            acceptable = true,
            q = 1,
            specificity = 0,
            position = math.huge,
        }
    end

    if type(accept_header) ~= 'string' then
        return {
            acceptable = false,
        }
    end

    if vim.trim(accept_header) == '' then
        return {
            acceptable = true,
            q = 1,
            specificity = 0,
            position = math.huge,
        }
    end

    local best_q = nil
    local best_specificity = nil
    local best_position = nil
    local blocked_specificity = nil

    local position = 0
    for value in accept_header:gmatch('[^,]+') do
        position = position + 1
        local media_range = parse_media_range(value)
        local specificity = content_type_match_specificity(media_range, content_type)

        if specificity ~= nil then
            if media_range.q == 0 then
                if blocked_specificity == nil or specificity > blocked_specificity then
                    blocked_specificity = specificity
                end
            elseif
                best_specificity == nil
                or specificity > best_specificity
                or (specificity == best_specificity and media_range.q > best_q)
                or (specificity == best_specificity and media_range.q == best_q and position < best_position)
            then
                best_specificity = specificity
                best_q = media_range.q
                best_position = position
            end
        end
    end

    if blocked_specificity ~= nil and best_specificity ~= nil and blocked_specificity == best_specificity then
        return {
            acceptable = false,
        }
    end

    return {
        acceptable = best_q ~= nil,
        q = best_q,
        specificity = best_specificity,
        position = best_position,
    }
end

local function negotiate_response_content_type(accept_header)
    local candidates = {
        { response = 'application/json', aliases = { 'application/*+json', '*/*' } },
    }

    local best_content_type = nil
    local best_q = nil
    local best_specificity = nil
    local best_position = nil

    for _, candidate in ipairs(candidates) do
        local preference = content_type_preference(accept_header, candidate.response)

        if not preference.acceptable then
            preference = nil
        end

        for _, alias in ipairs(candidate.aliases) do
            local alias_preference = content_type_preference(accept_header, alias)

            if
                alias_preference.acceptable
                and (
                    preference == nil
                    or alias_preference.specificity > preference.specificity
                    or (alias_preference.specificity == preference.specificity and alias_preference.q > preference.q)
                    or (
                        alias_preference.specificity == preference.specificity
                        and alias_preference.q == preference.q
                        and alias_preference.position < preference.position
                    )
                )
            then
                preference = alias_preference
            end
        end

        if
            preference ~= nil
            and preference.acceptable
            and (
                best_content_type == nil
                or preference.specificity > best_specificity
                or (preference.specificity == best_specificity and preference.q > best_q)
                or (
                    preference.specificity == best_specificity
                    and preference.q == best_q
                    and preference.position < best_position
                )
            )
        then
            best_content_type = candidate.response
            best_q = preference.q
            best_specificity = preference.specificity
            best_position = preference.position
        end
    end

    return best_content_type
end

---@param accept_header any
---@param content_type string
---@return boolean
function M.accepts_content_type(accept_header, content_type)
    return content_type_preference(accept_header, content_type).acceptable
end

---@param accept_header any
---@return string?
function M.negotiate_response_content_type(accept_header)
    return negotiate_response_content_type(accept_header)
end

return M
