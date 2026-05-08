local M = {}

---@class ministry.NeovimGuidanceSurface
---@field has_resources boolean
---@field has_buffers_list boolean
---@field has_workspace_summary boolean
---@field has_terminals_summary boolean
---@field has_tasks_summary boolean
---@field has_git_repository boolean
---@field has_git_overview boolean
---@field has_git_refs boolean
---@field has_git_paths boolean
---@field has_git_path boolean
---@field has_dap_summary boolean
---@field has_dap_breakpoints boolean
---@field has_dap_threads boolean
---@field has_any_tools boolean
---@field has_any_editor_tools boolean
---@field has_any_terminal_tools boolean
---@field has_any_git_tools boolean
---@field has_any_dap_tools boolean
---@field has_list_buffers boolean
---@field has_open_buffer boolean
---@field has_read_buffer boolean
---@field has_write_buffer boolean
---@field has_diff_buffer boolean
---@field has_apply_diff_buffer boolean
---@field has_diff_file boolean
---@field has_apply_diff_file boolean
---@field has_write_file boolean
---@field has_terminal_create boolean
---@field has_terminal_output boolean
---@field has_terminal_wait boolean
---@field has_terminal_release boolean
---@field has_git_overview_tool boolean
---@field has_git_list_refs boolean
---@field has_git_list_paths boolean
---@field has_git_path_state boolean
---@field has_dap_continue boolean
---@field has_dap_pause boolean
---@field has_dap_step_over boolean
---@field has_dap_step_into boolean
---@field has_dap_step_out boolean
---@field has_dap_terminate boolean
---@field has_dap_disconnect boolean
---@field has_dap_stack_template boolean
---@field has_dap_scopes_template boolean
---@field has_dap_variables_template boolean

---@param value unknown
---@return boolean
local function has_enabled_capability(value)
    if value == true then
        return true
    end

    if type(value) ~= 'table' then
        return false
    end

    for _, nested in pairs(value) do
        if has_enabled_capability(nested) then
            return true
        end
    end

    return false
end

---@param agent_capabilities? table
---@return boolean
local function has_mcp_capability_payload(agent_capabilities)
    return agent_capabilities ~= nil and type(agent_capabilities.mcpCapabilities) == 'table'
end

---@param agent_capabilities? table
---@return boolean
local function has_any_mcp_capability(agent_capabilities)
    if not has_mcp_capability_payload(agent_capabilities) then
        return false
    end

    return has_enabled_capability(agent_capabilities.mcpCapabilities)
end

---@param agent_capabilities? table
---@param family string
---@return boolean
local function supports_mcp_family(agent_capabilities, family)
    if not has_mcp_capability_payload(agent_capabilities) then
        return false
    end

    return has_enabled_capability(agent_capabilities.mcpCapabilities[family])
end

---@param values string[]
---@return string
local function quoted_list(values)
    return table.concat(
        vim.tbl_map(function(value)
            return string.format('`%s`', value)
        end, values),
        ', '
    )
end

