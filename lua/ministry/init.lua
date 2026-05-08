local config = require('ministry.core.config')
local builtin_coverage = require('ministry.builtin.coverage.init')
local builtin_dap = require('ministry.builtin.dap.init')
local builtin_editor = require('ministry.builtin.editor.init')
local builtin_formatting = require('ministry.builtin.formatting.init')
local builtin_git = require('ministry.builtin.git.init')
local builtin_lint = require('ministry.builtin.lint.init')
local builtin_lsp = require('ministry.builtin.lsp.init')
local builtin_mason = require('ministry.builtin.mason.init')
local builtin_navigation = require('ministry.builtin.navigation.init')
local builtin_neovim_guidance = require('ministry.builtin.neovim_guidance')
local builtin_overseer = require('ministry.builtin.overseer.init')
local builtin_quickfix = require('ministry.builtin.quickfix.init')
local builtin_terminal = require('ministry.builtin.terminal')
local builtin_terminal_runtime = require('ministry.builtin.terminal_runtime')
local approval = require('ministry.approval.policy')
local dispatch = require('ministry.protocol.dispatch')
local endpoint = require('ministry.transport.endpoint')
local external = require('ministry.external.manager')
local list_attachments = require('ministry.resources.list_providers')
local registry = require('ministry.core.registry')
local router = require('ministry.protocol.router')
local server = require('ministry.transport.server')
local http_server = require('ministry.transport.http.server')

---@class ministry.Module
local M = {}

local builtin_neovim_overrides = nil
local builtin_neovim_mode = 'builtin'
local commands_registered = false
local merge_named_specs

local function socket_transport_supported()
    local pipe = vim.uv.new_pipe(false)
    local supports_socket = pipe ~= nil and pipe.bind2 ~= nil

    if pipe ~= nil and pipe.close ~= nil then
        local closing = pipe.is_closing ~= nil and pipe:is_closing() or false
        if not closing then
            pipe:close()
        end
    end

    return supports_socket
end

local function builtin_neovim_server_spec()
    local editor_server = builtin_editor.server_spec()
    local applied = config.get()
    local namespaces = {
        tools = {
            dap = 'Debugger controls backed by dap.nvim.',
            editor = 'Editor buffer, file, diff, and prompt tools.',
            git = 'Stratum-backed Git repository observation tools.',
            lsp = 'Neovim LSP diagnostics, symbols, actions, and location tools.',
        },
        resources = {
            buffers = 'Current Neovim buffer inventory.',
            coverage = 'Coverage plugin state for the current session.',
            dap = 'Debugger session state backed by dap.nvim.',
            formatting = 'Formatter configuration for the current buffer filetype.',
            git = 'Stratum-backed Git repository, ref, and changed-path state.',
            lint = 'Linter configuration and running linter state.',
            ['location-list'] = 'Current-window location-list state.',
            lsp = 'Active Neovim LSP clients and current-buffer LSP state.',
            mason = 'Installed Mason package inventory.',
            navigation = 'Builtin Neovim mark and navigation anchors.',
            quickfix = 'Current quickfix list state.',
            tasks = 'Generic Overseer task state.',
            workspace = 'Editor and workspace summary for the current Neovim session.',
        },
        resource_templates = {
            dap = 'Parameterized debugger resources backed by dap.nvim.',
            ['dap/scopes'] = 'Debugger scopes for a concrete stack frame.',
            ['dap/stack'] = 'Debugger stack frames for a concrete thread.',
            ['dap/variables'] = 'Debugger variables for a concrete variablesReference.',
        },
    }
    local tools = {
        dap = builtin_dap.tools_tree(),
        editor = builtin_editor.tools_tree(),
        git = builtin_git.tools_tree(),
        lsp = builtin_lsp.tools_tree(),
    }
    local resources =
        merge_named_specs(builtin_coverage.server_spec().resources, builtin_dap.server_spec().resources, 'uri')
    resources = merge_named_specs(resources, builtin_lsp.server_spec().resources, 'uri')
    resources = merge_named_specs(builtin_formatting.server_spec().resources, resources, 'uri')
    resources = merge_named_specs(builtin_git.server_spec().resources, resources, 'uri')
    resources = merge_named_specs(builtin_lint.server_spec().resources, resources, 'uri')
    resources = merge_named_specs(builtin_mason.server_spec().resources, resources, 'uri')
    resources = merge_named_specs(builtin_navigation.server_spec().resources, resources, 'uri')
    resources = merge_named_specs(builtin_overseer.server_spec().resources, resources, 'uri')
    resources = merge_named_specs(builtin_quickfix.server_spec().resources, resources, 'uri')
    resources = merge_named_specs(resources, editor_server.resources, 'uri')
    local resource_templates = merge_named_specs(
        builtin_dap.server_spec().resource_templates,
        editor_server.resource_templates,
        'uri_template'
    )

    if applied.enable_terminal_tools then
        tools.terminal = builtin_terminal.tools_tree()
        namespaces.tools.terminal = 'Ministry-owned terminal runtime tools.'
        namespaces.resources.terminals = 'Ministry-owned terminal runtime summaries.'
        resources = merge_named_specs(builtin_terminal.resources_specs(), resources, 'uri')
    end

    return {
        name = 'neovim',
        title = 'Neovim',
        description = 'Built-in Neovim-local MCP capability surfaces.',
        guidance = builtin_neovim_guidance.guidance,
        tools = tools,
        resources = resources,
        resource_templates = resource_templates,
        prompts = editor_server.prompts,
        namespaces = namespaces,
    }
