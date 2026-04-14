local M = {}
local list_attachments = require('ministry.resources.list_providers')

---@param bufnr integer
---@return table
local function buffer_context(bufnr)
    local loaded = vim.api.nvim_buf_is_loaded(bufnr)

    return {
        bufnr = bufnr,
        name = vim.api.nvim_buf_get_name(bufnr),
        lines = loaded and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or {},
        filetype = loaded and vim.bo[bufnr].filetype or '',
        modified = loaded and vim.bo[bufnr].modified or false,
        listed = loaded and vim.bo[bufnr].buflisted or vim.fn.buflisted(bufnr) == 1,
        loaded = loaded,
    }
end

---@return table
function M.current_buffer()
    return buffer_context(vim.api.nvim_get_current_buf())
end

---@param bufnr integer
---@return table|nil, table|nil
function M.by_id(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return nil,
            {
                code = -32000,
                message = string.format('Invalid buffer id: %s', tostring(bufnr)),
            }
    end

    return buffer_context(bufnr), nil
end

---@return table[]
function M.list_buffers()
    local items = {}

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            table.insert(items, list_attachments.apply('buffers', bufnr, buffer_context(bufnr)))
        end
    end

    table.sort(items, function(left, right)
        return left.bufnr < right.bufnr
    end)

    return items
end

---@return table
local function buffer_counts()
    local valid = 0
    local listed = 0

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            valid = valid + 1

            if vim.fn.buflisted(bufnr) == 1 then
                listed = listed + 1
            end
        end
    end

    return {
        valid = valid,
        listed = listed,
    }
end

---@return table
function M.workspace_summary()
    local current_bufnr = vim.api.nvim_get_current_buf()

    return {
        cwd = vim.fn.getcwd(-1, -1),
        current_buffer = {
            bufnr = current_bufnr,
            name = vim.api.nvim_buf_get_name(current_bufnr),
            filetype = vim.bo[current_bufnr].filetype,
            modified = vim.bo[current_bufnr].modified,
            listed = vim.fn.buflisted(current_bufnr) == 1,
            loaded = vim.api.nvim_buf_is_loaded(current_bufnr),
        },
        tabpages = #vim.api.nvim_list_tabpages(),
        windows = #vim.api.nvim_list_wins(),
        buffer_counts = buffer_counts(),
    }
end

return M
