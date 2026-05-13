local config = require('ministry.core.config')

local M = {}
local CURRENT_VERSION = 1

---@class ministry.ApprovalStore
---@field servers table<string, { default?: ministry.ApprovalDecision, tools?: table<string, ministry.ApprovalDecision> }>

---@type ministry.ApprovalStore
local store = {
    servers = {},
}

---@class ministry.PendingApproval
---@field server string
---@field method string
---@field namespaced_name string
---@field arguments table
---@field tool_call_id? string
---@field logical_session_id? string
---@field transport_session_id? string
---@field expires_at_ms number

---@type ministry.PendingApproval[]
local pending_approvals = {}

---@type string?
local loaded_path = nil

---@return number
local function now_ms()
    return vim.uv.hrtime() / 1000000
end

---@param decision any
---@return boolean
local function valid_decision(decision)
    return decision == 'allow' or decision == 'reject' or decision == 'ask'
end

---@return string
local function default_path()
    return vim.fs.joinpath(vim.fn.stdpath('state'), 'ministry', 'approvals.json')
end

---@return string
local function policy_path()
    return config.get().approval.path or default_path()
end

---@param path string
---@return string
local function policy_dir(path)
    return string.format('%s.d', path)
end

---@param value string
---@return string
local function encode_path_component(value)
    return value:gsub('[^%w._-]', function(char)
        return string.format('%%%02X', char:byte())
    end)
end

---@param server string
---@return string
local function server_filename(server)
    return string.format('%s.json', encode_path_component(server))
end

---@param path string
local function ensure_parent(path)
    local parent = vim.fs.dirname(path)
    if parent ~= nil and parent ~= '' then
        vim.fn.mkdir(parent, 'p')
    end
end

---@param value any
---@return ministry.ApprovalStore
local function normalize_store(value)
    local normalized = {
        servers = {},
    }

    if type(value) ~= 'table' or type(value.servers) ~= 'table' then
        return normalized
    end

    for server, rules in pairs(value.servers) do
        if type(server) == 'string' and type(rules) == 'table' then
            local entry = {
                tools = {},
            }

            if valid_decision(rules.default) then
                entry.default = rules.default
            end

            if type(rules.tools) == 'table' then
                for method, decision in pairs(rules.tools) do
                    if type(method) == 'string' and valid_decision(decision) then
                        entry.tools[method] = decision
                    end
                end
            end

            normalized.servers[server] = entry
        end
    end

    return normalized
end

---@param path string
---@return table?, string?
local function read_json(path)
    local text = vim.fn.filereadable(path) == 1 and table.concat(vim.fn.readfile(path), '\n') or nil
    if text == nil or text == '' then
        return nil, nil
    end

    local ok, decoded = pcall(vim.json.decode, text)
    if not ok then
        return nil, tostring(decoded)
    end

    return type(decoded) == 'table' and decoded or nil, nil
end

---@param path string
---@param payload table
local function write_json(path, payload)
    ensure_parent(path)
    vim.fn.writefile(vim.split(vim.json.encode(payload), '\n', { plain = true }), path)
end

---@param index table
---@param path string
---@return ministry.ApprovalStore
local function load_fragmented(index, path)
    local normalized = {
        servers = {},
    }

    if type(index.servers) ~= 'table' then
        return normalized
    end

    local root = policy_dir(path)
    for _, entry in ipairs(index.servers) do
        if type(entry) == 'table' and type(entry.name) == 'string' then
            local filename = type(entry.file) == 'string' and entry.file or server_filename(entry.name)
            local rules = read_json(vim.fs.joinpath(root, 'servers', filename))
            if type(rules) == 'table' then
                normalized.servers[entry.name] = normalize_store({
                    servers = {
                        [entry.name] = rules,
                    },
                }).servers[entry.name]
            end
        end
    end

    return normalized
end