end

local function merge_tool_specs(existing_tools, builtin_tools)
    local merged = {}
    local positions = {}

    for _, tool in ipairs(registry.normalize_tools(builtin_tools)) do
        table.insert(merged, tool)
        positions[tool.name] = #merged
    end

    for _, tool in ipairs(registry.normalize_tools(existing_tools)) do
        local position = positions[tool.name]
        if position ~= nil then
            merged[position] = tool
        else
            table.insert(merged, tool)
            positions[tool.name] = #merged
        end
    end

    return merged
end

function merge_named_specs(existing_items, builtin_items, key)
    local merged = {}
    local positions = {}

    for _, item in ipairs(builtin_items or {}) do
        table.insert(merged, vim.tbl_extend('force', {}, item))
        positions[item[key]] = #merged
    end

    for _, item in ipairs(existing_items or {}) do
        local position = positions[item[key]]
        if position ~= nil then
            merged[position] = vim.tbl_extend('force', {}, merged[position], item)
        else
            table.insert(merged, item)
            positions[item[key]] = #merged
        end
    end

    return merged
end

---@param existing ministry.NamespaceDescriptions?
---@param builtin ministry.NamespaceDescriptions?
---@return ministry.NamespaceDescriptions?
local function merge_namespaces(existing, builtin)
    if existing == nil and builtin == nil then
        return nil
    end

    local merged = vim.deepcopy(builtin or {})
    for _, group in ipairs({ 'tools', 'resources', 'resource_templates', 'prompts' }) do
        if existing ~= nil and existing[group] ~= nil then
            merged[group] = vim.tbl_extend('force', merged[group] or {}, existing[group])
        end
    end
    return merged
end

local function snapshot_neovim_overrides(existing)
    if existing == nil then
        return nil
    end

    return {
        title = existing.title,
        description = existing.description,
        guidance = existing.guidance,
        tools = existing.tools,
        resources = existing.resources,
        resource_templates = existing.resource_templates,
        prompts = existing.prompts,
        namespaces = existing.namespaces,
    }
end

