local M = {}

---@param bufnr integer
---@return table
local function buffer_context(bufnr)
    return {
        bufnr = bufnr,
        name = vim.api.nvim_buf_get_name(bufnr),
        lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
        filetype = vim.bo[bufnr].filetype,
        modified = vim.bo[bufnr].modified,
        listed = vim.bo[bufnr].buflisted,
        loaded = vim.api.nvim_buf_is_loaded(bufnr),
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
            table.insert(items, buffer_context(bufnr))
        end
    end

    table.sort(items, function(left, right)
        return left.bufnr < right.bufnr
    end)

    return items
end

return M
