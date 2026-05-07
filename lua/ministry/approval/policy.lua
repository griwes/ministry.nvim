local config = require('ministry.core.config')

local M = {}

---@class ministry.ApprovalStore
---@field servers table<string, { default?: ministry.ApprovalDecision, tools?: table<string, ministry.ApprovalDecision> }>

---@type ministry.ApprovalStore
local store = {
    servers = {},
}

---@type string?
local loaded_path = nil

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
    local text = vim.fn.filereadable(path) == 1 and table.concat(vim.fn.readfile(path), '\n') or nil
    if text == nil or text == '' then
        return
    end

    local ok, decoded = pcall(vim.json.decode, text)
    if not ok then
        vim.notify(string.format('Ministry approval policy %s is invalid JSON: %s', path, decoded), vim.log.levels.WARN)
        return
    end

    store = normalize_store(decoded)
end

function M.save()
    if not config.get().approval.persistence then
        return
    end

    local path = loaded_path or policy_path()
    ensure_parent(path)
    vim.fn.writefile(vim.split(vim.json.encode(store), '\n', { plain = true }), path)
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
---@param opts? { ignore_enabled?: boolean }
---@return boolean, table|nil
function M.check(request, opts)
    if not config.get().approval.enabled and not (opts ~= nil and opts.ignore_enabled) then
        return true, nil
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

    if #vim.api.nvim_list_uis() == 0 then
        return false,
            {
                code = -32001,
                message = string.format('Ministry approval required for %s', request.namespaced_name),
            }
    end

    local choice =
        vim.fn.confirm(string.format('Allow Ministry MCP call %s?', request.namespaced_name), '&Allow\n&Reject', 2)
    if choice == 1 then
        return true, nil
    end

    return false,
        {
            code = -32001,
            message = string.format('Ministry approval rejected %s', request.namespaced_name),
        }
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
    loaded_path = nil
end

return M