local function contains_key_overlap(existing_items, builtin_items, key)
    local builtin_keys = {}

    for _, item in ipairs(builtin_items or {}) do
        builtin_keys[item[key]] = true
    end

    for _, item in ipairs(existing_items or {}) do
        if builtin_keys[item[key]] then
            return true
        end
    end

    return false
end

local function has_any_items(items)
    return items ~= nil and #items > 0
end

---@param namespaces ministry.NamespaceDescriptions?
---@return boolean
local function has_namespace_descriptions(namespaces)
    if namespaces == nil then
        return false
    end

    for _, group in ipairs({ 'tools', 'resources', 'resource_templates', 'prompts' }) do
        if namespaces[group] ~= nil and next(namespaces[group]) ~= nil then
            return true
        end
    end
    return false
end

local function explicit_custom_neovim(existing)
    if existing == nil then
        return false
    end

    local builtin = builtin_neovim_server_spec()
    local existing_tools = registry.normalize_tools(existing.tools)
    local builtin_tools = registry.normalize_tools(builtin.tools)

    local overlaps_builtin = contains_key_overlap(existing_tools, builtin_tools, 'name')
        or contains_key_overlap(existing.resources, builtin.resources, 'uri')
        or contains_key_overlap(existing.resource_templates, builtin.resource_templates, 'uri_template')
        or contains_key_overlap(existing.prompts, builtin.prompts, 'name')

    if overlaps_builtin then
        return false
    end

    return has_any_items(existing_tools)
        or has_any_items(existing.resources)
        or has_any_items(existing.resource_templates)
        or has_any_items(existing.prompts)
        or has_namespace_descriptions(existing.namespaces)
        or existing.title ~= nil
        or existing.description ~= nil
end

local function tool_specs_equal(left, right)
    if left == right then
        return true
    end

    if left == nil or right == nil then
        return false
    end

    local left_schema = left.input_schema or left.inputSchema
    local right_schema = right.input_schema or right.inputSchema

    return left.handler == right.handler
        and left.description == right.description
        and vim.deep_equal(left_schema, right_schema)
end

local function strip_builtin_tool_overrides(existing_tools, builtin_tools)
    if existing_tools == nil then
        return nil
    end

    local builtin_by_name = {}
    for _, tool in ipairs(registry.normalize_tools(builtin_tools)) do
        builtin_by_name[tool.name] = tool
    end

    local overrides = {}
    for _, tool in ipairs(registry.normalize_tools(existing_tools)) do
        local builtin_tool = builtin_by_name[tool.name]
        if not tool_specs_equal(tool, builtin_tool) then
            table.insert(overrides, tool)
        end
    end

    return overrides
end

local function strip_builtin_named_overrides(existing_items, builtin_items, key)
    if existing_items == nil then
        return nil
    end

    local builtin_by_key = {}
    for _, item in ipairs(builtin_items or {}) do
        builtin_by_key[item[key]] = item
    end

    local overrides = {}
    for _, item in ipairs(existing_items or {}) do
        if builtin_by_key[item[key]] == nil then
            table.insert(overrides, item)
        end
    end

    return overrides
end

local function snapshot_user_neovim_overrides(existing)
    if existing == nil then
        return nil
    end

    local builtin = builtin_neovim_server_spec()

    return {
        title = nil,
        description = nil,
        guidance = existing.guidance ~= builtin.guidance and existing.guidance or nil,
        tools = strip_builtin_tool_overrides(existing.tools, builtin.tools),
        resources = strip_builtin_named_overrides(existing.resources, builtin.resources, 'uri'),
        resource_templates = strip_builtin_named_overrides(
            existing.resource_templates,
            builtin.resource_templates,
            'uri_template'
        ),
        prompts = strip_builtin_named_overrides(existing.prompts, builtin.prompts, 'name'),
        namespaces = existing.namespaces,
    }
end

