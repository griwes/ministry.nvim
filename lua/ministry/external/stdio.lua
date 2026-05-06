local M = {}

---@class ministry.StdioClient
---@field job integer
---@field next_id integer
---@field stdout string
---@field pending table<integer, table>
---@field stderr string[]
---@field exited boolean
---@field exit_code? integer

---@type table<string, ministry.StdioClient>
local clients = {}

local handle_line
local max_stderr_summary = 400

---@param command string
---@return boolean
local function has_path_separator(command)
    return command:find('/', 1, true) ~= nil or command:find('\\', 1, true) ~= nil
end

---@param command string
---@return boolean
local function is_absolute(command)
    return command:sub(1, 1) == '/' or command:match('^%a:[/\\]') ~= nil
end

---@param path string
---@return boolean
local function is_executable(path)
    return vim.fn.executable(path) == 1
end

---@param command string
---@param cwd? string
---@return string?
local function resolve_path_command(command, cwd)
    if is_absolute(command) then
        return is_executable(command) and command or nil
    end

    local base = type(cwd) == 'string' and cwd ~= '' and cwd or vim.fn.getcwd()
    local path = vim.fs.joinpath(base, command)
    return is_executable(path) and path or nil
end

---@param command string
---@param env? table<string, string>
---@return string?
local function resolve_path_search_command(command, env)
    if is_executable(command) then
        return command
    end

    local path = type(env) == 'table' and env.PATH or nil
    path = type(path) == 'string' and path or vim.env.PATH

    for entry in string.gmatch(path or '', '([^:]+)') do
        local candidate = vim.fs.joinpath(entry, command)
        if is_executable(candidate) then
            return candidate
        end
    end

    return nil
end

---@param spec ministry.ExternalServerSpec
---@return string?, table?
local function resolve_command(spec)
    if spec.command == nil or spec.command == '' then
        return nil, {
            code = -32602,
            message = 'stdio MCP server is missing command',
        }
    end

    local command = has_path_separator(spec.command) and resolve_path_command(spec.command, spec.cwd)
        or resolve_path_search_command(spec.command, spec.env)

    if command == nil then
        return nil,
            {
                code = -32000,
                message = string.format('stdio MCP server %s command is not executable: %s', spec.name, spec.command),
            }
    end

    return command, nil
end

---@param data string[]|nil
---@return string[]
local function compact_data(data)
    local chunks = {}
    for _, chunk in ipairs(data or {}) do
        if chunk ~= '' then
            table.insert(chunks, chunk)
        end
    end
    return chunks
end

---@param client ministry.StdioClient
---@return string
local function stderr_summary(client)
    local stderr = table.concat(client.stderr or {}, '\n')
    if stderr == '' then
        return ''
    end
    stderr = vim.trim(stderr)
    if #stderr > max_stderr_summary then
        stderr = stderr:sub(1, max_stderr_summary) .. '...'
    end
    return string.format(': stderr: %s', stderr)
end

---@param client ministry.StdioClient
---@param data string[]|nil
local function handle_stdout(client, data)
    if data == nil or #data == 0 then
        return
    end

    local lines = vim.deepcopy(data)
    lines[1] = client.stdout .. lines[1]
    client.stdout = table.remove(lines) or ''

    for _, line in ipairs(lines) do
        handle_line(client, line)
    end
end

---@param client ministry.StdioClient
---@param line string
function handle_line(client, line)
    if line == '' then
        return
    end

    local ok, message = pcall(vim.json.decode, line)
    if not ok or type(message) ~= 'table' then
        return
    end

    if message.id ~= nil then
        local pending = client.pending[message.id]
        if pending ~= nil then
            pending.response = message
        end
    end
end

---@param spec ministry.ExternalServerSpec
---@return ministry.StdioClient?, table?
function M.start(spec)
    local existing = clients[spec.name]
    if existing ~= nil then
        return existing, nil
    end

    local executable, err = resolve_command(spec)
    if err ~= nil then
        return nil, err
    end

    local command = { executable }
    vim.list_extend(command, spec.args or {})

    local client = {
        job = 0,
        next_id = 1,
        stdout = '',
        pending = {},
        stderr = {},
        exited = false,
    }

    local job = vim.fn.jobstart(command, {
        cwd = spec.cwd,
        env = spec.env,
        stdin = 'pipe',
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = function(_, data)
            handle_stdout(client, data)
        end,
        on_stderr = function(_, data)
            vim.list_extend(client.stderr, compact_data(data))
        end,
        on_exit = function(_, exit_code)
            client.exited = true
            client.exit_code = exit_code
            clients[spec.name] = nil
        end,
    })

    if job <= 0 then
        return nil,
            {
                code = -32000,
                message = string.format('Failed to start stdio MCP server %s', spec.name),
            }
    end

    client.job = job
    clients[spec.name] = client
    return client, nil
end

---@param spec ministry.ExternalServerSpec
---@param payload table
---@param timeout_ms integer
---@return table?, table?
function M.request(spec, payload, timeout_ms)
    local client, start_err = M.start(spec)
    if client == nil then
        return nil, start_err
    end

    local id = client.next_id
    client.next_id = id + 1
    payload.id = id
    payload.jsonrpc = payload.jsonrpc or '2.0'
    client.pending[id] = {}

    vim.fn.chansend(client.job, vim.json.encode(payload) .. '\n')

    local function has_response()
        return client.pending[id] ~= nil and client.pending[id].response ~= nil
    end

    local ok = vim.wait(timeout_ms, function()
        return client.exited or has_response()
    end, 10)

    if not ok then
        client.pending[id] = nil
        return nil,
            {
                code = -32000,
                message = string.format(
                    'Timed out waiting for stdio MCP server %s%s',
                    spec.name,
                    stderr_summary(client)
                ),
            }
    end

    if client.exited and not has_response() then
        vim.wait(50, has_response, 1)
    end

    local pending = client.pending[id]
    local response = pending ~= nil and pending.response or nil
    client.pending[id] = nil

    if response == nil then
        if client.exited then
            return nil,
                {
                    code = -32000,
                    message = string.format(
                        'stdio MCP server %s exited before responding%s%s',
                        spec.name,
                        client.exit_code ~= nil and string.format(' with code %s', client.exit_code) or '',
                        stderr_summary(client)
                    ),
                }
        end
        return nil,
            {
                code = -32000,
                message = string.format('Missing response from stdio MCP server %s', spec.name),
            }
    end

    return response, nil
end

---@param spec ministry.ExternalServerSpec
function M.notify_initialized(spec)
    local client = clients[spec.name]
    if client == nil then
        return
    end

    vim.fn.chansend(client.job, vim.json.encode({
        jsonrpc = '2.0',
        method = 'notifications/initialized',
    }) .. '\n')
end

---@param name string
function M.stop(name)
    local client = clients[name]
    if client == nil then
        return
    end

    clients[name] = nil
    if client.job > 0 then
        vim.fn.jobstop(client.job)
    end
end

function M.stop_all()
    for _, client in pairs(clients) do
        if client.job > 0 then
            vim.fn.jobstop(client.job)
        end
    end
    clients = {}
end

---@param name string
---@return boolean
function M._running(name)
    return clients[name] ~= nil
end

return M
