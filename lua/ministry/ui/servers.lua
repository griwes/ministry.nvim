local approval = require('ministry.approval.policy')

local M = {}

---@class ministry.ServerUiTarget
---@field server string
---@field method? string

---@param value any
---@return string
local function display(value)
    if value == nil then
        return '-'
    end
    if type(value) == 'table' then
        return table.concat(value, ' ')
    end
    return tostring(value)
end

---@param status ministry.ServerStatus
---@return string
local function status_line(status)
    local policy = status.policy or {}
    local source = status.source or {}
    local endpoint = status.url or status.command or '-'
    return table.concat({
        status.name,
        string.format('source=%s:%s', source.kind or '-', source.path or source.name or '-'),
        string.format('transport=%s', status.transport or '-'),
        string.format('endpoint=%s', endpoint),
        string.format('state=%s', status.state or '-'),
        string.format('default=%s', policy.default or '-'),
        string.format('allow=%s', policy.allow or 0),
        string.format('reject=%s', policy.reject or 0),
        string.format('ask=%s', policy.ask or 0),
    }, '  ')
end

---@param status ministry.ServerStatus
---@return string[]
local function method_names(status)
    local by_name = {}
    if status.transport == 'stdio' then
        by_name.__activate = true
    end

    for name in pairs((status.policy or {}).tools or {}) do
        by_name[name] = true
    end

    for _, tool in ipairs(status.tools or {}) do
        if type(tool) == 'table' and type(tool.name) == 'string' and tool.name ~= '' then
            by_name[tool.name] = true
        end
    end

    local names = {}
    for name in pairs(by_name) do
        table.insert(names, name)
    end
    table.sort(names, function(left, right)
        if left == '__activate' then
            return true
        end
        if right == '__activate' then
            return false
        end
        return left < right
    end)
    return names
end

---@param status ministry.ServerStatus
---@param method string
---@return string
local function method_line(status, method)
    local policy = status.policy or {}
    local tools = policy.tools or {}
    local decision = tools[method] or policy.default or '-'
    local suffix = tools[method] == nil and policy.default ~= nil and ' inherited' or ''
    return string.format('  method=%s  policy=%s%s', method, decision, suffix)
end

---@param statuses ministry.ServerStatus[]
---@return string[]
function M.render_lines(statuses)
    local lines = {
        'Ministry MCP servers',
        '',
        'Press a/r/k on a server or method line to set allow/reject/ask.',
        '',
    }

    for _, status in ipairs(statuses) do
        table.insert(lines, status_line(status))
        if status.args ~= nil and #status.args > 0 then
            table.insert(lines, string.format('  args=%s', display(status.args)))
        end
        if status.error ~= nil and status.error ~= '' then
            table.insert(lines, string.format('  error=%s', status.error))
        end
        for _, method in ipairs(method_names(status)) do
            table.insert(lines, method_line(status, method))
        end
    end

    return lines
end

---@param statuses ministry.ServerStatus[]
---@param line integer
---@return ministry.ServerUiTarget?
local function target_at_line(statuses, line)
    local row = 5
    for _, status in ipairs(statuses) do
        if line == row then
            return { server = status.name }
        end
        row = row + 1
        if status.args ~= nil and #status.args > 0 then
            row = row + 1
        end
        if status.error ~= nil and status.error ~= '' then
            row = row + 1
        end
        for _, method in ipairs(method_names(status)) do
            if line == row then
                return { server = status.name, method = method }
            end
            row = row + 1
        end
    end
    return nil
end

---@param statuses ministry.ServerStatus[]
local function open_buffer(statuses)
    local current_statuses = statuses
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'ministry-servers'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.render_lines(current_statuses))
    vim.api.nvim_set_current_buf(buf)

    local function set_policy(decision)
        local row = vim.api.nvim_win_get_cursor(0)[1]
        local target = target_at_line(current_statuses, row)
        if target == nil then
            return
        end
        approval.set(target.server, target.method, decision)
        current_statuses = require('ministry').list_server_statuses()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.render_lines(current_statuses))
    end

    vim.keymap.set('n', 'a', function()
        set_policy('allow')
    end, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'r', function()
        set_policy('reject')
    end, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'k', function()
        set_policy('ask')
    end, { buffer = buf, nowait = true })
end

---@param statuses ministry.ServerStatus[]
function M.open(statuses)
    open_buffer(statuses)
end

M._target_at_line = target_at_line

return M