local function sync_builtin_neovim_state(existing)
    if existing == nil then
        builtin_neovim_overrides = nil
        builtin_neovim_mode = 'builtin'
        return
    end

    if explicit_custom_neovim(existing) then
        builtin_neovim_overrides = snapshot_neovim_overrides(existing)
        builtin_neovim_mode = 'custom'
        return
    end

    builtin_neovim_overrides = snapshot_user_neovim_overrides(existing)
    builtin_neovim_mode = builtin_neovim_overrides == nil and 'builtin' or 'overrides'
end

local function register_builtin_neovim_server(existing)
    if builtin_neovim_mode == 'custom' then
        return
    end

    local builtin = builtin_neovim_server_spec()
    local overrides = existing or builtin_neovim_overrides

    if overrides == nil then
        registry.register_server(builtin)
        builtin_neovim_overrides = nil
        builtin_neovim_mode = 'builtin'
        return
    end

    builtin_neovim_overrides = snapshot_neovim_overrides(overrides)
    builtin_neovim_mode = 'overrides'

    registry.register_server({
        name = 'neovim',
        title = overrides.title or builtin.title,
        description = overrides.description or builtin.description,
        guidance = overrides.guidance or builtin.guidance,
        tools = merge_tool_specs(overrides.tools, builtin.tools),
        resources = merge_named_specs(overrides.resources, builtin.resources, 'uri'),
        resource_templates = merge_named_specs(
            overrides.resource_templates,
            builtin.resource_templates,
            'uri_template'
        ),
        prompts = merge_named_specs(overrides.prompts, builtin.prompts, 'name'),
        namespaces = merge_namespaces(overrides.namespaces, builtin.namespaces),
    })
end

local function register_commands()
    if commands_registered then
        return
    end

    vim.api.nvim_create_user_command('MinistryServers', function()
        M.open_servers()
    end, {})

    vim.api.nvim_create_user_command('MinistryApprove', function(command)
        local server, method = command.args:match('^(%S+)%s*(.*)$')
        if server ~= nil then
            M.set_approval(server, method ~= '' and method or nil, 'allow')
        end
    end, { nargs = '+' })

    vim.api.nvim_create_user_command('MinistryReject', function(command)
        local server, method = command.args:match('^(%S+)%s*(.*)$')
        if server ~= nil then
            M.set_approval(server, method ~= '' and method or nil, 'reject')
        end
    end, { nargs = '+' })

    vim.api.nvim_create_user_command('MinistryAsk', function(command)
        local server, method = command.args:match('^(%S+)%s*(.*)$')
        if server ~= nil then
            M.set_approval(server, method ~= '' and method or nil, 'ask')
        end
    end, { nargs = '+' })

    commands_registered = true
end

---@param opts? Partial<ministry.Config>
---@return ministry.Config
function M.setup(opts)
    local applied = config.set(opts)

    approval.load()
    register_builtin_neovim_server(builtin_neovim_overrides)
    register_commands()
    if applied.external.enabled then
        external.discover()
    end

    if applied.auto_start then
        local transport = applied.transport or 'socket'
        if transport == 'http' then
            server.start(transport)
        elseif transport == 'socket' and socket_transport_supported() then
            server.start(transport)
        end
    end

    return applied
end

---@param server ministry.ServerSpec
---@return ministry.ServerSpec
function M.register_server(server)
    local existing_neovim = server.name == 'neovim' and registry.get_server('neovim') or nil
    local registered = registry.register_server(server)

    if server.name == 'neovim' then
        if
            existing_neovim == nil
            and builtin_neovim_mode == 'builtin'
            and server.title == nil
            and server.description == nil
        then
            builtin_neovim_overrides = snapshot_neovim_overrides(registered)
            builtin_neovim_mode = 'overrides'
        elseif builtin_neovim_mode == 'custom' and existing_neovim ~= nil and server.description == nil then
            builtin_neovim_overrides = snapshot_neovim_overrides(registered)
            builtin_neovim_mode = 'overrides'
        else
            sync_builtin_neovim_state(registered)
        end
    end

    return registered
