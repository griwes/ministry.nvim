local M = {}

---@param path string
---@return string
function M.normalize_path(path)
    return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

---@param path string
---@return integer?
function M.find_buffer(path)
    local target = M.normalize_path(path)

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            local name = vim.api.nvim_buf_get_name(bufnr)

            if name ~= '' and M.normalize_path(name) == target then
                return bufnr
            end
        end
    end

    return nil
end

---@param path string
---@return integer|nil, table|nil
function M.ensure_buffer(path)
    local normalized = M.normalize_path(path)
    local bufnr = M.find_buffer(normalized)

    if bufnr == nil then
        bufnr = vim.fn.bufadd(normalized)

        if bufnr == 0 then
            return nil,
                {
                    code = -32000,
                    message = string.format('Failed to create buffer for path: %s', normalized),
                }
        end
    end

    if not vim.api.nvim_buf_is_loaded(bufnr) then
        local ok, load_err = pcall(vim.fn.bufload, bufnr)

        if not ok then
            return nil,
                {
                    code = -32000,
                    message = string.format('Failed to load buffer %d: %s', bufnr, tostring(load_err)),
                }
        end
    end

    return bufnr, nil
end

---@param content string
---@return string[]
function M.decode_content(content)
    if content == '' then
        return {}
    end

    local lines = vim.split(content, '\n', {
        plain = true,
    })

    if content:sub(-1) == '\n' then
        table.remove(lines, #lines)
    end

    if #lines == 0 then
        return {}
    end

    return lines
end

---@param bufnr integer
---@param content any
---@return table|nil, table|nil
function M.write_buffer(bufnr, content)
    if type(content) ~= 'string' then
        return nil,
            {
                code = -32602,
                message = 'Invalid arguments: content must be a string',
            }
    end

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

    local lines = M.decode_content(content)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    return {
        bufnr = bufnr,
        path = vim.api.nvim_buf_get_name(bufnr),
        line_count = #lines,
        modified = vim.bo[bufnr].modified,
    },
        nil
end

---@param path any
---@param content any
---@return table|nil result, table|nil err, table|nil warning
function M.write_file(path, content)
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

    local normalized = M.normalize_path(path)
    local bufnr, ensure_err = M.ensure_buffer(normalized)

    if ensure_err ~= nil then
        return nil, ensure_err
    end

    local result, err = M.write_buffer(bufnr, content)

    if err ~= nil then
        return nil, err
    end

    result.path = normalized
    result.reloaded_buffer = false
    result.updated_buffer = bufnr
    return result, nil, nil
end

return M