---@param server string
---@param rules table
---@return table
local function server_index_entry(server, rules)
    local tools = type(rules.tools) == 'table' and rules.tools or {}
    return {
        name = server,
        default = rules.default,
        tool_count = vim.tbl_count(tools),
        file = server_filename(server),
    }
end

function M.load()
    local applied = config.get()
    loaded_path = policy_path()
    store = {
        servers = {},
    }

    if not applied.approval.persistence then
        return
    end

    local path = loaded_path
    local decoded, err = read_json(path)
    if decoded == nil and err == nil then
        return
    end

    if err ~= nil then
        vim.notify(string.format('Ministry approval policy %s is invalid JSON: %s', path, err), vim.log.levels.WARN)
        return
    end

    if decoded.version == CURRENT_VERSION then
        store = load_fragmented(decoded, path)
    end
end

function M.save()
    if not config.get().approval.persistence then
        return
    end

    local path = loaded_path or policy_path()
    local root = policy_dir(path)
    local index = {
        version = CURRENT_VERSION,
        servers = {},
    }

    for server, rules in pairs(store.servers) do
        write_json(vim.fs.joinpath(root, 'servers', server_filename(server)), rules)
        table.insert(index.servers, server_index_entry(server, rules))
    end

    table.sort(index.servers, function(left, right)
        return left.name < right.name
    end)

    write_json(path, index)
end

---@param server string
---@param method? string
---@return ministry.ApprovalDecision
function M.get(server, method)
    local rules = store.servers[server]
    if rules ~= nil then
        if method ~= nil and rules.tools ~= nil and valid_decision(rules.tools[method]) then
            return rules.tools[method]
        end
        if valid_decision(rules.default) then
            return rules.default
        end
    end

    local fallback = config.get().approval.default
    return valid_decision(fallback) and fallback or 'ask'
end

---@param server string
---@param method string|nil
---@param decision ministry.ApprovalDecision
function M.set(server, method, decision)
    assert(type(server) == 'string' and server ~= '', 'approval server must be a non-empty string')
    assert(valid_decision(decision), 'approval decision must be allow, reject, or ask')

    local rules = store.servers[server]
    if rules == nil then
        rules = {
            tools = {},
        }
        store.servers[server] = rules
    end

    if method == nil or method == '' then
        rules.default = decision
    else
        rules.tools = rules.tools or {}
        rules.tools[method] = decision
    end

    M.save()
end

---@param server string
---@return { default: ministry.ApprovalDecision?, allow: integer, reject: integer, ask: integer, tools: table<string, ministry.ApprovalDecision> }
function M.summary(server)
    local rules = store.servers[server] or {}
    local tools = rules.tools or {}
    local summary = {
        default = rules.default,
        allow = 0,
        reject = 0,
        ask = 0,
        tools = vim.deepcopy(tools),
    }

    for _, decision in pairs(tools) do
        if summary[decision] ~= nil then
            summary[decision] = summary[decision] + 1
        end
    end

    return summary
end

---@param namespaced_name string
---@return string?, string?
local function split_tool_name(namespaced_name)
    return namespaced_name:match('^([^/]+)/(.+)$')
end

---@param request ministry.ApprovalRequest
---@return string?
local function approval_tool_call_id(request)
    local context = type(request.context) == 'table' and request.context or {}
    local tool_call_id = context.tool_call_id or context.legate_tool_call_id

    return type(tool_call_id) == 'string' and tool_call_id ~= '' and tool_call_id or nil
end

---@param request ministry.ApprovalRequest
---@return string?
local function approval_transport_session_id(request)
    local context = type(request.context) == 'table' and request.context or {}
    local session_id = context.transport_session_id
    return type(session_id) == 'string' and session_id ~= '' and session_id or nil
end

---@param request ministry.ApprovalRequest
---@return string?
local function approval_logical_session_id(request)
    local context = type(request.context) == 'table' and request.context or {}
    local session_id = context.legate_session_id or context.session_id
    return type(session_id) == 'string' and session_id ~= '' and session_id or nil