end

---@param server_name string
function M.unregister_server(server_name)
    registry.unregister_server(server_name)

    if server_name == 'neovim' then
        builtin_neovim_overrides = nil
        builtin_neovim_mode = 'builtin'
    end
end

---@return ministry.ExternalRuntime[], table[]
function M.refresh_external_servers()
    return external.refresh()
end

---@return ministry.ServerStatus[]
function M.list_server_statuses()
    local statuses = {}
    local external_by_name = {}

    for _, runtime in ipairs(external.list_runtimes()) do
        external_by_name[runtime.spec.name] = runtime
        table.insert(statuses, {
            name = runtime.spec.name,
            source = runtime.spec.source,
            transport = runtime.spec.transport,
            command = runtime.spec.command,
            args = runtime.spec.args,
            url = runtime.spec.url,
            state = runtime.state,
            error = runtime.error,
            policy = approval.summary(runtime.spec.name),
            tools = runtime.tools,
            resources = runtime.resources,
            resource_templates = runtime.resource_templates,
            prompts = runtime.prompts,
            namespaces = runtime.namespaces,
        })
    end

    for _, server_spec in ipairs(registry.list_servers()) do
        if external_by_name[server_spec.name] == nil then
            local source = server_spec.ministry_source
                or {
                    kind = 'native',
                    name = 'neovim',
                }
            table.insert(statuses, {
                name = server_spec.name,
                source = source,
                transport = 'native',
                state = 'ready',
                policy = approval.summary(server_spec.name),
                tools = server_spec.tools,
                resources = server_spec.resources,
                resource_templates = server_spec.resource_templates,
                prompts = server_spec.prompts,
                namespaces = server_spec.namespaces,
            })
        end
    end

    table.sort(statuses, function(left, right)
        return left.name < right.name
    end)

    return statuses
end

---@param server string
---@param method string|nil
---@return ministry.ApprovalDecision
function M.get_approval(server, method)
    return approval.get(server, method)
end

---@param server string
---@param method string
---@param arguments table?
---@param context table?
---@return boolean, table|nil
function M.request_approval(server, method, arguments, context)
    return approval.request({
        server = server,
        method = method,
        namespaced_name = string.format('%s/%s', server, method),
        arguments = arguments or {},
        context = context or {},
    })
end

---@param server string
---@param method string
---@param arguments table?
---@param context table?
---@return boolean, table|nil
function M.approve_once(server, method, arguments, context)
    return approval.approve_once({
        server = server,
        method = method,
        namespaced_name = string.format('%s/%s', server, method),
        arguments = arguments or {},
        context = context or {},
    })
end

---@param server string
---@param method string|nil
---@param decision ministry.ApprovalDecision
function M.set_approval(server, method, decision)
    approval.set(server, method, decision)
end

function M.open_servers()
    require('ministry.ui.servers').open(M.list_server_statuses())
end

---@param server_name string
---@param tool ministry.ToolSpec
function M.register_tool(server_name, tool)
    if server_name == 'neovim' and registry.get_server('neovim') == nil then
        register_builtin_neovim_server(builtin_neovim_overrides)
    end

    registry.register_tool(server_name, tool)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param tool_name string
function M.unregister_tool(server_name, tool_name)
    registry.unregister_tool(server_name, tool_name)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param resource ministry.ResourceSpec
function M.register_resource(server_name, resource)
    if server_name == 'neovim' and registry.get_server('neovim') == nil then
        register_builtin_neovim_server(builtin_neovim_overrides)
    end

    registry.register_resource(server_name, resource)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param uri string
function M.unregister_resource(server_name, uri)
    registry.unregister_resource(server_name, uri)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param resource_template ministry.ResourceTemplateSpec
function M.register_resource_template(server_name, resource_template)
    if server_name == 'neovim' and registry.get_server('neovim') == nil then
        register_builtin_neovim_server(builtin_neovim_overrides)
    end

    registry.register_resource_template(server_name, resource_template)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param template_name string
