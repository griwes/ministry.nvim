local M = {}

local editor_io = require('ministry.builtin.editor.io')
local list_attachments = require('ministry.resources.list_providers')

---@type table<string, { proc: vim.SystemObj, command: string[], cwd: string|nil, stdout_chunks: string[], stderr_chunks: string[], completed: table|nil }>
local terminals = {}

---@param terminal_id string
---@param terminal { command: string[], cwd: string|nil, completed: table|nil }
---@return table
local function terminal_summary(terminal_id, terminal)
    return list_attachments.apply('terminals', terminal_id, {
        terminal_id = terminal_id,
        command = vim.deepcopy(terminal.command),
        cwd = terminal.cwd,
        completed = terminal.completed ~= nil,
    })
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
    terminal.completed = completed
end

---@param terminal table
---@return table
local function wait_for_completion(terminal)
    if terminal.completed ~= nil then
        return terminal.completed
    end

    if vim.in_fast_event() then
        return nil,
            {
                code = -32000,
                message = 'terminal wait is not available during fast events',
            }
    end

    local completed = terminal.proc:wait()
    if completed == nil then
        return nil,
            {
                code = -32000,
                message = 'terminal wait failed to produce a completion result',
            }
    end

    terminal.completed = completed

    append_output_if_missing(terminal.stdout_chunks, completed.stdout)
    append_output_if_missing(terminal.stderr_chunks, completed.stderr)

    return completed
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
                message = terminal.completed.stderr or terminal.completed.stdout or 'failed to start terminal command',
            }
    end

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
        completed = terminal.completed ~= nil,
    },
        nil
end

---@param terminal_id string
---@return table|nil, table|nil
function M.wait(terminal_id)
    local terminal = get_terminal(terminal_id)

    if terminal == nil then
        return nil,
            {
                code = -32000,
                message = string.format('Unknown terminal id: %s', terminal_id),
            }
    end

    local completed, wait_err = wait_for_completion(terminal)
    if wait_err ~= nil then
        return nil, wait_err
    end

    terminal.completed = completed

    local exit_code = completed.code

    if exit_code == nil and completed.signal ~= nil then
        exit_code = 128 + completed.signal
    end

    return {
        terminal_id = terminal_id,
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
end

return M