end

---@param request ministry.ApprovalRequest
---@return ministry.PendingApproval
local function approval_entry(request)
    return {
        server = request.server,
        method = request.method,
        namespaced_name = request.namespaced_name,
        arguments = vim.deepcopy(request.arguments or {}),
        tool_call_id = approval_tool_call_id(request),
        logical_session_id = approval_logical_session_id(request),
        transport_session_id = approval_transport_session_id(request),
        expires_at_ms = now_ms() + math.max(1, tonumber(config.get().approval.reservation_ttl_ms) or 30000),
    }
end

---@param entry ministry.PendingApproval
---@param request ministry.ApprovalRequest
---@return boolean
local function approval_target_matches(entry, request)
    return entry.server == request.server
        and entry.method == request.method
        and entry.namespaced_name == request.namespaced_name
end

---@param entry ministry.PendingApproval
---@param request ministry.ApprovalRequest
---@return boolean
local function approval_payload_matches(entry, request)
    return approval_target_matches(entry, request) and vim.deep_equal(entry.arguments, request.arguments or {})
end

local function remove_expired_approvals()
    local current_time = now_ms()
    local retained = {}

    for _, entry in ipairs(pending_approvals) do
        if entry.expires_at_ms > current_time then
            table.insert(retained, entry)
        end
    end

    pending_approvals = retained
end

---@param entry ministry.PendingApproval
---@param request ministry.ApprovalRequest
---@return boolean
local function approval_binding_matches(entry, request)
    local request_transport_session_id = approval_transport_session_id(request)
    local request_logical_session_id = approval_logical_session_id(request)
    local request_tool_call_id = approval_tool_call_id(request)

    if entry.transport_session_id ~= nil then
        if request_transport_session_id ~= entry.transport_session_id then
            return false
        end
        return entry.tool_call_id == nil or request_tool_call_id == nil or request_tool_call_id == entry.tool_call_id
    end

    if entry.logical_session_id ~= nil then
        if request_logical_session_id ~= entry.logical_session_id then
            return false
        end
        return entry.tool_call_id == nil or request_tool_call_id == nil or request_tool_call_id == entry.tool_call_id
    end

    if entry.tool_call_id ~= nil then
        return request_tool_call_id == entry.tool_call_id
    end

    return request_transport_session_id == nil and request_logical_session_id == nil and request_tool_call_id == nil
end

---@param request ministry.ApprovalRequest
local function remember_approval(request)
    remove_expired_approvals()
    table.insert(pending_approvals, approval_entry(request))
end

---@param request ministry.ApprovalRequest
---@return table
local function mismatch_error(request)
    return {
        code = -32001,
        message = string.format('Ministry approval payload mismatch for %s', request.namespaced_name),
    }
end

---@param request ministry.ApprovalRequest
---@return boolean|nil, table|nil
local function consume_approval(request)
    remove_expired_approvals()
    local has_pending_for_binding = false

    for index, entry in ipairs(pending_approvals) do
        if approval_binding_matches(entry, request) and approval_payload_matches(entry, request) then
            table.remove(pending_approvals, index)
            return true, nil
        end

        if approval_binding_matches(entry, request) and approval_target_matches(entry, request) then
            has_pending_for_binding = true
        end
    end

    if has_pending_for_binding then
        return false, mismatch_error(request)
    end

    return nil, nil
end

---@param request ministry.ApprovalRequest
---@param provider fun(request: ministry.ApprovalRequest): ministry.ApprovalDecision|boolean|nil
---@param label string
---@return boolean|nil, table|nil, boolean
local function check_provider(request, provider, label)
    local ok, provider_decision = pcall(provider, vim.deepcopy(request))
    if not ok then
        return false,
            {
                code = -32001,
                message = string.format('Ministry approval provider %s failed: %s', label, tostring(provider_decision)),
            },
            true
    end
    if provider_decision == true or provider_decision == 'allow' then
        return true, nil, true
    end
    if provider_decision == false or provider_decision == 'reject' then
        return false,
            {
                code = -32001,
                message = string.format('Ministry approval rejected %s', request.namespaced_name),
            },
            true
    end

    return nil, nil, false
