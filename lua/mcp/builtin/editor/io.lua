local M = {}

---@param path string
---@return string
function M.normalize_path(path)
    return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

---@param path string
---@return integer?
function M.find_loaded_buffer(path)
    local target = M.normalize_path(path)

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
            local name = vim.api.nvim_buf_get_name(bufnr)

            if name ~= '' and M.normalize_path(name) == target then
                return bufnr
            end
        end
    end

    return nil
end

---@param bufnr integer
---@return boolean
function M.is_modifiable_buffer(bufnr)
    return vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modifiable
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

---@param path string
---@param content string
---@return table|nil
function M.write_disk(path, content)
    local parent = vim.fn.fnamemodify(path, ':h')

    if parent ~= '' then
        local ok = vim.fn.mkdir(parent, 'p')

        if ok == 0 and vim.fn.isdirectory(parent) == 0 then
            return {
                code = -32000,
                message = string.format('Failed to create parent directory: %s', parent),
            }
        end
    end

    local handle, open_error = io.open(path, 'wb')

    if handle == nil then
        return {
            code = -32000,
            message = open_error or string.format('Failed to write file: %s', path),
        }
    end

    local ok, write_error = handle:write(content)
    handle:close()

    if not ok then
        return {
            code = -32000,
            message = write_error or string.format('Failed to write file: %s', path),
        }
    end

    return nil
end

---@param path string
---@return file*|nil, string?
function M.open_read(path)
    local handle, open_error = io.open(path, 'rb')

    if handle == nil then
        return nil, open_error
    end

    return handle, nil
end

---@param path string
---@return boolean
function M.path_exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

---@param bufnr integer
---@return table|nil
function M.reload_buffer(bufnr)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        return nil
    end

    local function run_checktime_in_window(winid)
        local current_buf = vim.api.nvim_win_get_buf(winid)
        local original_tab = vim.api.nvim_get_current_tabpage()
        local original_win = vim.api.nvim_get_current_win()
        local original_view = vim.fn.winsaveview()
        local reload_ok, reload_err = xpcall(function()
            vim.api.nvim_win_call(winid, function()
                local ok_set_buf, set_buf_err = pcall(vim.api.nvim_win_set_buf, 0, bufnr)
                if not ok_set_buf then
                    error(set_buf_err)
                end

                local ok_checktime, checktime_err = pcall(vim.cmd, 'silent checktime')
                if not ok_checktime then
                    error(checktime_err)
                end

                local ok_restore_buf, restore_buf_err = pcall(vim.api.nvim_win_set_buf, 0, current_buf)
                if not ok_restore_buf then
                    error(restore_buf_err)
                end
            end)
        end, debug.traceback)

        if vim.api.nvim_tabpage_is_valid(original_tab) then
            vim.api.nvim_set_current_tabpage(original_tab)
        end
        if vim.api.nvim_win_is_valid(original_win) then
            vim.api.nvim_set_current_win(original_win)
            vim.fn.winrestview(original_view)
        end
        if not reload_ok then
            error(reload_err)
        end
    end

    local ok, reload_error = pcall(function()
        vim.api.nvim_buf_call(bufnr, function()
            local windows = vim.fn.win_findbuf(bufnr)

            if #windows == 0 then
                local fallback_win

                for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
                    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
                        local config = vim.api.nvim_win_get_config(winid)
                        if config.relative == '' and vim.fn.getwinvar(winid, '&buftype') ~= 'nofile' then
                            fallback_win = winid
                            break
                        end
                    end

                    if fallback_win then
                        break
                    end
                end

                if fallback_win then
                    run_checktime_in_window(fallback_win)
                else
                    local temp_buf = vim.api.nvim_create_buf(false, true)
                    local temp_win
                    local ok_open, open_err = pcall(vim.api.nvim_open_win, temp_buf, false, {
                        relative = 'editor',
                        row = 0,
                        col = 0,
                        width = 1,
                        height = 1,
                        style = 'minimal',
                        focusable = false,
                        noautocmd = true,
                    })

                    if ok_open then
                        temp_win = open_err
                    else
                        if vim.api.nvim_buf_is_valid(temp_buf) then
                            vim.api.nvim_buf_delete(temp_buf, { force = true })
                        end
                        error('failed to create temporary reload window: ' .. tostring(open_err))
                    end

                    local ok_reload, reload_err_inner = xpcall(function()
                        run_checktime_in_window(temp_win)
                    end, debug.traceback)
                    if vim.api.nvim_win_is_valid(temp_win) then
                        vim.api.nvim_win_close(temp_win, true)
                    end
                    if vim.api.nvim_buf_is_valid(temp_buf) then
                        vim.api.nvim_buf_delete(temp_buf, { force = true })
                    end
                    if not ok_reload then
                        error(reload_err_inner)
                    end
                end

                return
            end

            for _, winid in ipairs(windows) do
                vim.api.nvim_win_call(winid, function()
                    vim.cmd('silent checktime')
                end)
            end
        end)
    end)

    if not ok then
        return {
            code = -32000,
            message = tostring(reload_error),
        }
    end

    return nil
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

    local diff = require('mcp.builtin.editor.diff')
    local result, err = diff.apply_buffer(bufnr, content)

    if err ~= nil then
        return nil, err
    end

    local lines = M.decode_content(content)

    return {
        bufnr = bufnr,
        path = vim.api.nvim_buf_get_name(bufnr),
        line_count = #lines,
        modified = result.modified,
    },
        nil
end

---@param content any
---@return table|nil, table|nil
function M.write_current_buffer(content)
    return M.write_buffer(vim.api.nvim_get_current_buf(), content)
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
    local bufnr = M.find_loaded_buffer(normalized)

    if bufnr ~= nil and vim.bo[bufnr].modified then
        return nil,
            {
                code = -32000,
                message = string.format('Buffer %d has unsaved changes', bufnr),
            }
    end

    local write_error = M.write_disk(normalized, content)

    if write_error ~= nil then
        return nil, write_error
    end

    local warning = nil

    if bufnr ~= nil then
        warning = M.reload_buffer(bufnr)
    end

    return {
        path = normalized,
        reloaded_buffer = bufnr ~= nil,
    },
        nil,
        warning
end

return M
