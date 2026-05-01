local approval = require('ministry.approval.policy')
local config = require('ministry.core.config')
local discovery = require('ministry.sources.files')
local http = require('ministry.external.http')
local registry = require('ministry.core.registry')
local stdio = require('ministry.external.stdio')

local M = {}

---@class ministry.ExternalRuntime
---@field spec ministry.ExternalServerSpec
---@field state string
---@field error? string
---@field initialized boolean
---@field tools table[]
---@field session_id? string

---@type table<string, ministry.ExternalRuntime>
local runtimes = {}

local next_http_id = 1
local initialize

---@param spec ministry.ExternalServerSpec
---@return ministry.ExternalRuntime
local function ensure_runtime(spec)
    local runtime = runtimes[spec.name]
    if runtime == nil then
        runtime = {
            spec = vim.deepcopy(spec),
            state = 'configured',
            initialized = false,
            tools = {},
        }
        runtimes[spec.name] = runtime
    else
        runtime.spec = vim.deepcopy(spec)
    end
    return runtime
end

---@param runtime ministry.ExternalRuntime
---@param message string
local function fail_runtime(runtime, message)
    runtime.state = 'error'
    runtime.error = message
end

---@param name string
local function unregister_external_server(name)
    registry.unregister_server(name)
    stdio.stop(name)
end

---@param opts? { cwd?: string }
---@return { cwd?: string }?
local function discovery_opts(opts)
    if opts == nil or opts.cwd == nil then
        return nil
    end

    return { cwd = opts.cwd }
end

---@param runtime ministry.ExternalRuntime
---@param method string
---@param params table
---@param opts? { notification?: boolean }
---@return table?, table?
local function request_once(runtime, method, params, opts)
    local timeout = config.get().external.request_timeout_ms or 60000
    local spec = runtime.spec
    local payload = {
        jsonrpc = '2.0',
        method = method,
        params = params or {},
    }

    if spec.transport == 'http' then
        local expected_id = nil
        if not (opts ~= nil and opts.notification) then
            payload.id = next_http_id
            expected_id = next_http_id
            next_http_id = next_http_id + 1
        end
        local response, err, meta = http.request(spec, payload, timeout, {
            allow_empty_response = opts ~= nil and opts.notification or false,
            expected_id = expected_id,
            session_id = runtime.session_id,
        })
        if meta ~= nil and meta.session_id ~= nil and meta.session_id ~= '' then
            runtime.session_id = meta.session_id
        end
        return response, err
    end

    if opts ~= nil and opts.notification then
        return {}, nil
    end
    return stdio.request(spec, payload, timeout)
end

---@param runtime ministry.ExternalRuntime
---@param method string
---@param params table
---@param opts? { notification?: boolean }
---@return table?, table?
local function request(runtime, method, params, opts)
    local response, err = request_once(runtime, method, params, opts)
    if
        err ~= nil
        and err.http_status == 404
        and runtime.session_id ~= nil
        and method ~= 'initialize'
        and not (opts ~= nil and opts.notification)
    then
        runtime.session_id = nil
        runtime.initialized = false
        local _, init_err = initialize(runtime)
        if init_err ~= nil then
            return nil, init_err
        end
        return request_once(runtime, method, params, opts)
    end

    return response, err
end

---@param runtime ministry.ExternalRuntime
---@return table?, table?
function initialize(runtime)
    local response, err = request(runtime, 'initialize', {
        protocolVersion = '2025-06-18',
        capabilities = {},
        clientInfo = {
            name = 'ministry.nvim',
            version = '0.1.0',
        },
    })

    if err ~= nil then
        return nil, err
    end
    if response.error ~= nil then
        return nil, response.error
    end

    if runtime.spec.transport == 'stdio' then
        stdio.notify_initialized(runtime.spec)
    else
        request(runtime, 'notifications/initialized', {}, { notification = true })
    end

    return response.result or {}, nil
end

---@param runtime ministry.ExternalRuntime
---@return boolean, table?
local function approve_activation(runtime)
    if runtime.spec.transport ~= 'stdio' then
        return true, nil
    end

    return approval.check({
        server = runtime.spec.name,
        method = '__activate',
        namespaced_name = runtime.spec.name .. '/__activate',
        arguments = {
            command = runtime.spec.command,
            args = runtime.spec.args or {},
            cwd = runtime.spec.cwd,
            source = runtime.spec.source,
        },
        context = {},
    }, { ignore_enabled = true })
end