end

---@param provider_name string
---@return (fun(request: ministry.ApprovalRequest): ministry.ApprovalDecision|boolean|nil)?
local function load_discovered_provider(provider_name)
    local ok, provider = pcall(require, 'ministry.approval.providers.' .. provider_name)
    if not ok then
        return nil
    end
    if type(provider) == 'function' then
        return provider
    end
    if type(provider) == 'table' and type(provider.request) == 'function' then
        return provider.request
    end
    return nil
end

---@param request ministry.ApprovalRequest
---@return boolean|nil, table|nil, boolean
local function check_discovered_providers(request)
    local provider_names = config.get().approval.providers
    if type(provider_names) ~= 'table' then
        return nil, nil, false
    end

    for _, provider_name in ipairs(provider_names) do
        if type(provider_name) == 'string' and provider_name ~= '' then
            local provider = load_discovered_provider(provider_name)
            if provider ~= nil then
                local approved, err, handled = check_provider(request, provider, provider_name)
                if handled then
                    return approved, err, true
                end
            end
        end
    end

    return nil, nil, false
end

---@param request ministry.ApprovalRequest
---@param opts? { ignore_enabled?: boolean, ignore_pending?: boolean }
---@return boolean, table|nil
function M.check(request, opts)
    if not config.get().approval.enabled and not (opts ~= nil and opts.ignore_enabled) then
        return true, nil
    end

    if not (opts ~= nil and opts.ignore_pending) then
        local pending_approved, pending_err = consume_approval(request)

        if pending_approved ~= nil then
            return pending_approved, pending_err
        end
    end

    local server = request.server
    local method = request.method
    local decision = M.get(server, method)

    if decision == 'allow' then
        return true, nil
    end

    if decision == 'reject' then
        return false,
            {
                code = -32001,
                message = string.format('Ministry approval rejected %s', request.namespaced_name),
            }
    end

    local provider = config.get().approval.provider
    if type(provider) == 'function' then
        local approved, err, handled = check_provider(request, provider, 'configured')
        if handled then
            return approved, err
        end
    end

    local approved, err, handled = check_discovered_providers(request)
    if handled then
        return approved, err
    end

    return false,
        {
            code = -32001,
            message = string.format('Ministry approval required for %s', request.namespaced_name),
        }
end

---@param request ministry.ApprovalRequest
---@return boolean, table|nil
function M.request(request)
    local approved, err = M.check(request, { ignore_pending = true })

    if approved then
        remember_approval(request)
    end

    return approved, err
end

---@param request ministry.ApprovalRequest
---@return boolean, table|nil
function M.approve_once(request)
    remember_approval(request)
    return true, nil
end

---@param session_id string
function M.cancel_session(session_id)
    local retained = {}

    for _, entry in ipairs(pending_approvals) do
        if entry.transport_session_id ~= session_id then
            table.insert(retained, entry)
        end
    end

    pending_approvals = retained
end

---@return ministry.PendingApproval[]
function M._debug_pending_approvals()
    remove_expired_approvals()
    return vim.deepcopy(pending_approvals)
end

---@param namespaced_name string
---@param arguments table
---@param context table
---@return boolean, table|nil
function M.check_tool(namespaced_name, arguments, context)
    local server, method = split_tool_name(namespaced_name)
    if server == nil or method == nil then
        return true, nil
    end

    return M.check({
        server = server,
        method = method,
        namespaced_name = namespaced_name,
        arguments = arguments,
        context = context,
    })
end

function M.reset()
    store = {
        servers = {},
    }
    pending_approvals = {}
    loaded_path = nil
end

return M