function M.unregister_resource_template(server_name, template_name)
    registry.unregister_resource_template(server_name, template_name)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param prompt ministry.PromptSpec
function M.register_prompt(server_name, prompt)
    if server_name == 'neovim' and registry.get_server('neovim') == nil then
        register_builtin_neovim_server(builtin_neovim_overrides)
    end

    registry.register_prompt(server_name, prompt)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param prompt_name string
function M.unregister_prompt(server_name, prompt_name)
    registry.unregister_prompt(server_name, prompt_name)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
---@param guidance string|string[]|fun(ctx: table): string|string[]|nil
function M.register_server_guidance(server_name, guidance)
    if server_name == 'neovim' and registry.get_server('neovim') == nil then
        register_builtin_neovim_server(builtin_neovim_overrides)
    end

    registry.register_server_guidance(server_name, guidance)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@param server_name string
function M.unregister_server_guidance(server_name)
    registry.unregister_server_guidance(server_name)

    if server_name == 'neovim' then
        sync_builtin_neovim_state(registry.get_server('neovim'))
    end
end

---@return ministry.ServerSpec[]
function M.list_servers()
    return registry.list_servers()
end

---@return table[]
function M.list_tool_descriptors()
    return registry.list_tool_descriptors()
end

---@return table[]
function M.list_resource_descriptors()
    return registry.list_resource_descriptors()
end

---@return table[]
function M.list_resource_template_descriptors()
    return registry.list_resource_template_descriptors()
end

---@return table[]
function M.list_prompt_descriptors()
    return registry.list_prompt_descriptors()
end

---@param server_name string
---@param context? table
---@return string|nil
function M.server_guidance(server_name, context)
    return registry.server_guidance(server_name, context)
end

---@param context? table
---@return { server: string, guidance: string }[]
function M.list_server_guidance(context)
    return registry.list_server_guidance(context)
end

---@param namespaced_name string
---@param arguments table|nil
---@param context table|nil
---@return table|nil, table|nil
function M.call_tool(namespaced_name, arguments, context)
    return dispatch.call_tool(namespaced_name, arguments, context)
end

---@param method string|nil
---@param params table|nil
---@param id integer|string|nil
---@param context table|nil
---@return table|nil
function M.handle_request(method, params, id, context)
    return router.handle_request(method, params, id, context)
end

---@param transport? 'socket'|'http'
---@return boolean, string?
function M.start(transport)
    return server.start(transport or config.get().transport or 'socket')
end

---@return boolean, string?
function M.start_all()
    return server.start_all()
end

function M.stop()
    server.stop()
end

---@return boolean
function M.running()
    return server.running()
end

---@return ministry.EndpointDescriptor
function M.endpoint()
    return endpoint.describe()
end

---@return table
function M.endpoint_invocation()
    return endpoint.describe().invocation
end

---@param list_name string
---@param owner string
---@param callback fun(item: table, item_id: string): table<string, any>|nil
---@return table|nil, table|nil
function M.register_list_item_data_provider(list_name, owner, callback)
    return list_attachments.register(list_name, owner, callback)
end

---@param list_name string
---@param owner string
---@return table|nil, table|nil
function M.unregister_list_item_data_provider(list_name, owner)
    return list_attachments.unregister(list_name, owner)
end

---@return ministry.EndpointDescriptor?
function M.http_endpoint()
    local host, port = http_server.bound_address()

    if host == nil or port == nil then
        return nil
    end

    return endpoint.describe_http(host, port)
end

function M.reset()
    builtin_neovim_overrides = nil
    builtin_neovim_mode = 'builtin'

    server.stop()
    http_server.stop()
    builtin_terminal_runtime.reset()
    external.reset()
    approval.reset()
    endpoint.reset()
    config.reset()
    registry.reset()
end

return M
