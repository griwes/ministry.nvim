local io = require('mcp.builtin.editor.io')

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
        vim.api.nvim_buf_set_lines(
            bufnr,
            hunk.current_start - 1,
            hunk.current_start - 1 + hunk.current_count,
            false,
            hunk.replacement
        )
    end
end

---@param content string
---@return table
function M.current_buffer(content)
    local current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local target_lines = normalized_lines(content)

    return {
        hunks = diff_hunks(current_lines, target_lines),
    }
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
    local handle, open_error = io.open_read(normalized)

    local current_content = ''

    if handle == nil then
        if io.path_exists(normalized) then
            return nil,
                {
                    code = -32000,
                    message = open_error or string.format('Failed to read file: %s', normalized),
                }
        end
    else
        current_content = handle:read('*a')
        handle:close()
    end

    local current_lines = normalized_lines(current_content)
    local target_lines = normalized_lines(content)

    return {
        path = normalized,
        hunks = diff_hunks(current_lines, target_lines),
    }, nil
end

---@param content string
---@return table|nil, table|nil
function M.apply_current_buffer(content)
    local bufnr = vim.api.nvim_get_current_buf()

    if not vim.bo[bufnr].modifiable then
        return nil, {
            code = -32000,
            message = 'Current buffer is not modifiable',
        }
    end

    local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local target_lines = normalized_lines(content)
    local hunks = diff_hunks(current_lines, target_lines)
    apply_hunks_to_buffer(bufnr, hunks)

    return {
        bufnr = bufnr,
        applied_hunk_count = #hunks,
        modified = vim.bo[bufnr].modified,
    },
        nil
end

---@param bufnr integer
---@param content string
---@return table|nil, table|nil
function M.apply_buffer(bufnr, content)
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

    local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local target_lines = normalized_lines(content)
    local hunks = diff_hunks(current_lines, target_lines)
    apply_hunks_to_buffer(bufnr, hunks)

    return {
        bufnr = bufnr,
        applied_hunk_count = #hunks,
        modified = vim.bo[bufnr].modified,
    },
        nil
end

---@param path string
---@param content string
---@return table|nil result, table|nil err, table|nil warning
function M.apply_file(path, content)
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
    local bufnr = io.find_loaded_buffer(normalized)

    if bufnr ~= nil and vim.bo[bufnr].modified then
        return nil,
            {
                code = -32000,
                message = string.format('Buffer %d has unsaved changes', bufnr),
            }
    end

    local write_error = io.write_disk(normalized, content)

    if write_error ~= nil then
        return nil, write_error
    end

    local warning = nil

    if bufnr ~= nil then
        local reload_result = io.reload_buffer(bufnr)

        if reload_result ~= nil and reload_result.code ~= nil and reload_result.message ~= nil then
            warning = reload_result
        end
    end

    return {
        path = normalized,
        reloaded_buffer = bufnr ~= nil,
    },
        nil,
        warning
end

return M