---@param groups string[]
---@return string
local function tool_group_list(groups)
    if #groups == 1 then
        return string.format('`%s`', groups[1])
    end
    if #groups == 2 then
        return string.format('`%s` or `%s`', groups[1], groups[2])
    end

    local quoted = vim.tbl_map(function(group)
        return string.format('`%s`', group)
    end, groups)
    quoted[#quoted] = 'or ' .. quoted[#quoted]
    return table.concat(quoted, ', ')
end

---@return ministry.NeovimGuidanceSurface
local function empty_surface()
    return {
        has_resources = false,
        has_buffers_list = false,
        has_workspace_summary = false,
        has_terminals_summary = false,
        has_tasks_summary = false,
        has_git_repository = false,
        has_git_overview = false,
        has_git_refs = false,
        has_git_paths = false,
        has_git_path = false,
        has_dap_summary = false,
        has_dap_breakpoints = false,
        has_dap_threads = false,
        has_any_tools = false,
        has_any_editor_tools = false,
        has_any_terminal_tools = false,
        has_any_git_tools = false,
        has_any_dap_tools = false,
        has_list_buffers = false,
        has_open_buffer = false,
        has_read_buffer = false,
        has_write_buffer = false,
        has_diff_buffer = false,
        has_apply_diff_buffer = false,
        has_diff_file = false,
        has_apply_diff_file = false,
        has_write_file = false,
        has_terminal_create = false,
        has_terminal_output = false,
        has_terminal_wait = false,
        has_terminal_release = false,
        has_git_overview_tool = false,
        has_git_list_refs = false,
        has_git_list_paths = false,
        has_git_path_state = false,
        has_dap_continue = false,
        has_dap_pause = false,
        has_dap_step_over = false,
        has_dap_step_into = false,
        has_dap_step_out = false,
        has_dap_terminate = false,
        has_dap_disconnect = false,
        has_dap_stack_template = false,
        has_dap_scopes_template = false,
        has_dap_variables_template = false,
    }
end

---@param server ministry.ServerSpec
---@return ministry.NeovimGuidanceSurface
local function available_surface(server)
    local surface = empty_surface()

    for _, resource in ipairs(server.resources or {}) do
        if resource.uri == 'buffers://list' then
            surface.has_resources = true
            surface.has_buffers_list = true
        elseif resource.uri == 'workspace://summary' then
            surface.has_resources = true
            surface.has_workspace_summary = true
        elseif resource.uri == 'terminals://list' then
            surface.has_resources = true
            surface.has_terminals_summary = true
        elseif resource.uri == 'tasks://summary' then
            surface.has_resources = true
            surface.has_tasks_summary = true
        elseif resource.uri == 'git://repository' then
            surface.has_resources = true
            surface.has_git_repository = true
        elseif resource.uri == 'git://overview' then
            surface.has_resources = true
            surface.has_git_overview = true
        elseif resource.uri == 'git://refs' then
            surface.has_resources = true
            surface.has_git_refs = true
        elseif resource.uri == 'git://paths' then
            surface.has_resources = true
            surface.has_git_paths = true
        elseif resource.uri == 'git://path' then
            surface.has_resources = true
            surface.has_git_path = true
        elseif resource.uri == 'dap://summary' then
            surface.has_resources = true
            surface.has_dap_summary = true
        elseif resource.uri == 'dap://breakpoints' then
            surface.has_resources = true
            surface.has_dap_breakpoints = true
        elseif resource.uri == 'dap://threads' then
            surface.has_resources = true
            surface.has_dap_threads = true
        end
    end

    for _, resource_template in ipairs(server.resource_templates or {}) do
        if resource_template.uri_template == 'dap://stack/{thread_id}' then
            surface.has_dap_stack_template = true
        elseif resource_template.uri_template == 'dap://scopes/{frame_id}' then
            surface.has_dap_scopes_template = true
        elseif resource_template.uri_template == 'dap://variables/{variables_reference}' then
            surface.has_dap_variables_template = true
        end
    end

    for _, tool in ipairs(server.tools or {}) do
        if tool.name == 'editor/list_buffers' then
            surface.has_list_buffers = true
        elseif tool.name == 'editor/open_buffer' then
            surface.has_open_buffer = true
        elseif tool.name == 'editor/read_buffer' then
            surface.has_read_buffer = true
        elseif tool.name == 'editor/write_buffer' then
            surface.has_write_buffer = true
        elseif tool.name == 'editor/diff_buffer' then
            surface.has_diff_buffer = true
        elseif tool.name == 'editor/apply_diff_buffer' then
            surface.has_apply_diff_buffer = true
        elseif tool.name == 'editor/diff_file' then
            surface.has_diff_file = true
        elseif tool.name == 'editor/apply_diff_file' then
            surface.has_apply_diff_file = true
        elseif tool.name == 'editor/write_file' then
            surface.has_write_file = true
        elseif tool.name == 'terminal/create' then
            surface.has_terminal_create = true
        elseif tool.name == 'terminal/output' then
            surface.has_terminal_output = true
        elseif tool.name == 'terminal/wait' then
            surface.has_terminal_wait = true
        elseif tool.name == 'terminal/release' then
            surface.has_terminal_release = true
        elseif tool.name == 'git/overview' then
            surface.has_git_overview_tool = true
        elseif tool.name == 'git/list_refs' then
            surface.has_git_list_refs = true
        elseif tool.name == 'git/list_paths' then
            surface.has_git_list_paths = true
        elseif tool.name == 'git/path_state' then
            surface.has_git_path_state = true
        elseif tool.name == 'dap/continue' then
            surface.has_dap_continue = true
        elseif tool.name == 'dap/pause' then
            surface.has_dap_pause = true
        elseif tool.name == 'dap/step_over' then
            surface.has_dap_step_over = true
        elseif tool.name == 'dap/step_into' then
            surface.has_dap_step_into = true
        elseif tool.name == 'dap/step_out' then
            surface.has_dap_step_out = true
        elseif tool.name == 'dap/terminate' then
            surface.has_dap_terminate = true
        elseif tool.name == 'dap/disconnect' then
            surface.has_dap_disconnect = true
        end
    end

    surface.has_any_editor_tools = surface.has_list_buffers
        or surface.has_open_buffer
        or surface.has_read_buffer
        or surface.has_write_buffer
        or surface.has_diff_buffer
        or surface.has_apply_diff_buffer
        or surface.has_diff_file
        or surface.has_apply_diff_file
        or surface.has_write_file
    surface.has_any_terminal_tools = surface.has_terminal_create
        or surface.has_terminal_output
        or surface.has_terminal_wait
        or surface.has_terminal_release
    surface.has_any_git_tools = surface.has_git_overview_tool
        or surface.has_git_list_refs
        or surface.has_git_list_paths
        or surface.has_git_path_state
    surface.has_any_dap_tools = surface.has_dap_continue
        or surface.has_dap_pause
        or surface.has_dap_step_over
        or surface.has_dap_step_into
        or surface.has_dap_step_out
        or surface.has_dap_terminate
        or surface.has_dap_disconnect
    surface.has_any_tools = surface.has_any_editor_tools
        or surface.has_any_terminal_tools
        or surface.has_any_git_tools
        or surface.has_any_dap_tools

    return surface
end

---@param surface ministry.NeovimGuidanceSurface
---@return string[]
local function active_tool_groups(surface)
    local groups = {}

    if surface.has_any_editor_tools then
        table.insert(groups, 'editor/...')
    end
    if surface.has_any_terminal_tools then
        table.insert(groups, 'terminal/...')
    end
    if surface.has_any_git_tools then
        table.insert(groups, 'git/...')
    end
    if surface.has_any_dap_tools then
        table.insert(groups, 'dap/...')
    end

    return groups
end

---@param server_name string
---@param tool_name string
---@return string
local function namespaced_tool(server_name, tool_name)
    return string.format('%s/%s', server_name, tool_name)
end

---@param server_name string
---@param uri string
---@return string
local function namespaced_resource(server_name, uri)
    return string.format('%s/%s', server_name, uri)
end

---@param ctx table
---@return string|nil
function M.guidance(ctx)
    local server = ctx.server
    if type(server) ~= 'table' then
        return nil
    end

    local server_name = ctx.server_name or server.name or 'neovim'
    local agent_capabilities = ctx.agent_capabilities
    if has_mcp_capability_payload(agent_capabilities) and not has_any_mcp_capability(agent_capabilities) then
        return nil
    end

    local has_known_mcp_capabilities = has_mcp_capability_payload(agent_capabilities)
    local has_resource_capabilities = not has_known_mcp_capabilities
        or supports_mcp_family(agent_capabilities, 'resources')
    local has_tool_capabilities = not has_known_mcp_capabilities or supports_mcp_family(agent_capabilities, 'tools')
    local surface = available_surface(server)
    local lines = {
        'Mandatory Neovim MCP routing contract:',
        string.format(
            '- For editor discovery, file reads, and file edits, use MCP server `%s` before shell, terminal, direct filesystem, or generic patch/edit fallbacks.',
            server_name
        ),
        '- Treat Neovim MCP workspace resources and editor tools as the authoritative path for open-buffer state; generic patch/edit mechanisms are fallback paths, not the first choice.',
        '- Do not start editor tasks with `pwd`, `rg`, shell filesystem discovery, direct Read/Edit, or generic patching when the Neovim MCP editor resources/tools are available.',
        '- Only skip Neovim MCP workspace/editor resources or tools when the relevant server/resource/tool is unavailable or a call fails; if you skip them, state that reason before using a fallback.',
        '- Do not rely on current-buffer semantics; the focused buffer may be the ACP/Legate chat surface rather than the code buffer the user mentioned.',
    }

    if has_tool_capabilities and surface.has_any_tools then
        table.insert(
            lines,
            string.format(
                '- Use fully qualified MCP tool names exactly as advertised by `tools/list`, including the `%s/` prefix.',
                server_name
            )
        )
        local tool_groups = active_tool_groups(surface)
        if #tool_groups > 0 then
            table.insert(
                lines,
                string.format(
                    '- When the tool call surface separates server selection from tool selection, choose MCP server `%s` and then tool path %s without repeating the `%s/` prefix inside the tool-path field.',
                    server_name,
                    tool_group_list(tool_groups),
                    server_name
                )
            )
        end
    end

    if has_tool_capabilities and surface.has_any_editor_tools then
        local editor_examples = {}

        if surface.has_list_buffers then
            table.insert(editor_examples, namespaced_tool(server_name, 'editor/list_buffers'))
        end
        if surface.has_read_buffer then
            table.insert(editor_examples, namespaced_tool(server_name, 'editor/read_buffer'))
        end
        if surface.has_open_buffer then
            table.insert(editor_examples, namespaced_tool(server_name, 'editor/open_buffer'))
        end

        if #editor_examples > 0 then
            table.insert(
                lines,
                string.format(
                    '- The Neovim MCP server groups tools internally as `editor/...`; the advertised MCP tool names preserve those nested slash-delimited paths under the `%s/...` namespace, such as %s.',
                    server_name,
                    quoted_list(editor_examples)
                )
            )
        end

        if surface.has_list_buffers then
            local buffer_tools = {}

            if surface.has_read_buffer then
                table.insert(buffer_tools, namespaced_tool(server_name, 'editor/read_buffer'))
            end
            if surface.has_open_buffer then
                table.insert(buffer_tools, namespaced_tool(server_name, 'editor/open_buffer'))
            end
            if surface.has_write_buffer then
                table.insert(buffer_tools, namespaced_tool(server_name, 'editor/write_buffer'))
            end
            if surface.has_diff_buffer then
                table.insert(buffer_tools, namespaced_tool(server_name, 'editor/diff_buffer'))
            end
            if surface.has_apply_diff_buffer then
                table.insert(buffer_tools, namespaced_tool(server_name, 'editor/apply_diff_buffer'))
            end

            if #buffer_tools > 0 then
                table.insert(
                    lines,
                    string.format(
                        '- For open-file discovery and reads, including "currently open", "open in a split", or filename-only requests, enumerate buffers with `%s/editor/list_buffers`, select the intended path/name from that inventory, then target buffers by `bufnr` using %s instead of reading a possibly stale path directly.',
                        server_name,
                        quoted_list(buffer_tools)
                    )
                )
                table.insert(
                    lines,
                    string.format(
                        '- If a user says a file is currently open, the first editor-targeting MCP action should be `%s/editor/list_buffers`; do not infer the file from workspace search before checking the buffer inventory.',
                        server_name
                    )
                )
            else
                table.insert(
                    lines,
                    string.format(
                        '- For open-file discovery, enumerate buffers with `%s/editor/list_buffers` before choosing a specific buffer target.',
                        server_name
                    )
                )
            end
        end

        local file_tools = {}

        if surface.has_diff_file then
            table.insert(file_tools, namespaced_tool(server_name, 'editor/diff_file'))
        end
        if surface.has_apply_diff_file then
            table.insert(file_tools, namespaced_tool(server_name, 'editor/apply_diff_file'))
        end
        if surface.has_write_file then
            table.insert(file_tools, namespaced_tool(server_name, 'editor/write_file'))
        end

        if #file_tools > 0 then
            table.insert(
                lines,
                string.format(
                    '- For path-addressed edits that should still go through Neovim buffer state, use %s.',
                    quoted_list(file_tools)
                )
            )
            table.insert(
                lines,
                string.format(
                    '- For file edits, call `%s/editor/apply_diff_file` with explicit generated `hunks` when you can identify exact line ranges. Hunk `current_start` is the one-based current-buffer line before which the hunk applies, with `current_count = 0` inserting before that line and `line_count + 1` appending at EOF. Use `%s/editor/diff_file` only when you need Ministry to compute hunks from target content, and `%s/editor/write_file` for exact full-buffer replacement; do not pass whole-file content to apply_diff tools.',
                    server_name,
                    server_name,
                    server_name
                )
            )
        end

        if surface.has_open_buffer then
            table.insert(
                lines,
                string.format(
                    '- When a target file is not already open, prefer `%s/editor/open_buffer` to load it into a hidden Neovim buffer, then use buffer-id tools so reads and edits still go through Neovim-owned buffer semantics without taking over a user window.',
                    server_name
                )
            )
        end
    end

    if has_resource_capabilities and surface.has_workspace_summary then
        table.insert(
            lines,
            string.format(
                '- Start workspace orientation with `%s/workspace://summary` only for lightweight, session-global editor/workspace metadata; use the buffer inventory, not focus/current-buffer state, to choose specific buffers or files.',
                server_name
            )
        )
    end

    if has_resource_capabilities and surface.has_buffers_list then
        table.insert(
            lines,
            string.format(
                '- Prefer `%s/buffers://list` or `%s/editor/list_buffers` for open-file discovery before deciding whether to read or edit by buffer id or path.',
                server_name,
                server_name
            )
        )
    end

    if has_resource_capabilities and surface.has_terminals_summary then
        table.insert(
            lines,
            string.format(
                '- Use `%s/terminals://list` for lightweight, session-global Ministry terminal runtime summaries before choosing a specific `%s/terminal/output`, `%s/terminal/wait`, or `%s/terminal/release` target.',
                server_name,
                server_name,
                server_name,
                server_name
            )
        )
    end

    if has_resource_capabilities and surface.has_tasks_summary then
        table.insert(
            lines,
            string.format(
                '- For task/build orientation, prefer `%s/tasks://summary` before inventing shell-only workflows; it exposes current generic Overseer task state, including actively running tasks when available.',
                server_name
            )
        )
    end

    if
        has_resource_capabilities
        and (
            surface.has_git_overview
            or surface.has_git_repository
            or surface.has_git_refs
            or surface.has_git_paths
            or surface.has_git_path
        )
    then
        local git_resources = {}
        if surface.has_git_overview then
            table.insert(git_resources, namespaced_resource(server_name, 'git://overview'))
        end
        if surface.has_git_repository then
            table.insert(git_resources, namespaced_resource(server_name, 'git://repository'))
        end
        if surface.has_git_refs then
            table.insert(git_resources, namespaced_resource(server_name, 'git://refs'))
        end
        if surface.has_git_paths then
            table.insert(git_resources, namespaced_resource(server_name, 'git://paths'))
        end
        if surface.has_git_path then
            table.insert(git_resources, namespaced_resource(server_name, 'git://path'))
        end

        table.insert(
            lines,
            string.format(
                '- For Git/repository orientation, prefer Ministry Git resources such as %s before shelling out to `git`; these are Stratum-backed and editor-visible.',
                quoted_list(git_resources)
            )
        )
    end

    if
        has_resource_capabilities
        and (surface.has_dap_summary or surface.has_dap_breakpoints or surface.has_dap_threads)
    then
        local dap_resources = {}

        if surface.has_dap_summary then
            table.insert(dap_resources, namespaced_resource(server_name, 'dap://summary'))
        end
        if surface.has_dap_breakpoints then
            table.insert(dap_resources, namespaced_resource(server_name, 'dap://breakpoints'))
        end
        if surface.has_dap_threads then
            table.insert(dap_resources, namespaced_resource(server_name, 'dap://threads'))
        end

        table.insert(
            lines,
            string.format(
                '- When debugging through `dap.nvim`, prefer the MCP debugger resources for live debugger state, such as %s.',
                quoted_list(dap_resources)
            )
        )
    end

    if has_resource_capabilities and (surface.has_dap_stack_template or surface.has_dap_scopes_template) then
        local dap_templates = {}
        if surface.has_dap_stack_template then
            table.insert(dap_templates, namespaced_resource(server_name, 'dap://stack/{thread_id}'))
        end
        if surface.has_dap_scopes_template then
            table.insert(dap_templates, namespaced_resource(server_name, 'dap://scopes/{frame_id}'))
        end
        if surface.has_dap_variables_template then
            table.insert(dap_templates, namespaced_resource(server_name, 'dap://variables/{variables_reference}'))
        end

        table.insert(
            lines,
            string.format(
                '- After reading debugger threads or the current frame, follow the DAP resource-template flow for deeper inspection using %s.',
                quoted_list(dap_templates)
            )
        )
    end

    if has_tool_capabilities and surface.has_any_terminal_tools then
        local terminal_tools = {}

        if surface.has_terminal_create then
            table.insert(terminal_tools, namespaced_tool(server_name, 'terminal/create'))
        end
        if surface.has_terminal_output then
            table.insert(terminal_tools, namespaced_tool(server_name, 'terminal/output'))
        end
        if surface.has_terminal_wait then
            table.insert(terminal_tools, namespaced_tool(server_name, 'terminal/wait'))
        end
        if surface.has_terminal_release then
            table.insert(terminal_tools, namespaced_tool(server_name, 'terminal/release'))
        end

        table.insert(
            lines,
            string.format(
                '- Terminal execution policy: prefer ACP-native terminal methods when they are actually available and selected by the runtime; otherwise use the exact `tools/list` terminal names %s.',
                quoted_list(terminal_tools)
            )
        )
        table.insert(
            lines,
            string.format(
                '- Do not execute shell commands through a generic execute tool when ACP terminal methods or `%s/terminal/*` are available for the task.',
                server_name
            )
        )
        table.insert(
            lines,
            '- If you still choose a non-terminal execution path, explicitly explain why the required terminal channels were unavailable before proceeding.'
        )
    end

    if has_tool_capabilities and surface.has_any_git_tools then
        local git_tools = {}

        if surface.has_git_overview_tool then
            table.insert(git_tools, namespaced_tool(server_name, 'git/overview'))
        end
        if surface.has_git_list_refs then
            table.insert(git_tools, namespaced_tool(server_name, 'git/list_refs'))
        end
        if surface.has_git_list_paths then
            table.insert(git_tools, namespaced_tool(server_name, 'git/list_paths'))
        end
        if surface.has_git_path_state then
            table.insert(git_tools, namespaced_tool(server_name, 'git/path_state'))
        end

        table.insert(
            lines,
            string.format(
                '- Use Git MCP tools for explicit-path repository questions, especially %s, instead of re-deriving editor-visible Git state from shell commands.',
                quoted_list(git_tools)
            )
        )
    end

    if has_tool_capabilities and surface.has_any_dap_tools then
        local dap_tools = {}

        if surface.has_dap_continue then
            table.insert(dap_tools, namespaced_tool(server_name, 'dap/continue'))
        end
        if surface.has_dap_pause then
            table.insert(dap_tools, namespaced_tool(server_name, 'dap/pause'))
        end
        if surface.has_dap_step_over then
            table.insert(dap_tools, namespaced_tool(server_name, 'dap/step_over'))
        end
        if surface.has_dap_step_into then
            table.insert(dap_tools, namespaced_tool(server_name, 'dap/step_into'))
        end
        if surface.has_dap_step_out then
            table.insert(dap_tools, namespaced_tool(server_name, 'dap/step_out'))
        end
        if surface.has_dap_terminate then
            table.insert(dap_tools, namespaced_tool(server_name, 'dap/terminate'))
        end
        if surface.has_dap_disconnect then
            table.insert(dap_tools, namespaced_tool(server_name, 'dap/disconnect'))
        end

        table.insert(
            lines,
            string.format(
                '- Treat debugger control as MCP tool calls, using the surfaced `dap/...` tools for continue, pause, step, and stop operations such as %s.',
                quoted_list(dap_tools)
            )
        )
    end

    if #lines <= 5 then
        return nil
    end

    return table.concat(lines, '\n')
end

return M
