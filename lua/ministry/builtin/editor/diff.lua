local io = require('ministry.builtin.editor.io')

local M = {}

local function encode_lines(lines)
    if #lines == 0 then
        return ''
    end

    return table.concat(lines, '\n') .. '\n'
end

---@param content string
---@return string[]
local function normalized_lines(content)
    return io.decode_content(content)
end

---@param current_lines string[]
---@param target_lines string[]
---@return table[]
local function diff_hunks(current_lines, target_lines)
    local current_text = encode_lines(current_lines)
    local target_text = encode_lines(target_lines)
    local hunks = vim.diff(current_text, target_text, {
        result_type = 'indices',
        algorithm = 'histogram',
    })
    local items = {}

    for _, hunk in ipairs(hunks) do
        local start_current = hunk[1]
        local count_current = hunk[2]
        local start_target = hunk[3]
        local count_target = hunk[4]
        local replacement = {}

        for index = start_target, start_target + count_target - 1 do
            table.insert(replacement, target_lines[index])
        end

        if count_current == 0 then
            -- vim.diff reports insertions as "after current line N". Exposed
            -- hunks use patch-style "before current line N" semantics instead.
            start_current = start_current + 1
        end

        table.insert(items, {
            current_start = start_current,
            current_count = count_current,
            replacement = replacement,
        })
    end

    return items
end

---@param bufnr integer
---@param hunks table[]
local function apply_hunks_to_buffer(bufnr, hunks)
    for index = #hunks, 1, -1 do
        local hunk = hunks[index]
        local start_index = math.max(hunk.current_start - 1, 0)
        vim.api.nvim_buf_set_lines(bufnr, start_index, start_index + hunk.current_count, false, hunk.replacement)
    end
end

---@param hunks any
---@return table[]|nil, table|nil
local function validate_hunks(hunks)
    if type(hunks) ~= 'table' or vim.islist(hunks) == false then
        return nil,
            {
                code = -32602,
                message = 'Invalid arguments: hunks must be a list',
            }
    end

    local normalized = {}

    for index, hunk in ipairs(hunks) do
        if type(hunk) ~= 'table' then
            return nil,
                {
                    code = -32602,
                    message = string.format('Invalid arguments: hunks[%d] must be an object', index),
                }
        end

        local current_start = hunk.current_start
        local current_count = hunk.current_count
        local replacement = hunk.replacement

        if type(current_start) ~= 'number' or current_start % 1 ~= 0 or current_start < 0 then
            return nil,
                {
                    code = -32602,
                    message = string.format(
                        'Invalid arguments: hunks[%d].current_start must be a non-negative integer',
                        index
                    ),
                }
        end

        if type(current_count) ~= 'number' or current_count % 1 ~= 0 or current_count < 0 then
            return nil,
                {
                    code = -32602,
                    message = string.format(
                        'Invalid arguments: hunks[%d].current_count must be a non-negative integer',
                        index
                    ),
                }
        end

        if type(replacement) ~= 'table' or vim.islist(replacement) == false then
            return nil,
                {
                    code = -32602,
                    message = string.format(
                        'Invalid arguments: hunks[%d].replacement must be a list of strings',
                        index
                    ),
                }
        end

        for line_index, line in ipairs(replacement) do
            if type(line) ~= 'string' then
                return nil,
                    {
                        code = -32602,
                        message = string.format(
                            'Invalid arguments: hunks[%d].replacement[%d] must be a string',
                            index,
                            line_index
                        ),
                    }
            end
        end

        table.insert(normalized, {
            current_start = current_start,
            current_count = current_count,
            replacement = replacement,
        })
    end

    return normalized, nil
end

---@param bufnr integer
---@param content string
---@return table|nil, table|nil
function M.buffer(bufnr, content)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return nil,
            {
                code = -32000,
                message = string.format('Invalid buffer id: %s', tostring(bufnr)),
            }
    end

    local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local target_lines = normalized_lines(content)

    return {
        bufnr = bufnr,
        hunks = diff_hunks(current_lines, target_lines),
    }, nil
end

---@param path string
---@param content string
---@return table|nil, table|nil
function M.file(path, content)
    if type(path) ~= 'string' then
        return nil,
            {
                code = -32602,
                message = 'Invalid arguments: path must be a string',
            }
    end

    if type(content) ~= 'string' then
        return nil,
            {
                code = -32602,
                message = 'Invalid arguments: content must be a string',
            }
    end

    local normalized = io.normalize_path(path)
    local bufnr, ensure_err = io.ensure_buffer(normalized)

    if ensure_err ~= nil then
        return nil, ensure_err
    end

    local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local target_lines = normalized_lines(content)

    return {
        path = normalized,
        bufnr = bufnr,
        hunks = diff_hunks(current_lines, target_lines),
    },
        nil
end

---@param bufnr integer
---@param hunks table[]
---@return table|nil, table|nil
function M.apply_buffer(bufnr, hunks)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return nil,
            {
                code = -32000,
                message = string.format('Invalid buffer id: %s', tostring(bufnr)),
            }
    end

    if not vim.bo[bufnr].modifiable then
        return nil,
            {
                code = -32000,
                message = string.format('Buffer %d is not modifiable', bufnr),
            }
    end

    local normalized_hunks, hunk_err = validate_hunks(hunks)

    if hunk_err ~= nil then
        return nil, hunk_err
    end

    apply_hunks_to_buffer(bufnr, normalized_hunks)

    return {
        bufnr = bufnr,
        applied_hunk_count = #normalized_hunks,
        modified = vim.bo[bufnr].modified,
    },
        nil
end

---@param path string
---@param hunks table[]
---@return table|nil result, table|nil err, table|nil warning
function M.apply_file(path, hunks)
    if type(path) ~= 'string' then
        return nil,
            {
                code = -32602,
                message = 'Invalid arguments: path must be a string',
            }
    end

    local normalized = io.normalize_path(path)
    local bufnr, ensure_err = io.ensure_buffer(normalized)

    if ensure_err ~= nil then
        return nil, ensure_err
    end

    local result, err = M.apply_buffer(bufnr, hunks)

    if err ~= nil then
        return nil, err
    end

    result.path = normalized
    result.reloaded_buffer = false
    result.updated_buffer = bufnr
    return result, nil, nil
end

return M
