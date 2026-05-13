local M = {}

local config = require('ministry.core.config')
local editor_io = require('ministry.builtin.editor.io')
local lifecycle = require('ministry.builtin.terminal_lifecycle')
local list_attachments = require('ministry.resources.list_providers')

---@type table<string, { proc: vim.SystemObj, command: string[], cwd: string|nil, stdout_chunks: string[], stderr_chunks: string[], completed: table|nil }>
local terminals = {}

---@param terminal_id string
---@param terminal { command: string[], cwd: string|nil, completed: table|nil }
---@return table
local function terminal_data(terminal_id, terminal)
    return {
        terminal_id = terminal_id,
        command = vim.deepcopy(terminal.command),
        cwd = terminal.cwd,
        completed = terminal.completed ~= nil,
    }
end

---@param terminal_id string
---@param terminal { command: string[], cwd: string|nil, completed: table|nil }
---@return table
local function terminal_summary(terminal_id, terminal)
    return list_attachments.apply('terminals', terminal_id, terminal_data(terminal_id, terminal))
end

local function next_id()
    return string.format('term-%d-%d', vim.fn.getpid(), vim.loop.hrtime())
end

---@param chunks string[]
---@return string
local function join_chunks(chunks)
    return table.concat(chunks, '')
end

---@param chunks string[]
---@return boolean
local function bound_chunks(chunks)
    local output = join_chunks(chunks)
    local max_bytes = math.max(1, tonumber(config.get().terminal.max_output_bytes) or 1024 * 1024)
    if #output <= max_bytes then
        return false
    end

    chunks[1] = output:sub(#output - max_bytes + 1)
    for index = #chunks, 2, -1 do
        chunks[index] = nil
    end
    return true
end

---@param terminal table
---@param stream 'stdout'|'stderr'
---@param output string|nil
local function append_stream_output(terminal, stream, output)
    if output == nil or output == '' then
        return
    end

    local chunks = terminal[stream .. '_chunks']
    table.insert(chunks, output)
    if bound_chunks(chunks) then
        terminal[stream .. '_truncated'] = true
    end
end

---@param chunks string[]
---@param output string|nil
local function append_output_if_missing(chunks, output)
    if output == nil or output == '' then
        return
    end

    if #chunks == 0 then
        chunks[1] = output
        return
    end

    local existing = join_chunks(chunks)
    if existing == output then
        return
    end

    local common_length = 0
    local max_common = math.min(#existing, #output)
    while
        common_length < max_common
        and existing:sub(common_length + 1, common_length + 1) == output:sub(common_length + 1, common_length + 1)
    do
        common_length = common_length + 1
    end

    if common_length == #existing then
        chunks[#chunks + 1] = output:sub(common_length + 1)
        return
    end

    chunks[1] = output
    for i = #chunks, 2, -1 do
        chunks[i] = nil
    end
end

---@param completed table|nil
---@return boolean
local function completed_with_failure(completed)
    if completed == nil then
        return false
    end

    if completed.code ~= nil then
        return completed.code ~= 0
    end

    return completed.signal ~= nil and completed.signal ~= 0
end

---@param terminal table
---@param completed table|nil
local function apply_completion(terminal, completed)
    if completed == nil then
        return
    end

    append_output_if_missing(terminal.stdout_chunks, completed.stdout)
    append_output_if_missing(terminal.stderr_chunks, completed.stderr)
    if bound_chunks(terminal.stdout_chunks) then
        terminal.stdout_truncated = true
    end
    if bound_chunks(terminal.stderr_chunks) then
        terminal.stderr_truncated = true
    end
    terminal.completed = completed
end

---@param terminal table
---@param timeout_ms integer
---@return table|nil, table|nil
local function wait_for_completion(terminal, timeout_ms)
    if terminal.completed ~= nil then
        return terminal.completed
    end

    if vim.in_fast_event() then
        return nil, nil
    end

    vim.wait(timeout_ms, function()
        return terminal.completed ~= nil
    end, 10)

    return terminal.completed, nil
end

---@param terminal table
local function stop_process(terminal)
    if terminal.completed ~= nil then
        return
    end

    pcall(terminal.proc.kill, terminal.proc, 15)
    local completed = terminal.proc:wait(1000)

    if completed == nil then
        pcall(terminal.proc.kill, terminal.proc, 9)
        completed = terminal.proc:wait(1000)
    end

    terminal.completed = completed or {
        code = 143,
        signal = 15,
    }

    if completed ~= nil then
        append_output_if_missing(terminal.stdout_chunks, completed.stdout)
        append_output_if_missing(terminal.stderr_chunks, completed.stderr)
    end
end

---@param command string[]
---@param cwd string|nil
---@return table|nil, table|nil
function M.create(command, cwd)
    local terminal_id = next_id()

    if cwd ~= nil then
        cwd = editor_io.normalize_path(cwd)
    end

    local terminal = {
        proc = nil,
        command = vim.deepcopy(command),
        cwd = cwd,
        stdout_chunks = {},
        stderr_chunks = {},
        stdout_truncated = false,
        stderr_truncated = false,
        completed = nil,
    }

    if cwd ~= nil then
        local stat = vim.uv.fs_stat(cwd)
        if stat == nil then
            return nil,
                {
                    code = -32602,
                    message = 'Invalid arguments: cwd does not exist',
                }
        end

        if stat.type ~= 'directory' then
            return nil,
                {
                    code = -32602,
                    message = 'Invalid arguments: cwd must be a directory',
                }
        end
    end

    terminals[terminal_id] = terminal

    local ok, proc = pcall(vim.system, command, {
        cwd = cwd,
        text = true,
        stdout = function(_, data)
            local current = terminals[terminal_id]
            if current ~= nil then
                append_stream_output(current, 'stdout', data)
            end
        end,
        stderr = function(_, data)
            local current = terminals[terminal_id]
            if current ~= nil then
                append_stream_output(current, 'stderr', data)
            end
        end,
    }, function(obj)
        local current = terminals[terminal_id]
        if current == nil then
            return
        end

        apply_completion(current, obj)
    end)

    if not ok then
        terminals[terminal_id] = nil
        return nil, {
            code = -32000,
            message = tostring(proc),
        }
    end

    terminal.proc = proc

    if completed_with_failure(terminal.completed) then
        terminals[terminal_id] = nil
        return nil,
            {
                code = -32000,
                message = join_chunks(terminal.stderr_chunks) ~= '' and join_chunks(terminal.stderr_chunks)
                    or join_chunks(terminal.stdout_chunks) ~= '' and join_chunks(terminal.stdout_chunks)
                    or 'failed to start terminal command',
            }
    end

    lifecycle.created(terminal_data(terminal_id, terminal))

    return {
        terminal_id = terminal_id,
    }, nil
end

---@param terminal_id string
---@return table?
local function get_terminal(terminal_id)
    return terminals[terminal_id]
end

---@param terminal_id string
---@return table|nil, table|nil
function M.output(terminal_id)
    local terminal = get_terminal(terminal_id)

    if terminal == nil then
        return nil,
            {
                code = -32000,
                message = string.format('Unknown terminal id: %s', terminal_id),
            }
    end

    return {
        terminal_id = terminal_id,
        stdout = join_chunks(terminal.stdout_chunks),
        stderr = join_chunks(terminal.stderr_chunks),
        stdout_truncated = terminal.stdout_truncated == true,
        stderr_truncated = terminal.stderr_truncated == true,
        completed = terminal.completed ~= nil,
    },
        nil
end

---@param terminal_id string
---@param timeout_ms? integer
---@return table|nil, table|nil
function M.wait(terminal_id, timeout_ms)
    local terminal = get_terminal(terminal_id)

    if terminal == nil then
        return nil,
            {
                code = -32000,
                message = string.format('Unknown terminal id: %s', terminal_id),
            }
    end

    local applied = config.get().terminal
    local default_timeout = tonumber(applied.wait_timeout_ms) or 100
    local max_timeout = math.max(0, tonumber(applied.max_wait_timeout_ms) or 1000)
    local bounded_timeout = tonumber(timeout_ms == nil and default_timeout or timeout_ms) or default_timeout
    bounded_timeout = math.max(0, math.min(bounded_timeout, max_timeout))
    local completed, wait_err = wait_for_completion(terminal, bounded_timeout)
    if wait_err ~= nil then
        return nil, wait_err
    end

    if completed == nil then
        return {
            terminal_id = terminal_id,
            completed = false,
        }, nil
    end

    terminal.completed = completed

    local exit_code = completed.code

    if exit_code == nil and completed.signal ~= nil then
        exit_code = 128 + completed.signal
    end

    return {
        terminal_id = terminal_id,
        completed = true,
        exit_code = exit_code,
        signal = completed.signal,
    },
        nil
end

---@param terminal_id string
---@return table|nil, table|nil
function M.release(terminal_id)
    local terminal = get_terminal(terminal_id)

    if terminal == nil then
        return nil,
            {
                code = -32000,
                message = string.format('Unknown terminal id: %s', terminal_id),
            }
    end

    stop_process(terminal)
    terminals[terminal_id] = nil
    lifecycle.released(terminal_data(terminal_id, terminal))

    return {
        terminal_id = terminal_id,
        released = true,
    }, nil
end

---@return table[]
function M.list()
    local items = {}

    for terminal_id, terminal in pairs(terminals) do
        table.insert(items, terminal_summary(terminal_id, terminal))
    end

    table.sort(items, function(left, right)
        return left.terminal_id < right.terminal_id
    end)

    return items
end

function M.reset()
    for _, terminal in pairs(terminals) do
        stop_process(terminal)
    end

    terminals = {}
    list_attachments.reset()
    lifecycle.reset()
end

return M