---@param tool table
---@return ministry.ToolSpec
local function proxy_tool(runtime, tool)
    local name = tool.name
    return {
        name = name,
        description = tool.description,
        input_schema = tool.inputSchema or tool.input_schema,
        ministry_source = runtime.spec.source,
        handler = function(arguments)
            local response, err = request(runtime, 'tools/call', {
                name = name,
                arguments = arguments or {},
            })

            if err ~= nil then
                return nil, err
            end
            if response.error ~= nil then
                return nil, response.error
            end

            return response.result or {}, nil
        end,
    }
end

---@param runtime ministry.ExternalRuntime
local function register_runtime(runtime)
    local tools = {}
    for _, tool in ipairs(runtime.tools) do
        if type(tool) == 'table' and type(tool.name) == 'string' and tool.name ~= '' then
            table.insert(tools, proxy_tool(runtime, tool))
        end
    end

    registry.register_server({
        name = runtime.spec.name,
        title = runtime.spec.name,
        description = string.format(
            'External MCP server from %s',
            runtime.spec.source.path or runtime.spec.source.name or 'config'
        ),
        ministry_source = runtime.spec.source,
        tools = tools,
    })
end

---@param spec ministry.ExternalServerSpec
---@return boolean, table?
function M.refresh_server(spec)
    local runtime = ensure_runtime(spec)
    runtime.state = 'connecting'
    runtime.error = nil
    runtime.tools = {}
    runtime.session_id = nil
    unregister_external_server(spec.name)

    local approved, approval_err = approve_activation(runtime)
    if not approved then
        fail_runtime(runtime, approval_err.message or 'external server activation was not approved')
        return false, approval_err
    end

    local _, init_err = initialize(runtime)
    if init_err ~= nil then
        fail_runtime(runtime, init_err.message or tostring(init_err))
        return false, init_err
    end

    runtime.initialized = true
    local response, list_err = request(runtime, 'tools/list', {})
    if list_err ~= nil then
        fail_runtime(runtime, list_err.message or tostring(list_err))
        return false, list_err
    end
    if response.error ~= nil then
        fail_runtime(runtime, response.error.message or tostring(response.error))
        return false, response.error
    end

    runtime.tools = type(response.result) == 'table' and response.result.tools or {}
    runtime.state = 'ready'
    register_runtime(runtime)
    return true, nil
end

---@param opts? { specs?: ministry.ExternalServerSpec[], cwd?: string }
---@return ministry.ExternalRuntime[], table[]
function M.refresh(opts)
    local applied = config.get().external
    local specs = opts ~= nil and opts.specs or nil
    local errors = {}

    if not applied.enabled and specs == nil then
        return {}, errors
    end

    if specs == nil then
        specs, errors = discovery.discover(discovery_opts(opts))
    end

    local seen = {}
    for _, spec in ipairs(specs or {}) do
        seen[spec.name] = true
        local ok, err = M.refresh_server(spec)
        if not ok and err ~= nil then
            table.insert(errors, {
                server = spec.name,
                message = err.message or tostring(err),
            })
        end
    end

    for name, runtime in pairs(runtimes) do
        if not seen[name] then
            unregister_external_server(name)
            runtimes[name] = nil
        else
            ensure_runtime(runtime.spec)
        end
    end

    return M.list_runtimes(), errors
end

---@param opts? { specs?: ministry.ExternalServerSpec[], cwd?: string }
---@return ministry.ExternalRuntime[], table[]
function M.discover(opts)
    local specs = opts ~= nil and opts.specs or nil
    local errors = {}

    if specs == nil then
        specs, errors = discovery.discover(discovery_opts(opts))
    end

    for _, spec in ipairs(specs or {}) do
        ensure_runtime(spec)
    end

    return M.list_runtimes(), errors
end

---@return ministry.ExternalRuntime[]
function M.list_runtimes()
    local items = {}
    for _, runtime in pairs(runtimes) do
        table.insert(items, vim.deepcopy(runtime))
    end
    table.sort(items, function(left, right)
        return left.spec.name < right.spec.name
    end)
    return items
end

---@param server string
---@return ministry.ExternalRuntime?
function M.get(server)
    local runtime = runtimes[server]
    return runtime ~= nil and vim.deepcopy(runtime) or nil
end

---@param specs ministry.ExternalServerSpec[]
function M.configure(specs)
    for _, spec in ipairs(specs) do
        ensure_runtime(spec)
    end
end

function M.reset()
    stdio.stop_all()
    for name in pairs(runtimes) do
        registry.unregister_server(name)
    end
    runtimes = {}
    next_http_id = 1
end

return M
