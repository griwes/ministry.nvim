local approval = require('ministry.approval.policy')
local config = require('ministry.core.config')

local M = {}

local ns = vim.api.nvim_create_namespace('ministry-servers')
local augroup = vim.api.nvim_create_augroup('MinistryServersUi', { clear = false })

---@class ministry.ServerUiTarget
---@field server string
---@field method? string
---@field methods? string[]

---@class ministry.ServerUiHighlight
---@field line integer 1-indexed line number
---@field group string highlight group name

---@class ministry.ServerUiSpan
---@field line integer 1-indexed line number
---@field col integer 0-indexed byte column
---@field end_col integer 0-indexed end byte column
---@field group string highlight group name

---@class ministry.ServerUiFold
---@field start integer
---@field finish integer
---@field id string

---@class ministry.ServerUiView
---@field lines string[]
---@field targets table<integer, ministry.ServerUiTarget>
---@field highlights ministry.ServerUiHighlight[]
---@field spans ministry.ServerUiSpan[]
---@field folds ministry.ServerUiFold[]
---@field tree_start integer
---@field tree_end integer

---@class ministry.ServerUiTreeNode
---@field children table<string, ministry.ServerUiTreeNode>
---@field item? table
---@field key? string

local COLUMN_NAME_WIDTH = 36
local COLUMN_POLICY_WIDTH = 24
local COLUMN_KIND_WIDTH = 16
local FLOAT_HORIZONTAL_PADDING = ' '

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

---@param text string
---@param width integer
---@return string
local function pad(text, width)
    local length = vim.fn.strdisplaywidth(text)
    if length >= width then
        return text
    end
    return text .. string.rep(' ', width - length)
end

---@param marker string
---@param name string
---@param policy string?
---@param kind string?
---@param detail string?
---@return string
local function row(marker, name, policy, kind, detail)
    return table.concat({
        pad(marker .. ' ' .. name, COLUMN_NAME_WIDTH),
        pad(policy or '', COLUMN_POLICY_WIDTH),
        pad(kind or '', COLUMN_KIND_WIDTH),
        detail or '',
    }, '  ')
end

---@param text string
---@return string
local function padded_line(text)
    return FLOAT_HORIZONTAL_PADDING .. text .. FLOAT_HORIZONTAL_PADDING
end

---@param status ministry.ServerStatus
---@return string
local function endpoint(status)
    return status.url or status.command or '-'
end

---@param status ministry.ServerStatus
---@return string
local function source_label(status)
    local source = status.source or {}
    local detail = source.path or source.name or '-'
    return string.format('%s:%s', source.kind or '-', detail)
end

---@param status ministry.ServerStatus
---@return string
local function state_label(status)
    if status.error ~= nil and status.error ~= '' then
        return 'error'
    end
    return status.state or '-'
end

---@param items table[]?
---@param key string
---@return table<string, table>
local function descriptions_by_key(items, key)
    local descriptions = {}
    for _, item in ipairs(items or {}) do
        if type(item) == 'table' and type(item[key]) == 'string' then
            descriptions[item[key]] = item
        end
    end
    return descriptions
end

---@param status ministry.ServerStatus
---@param group 'tools'|'resources'|'resource_templates'|'prompts'
---@param path string|string[]
---@return string?
local function namespace_description(status, group, path)
    local namespaces = status.namespaces or {}
    local descriptions = namespaces[group] or {}
    local key = type(path) == 'table' and table.concat(path, '/') or path
    return descriptions[key] or descriptions['/' .. key]
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
local function method_policy_label(status, method)
    local policy = status.policy or {}
    local tools = policy.tools or {}
    local decision = tools[method] or policy.default or '-'
    local suffix = tools[method] == nil and policy.default ~= nil and ' inherited' or ''
    return string.format('%s%s', decision, suffix)
end

---@param decision string?
---@return string
local function policy_highlight(decision)
    if decision == 'allow' then
        return 'MinistryServersAllow'
    end
    if decision == 'reject' then
        return 'MinistryServersReject'
    end
    return 'MinistryServersAsk'
end

---@param view ministry.ServerUiView
---@param line_number integer
---@param line string
local function add_policy_count_spans(view, line_number, line)
    for _, decision in ipairs({ 'allow', 'reject', 'ask' }) do
        local start = 1
        while true do
            local first, last = line:find(decision .. '=%d+', start)
            if first == nil then
                break
            end

            table.insert(view.spans, {
                line = line_number,
                col = first - 1,
                end_col = last,
                group = policy_highlight(decision),
            })
            start = last + 1
        end
    end
end

---@param text string
---@param group string
---@return table[]
local function policy_count_chunks(text, group)
    local chunks = {}
    local cursor = 1

    while cursor <= #text do
        local best_first, best_last, best_group
        for _, decision in ipairs({ 'allow', 'reject', 'ask' }) do
            local first, last = text:find(decision .. '=%d+', cursor)
            if first ~= nil and (best_first == nil or first < best_first) then
                best_first = first
                best_last = last
                best_group = policy_highlight(decision)
            end
        end

        if best_first == nil then
            table.insert(chunks, { text:sub(cursor), group })
            break
        end

        if best_first > cursor then
            table.insert(chunks, { text:sub(cursor, best_first - 1), group })
        end
        table.insert(chunks, { text:sub(best_first, best_last), best_group })
        cursor = best_last + 1
    end

    return chunks
end

---@param view ministry.ServerUiView
---@param line string
---@param group? string
---@param target? ministry.ServerUiTarget
---@param marker? string
local function add_line(view, line, group, target, marker)
    line = padded_line(line)
    table.insert(view.lines, line)
    local line_number = #view.lines
    add_policy_count_spans(view, line_number, line)
    if group ~= nil then
        table.insert(view.highlights, { line = line_number, group = group })
    end
    if target ~= nil then
        view.targets[line_number] = target
    end
end

---@param view ministry.ServerUiView
---@param start integer
---@param id string
local function add_fold(view, start, id)
    local finish = #view.lines
    if finish > start then
        table.insert(view.folds, { start = start, finish = finish, id = id })
    end
end

---@param value string
---@return string[]
local function split_key(value)
    local scheme, rest = value:match('^([^:]+)://(.*)$')
    local raw_parts
    if scheme ~= nil then
        raw_parts = { scheme }
        vim.list_extend(raw_parts, vim.split(rest, '/', { plain = true }))
    else
        raw_parts = vim.split(value, '/', { plain = true })
    end

    local parts = {}
    for _, part in ipairs(raw_parts) do
        if part ~= '' then
            table.insert(parts, part)
        end
    end
    return parts
end

---@param keys string[]
---@return ministry.ServerUiTreeNode
local function make_tree(keys)
    local root = { children = {} }
    for _, key in ipairs(keys) do
        local parts = split_key(key)
        if #parts == 0 then
            parts = { key }
        end

        local node = root
        for _, part in ipairs(parts) do
            node.children[part] = node.children[part] or { children = {} }
            node = node.children[part]
        end
        node.key = key
    end
    return root
end

---@param children table<string, ministry.ServerUiTreeNode>
---@return string[]
local function sorted_child_names(children)
    local names = {}
    for name in pairs(children) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

---@param node ministry.ServerUiTreeNode
---@return string[]
local function collect_keys(node)
    local keys = {}
    if node.key ~= nil then
        table.insert(keys, node.key)
    end
    for _, name in ipairs(sorted_child_names(node.children)) do
        vim.list_extend(keys, collect_keys(node.children[name]))
    end
    return keys
end

---@param status ministry.ServerStatus
---@param methods string[]
---@return string
local function subtree_policy_label(status, methods)
    local tools = (status.policy or {}).tools or {}
    local counts = {
        allow = 0,
        reject = 0,
        ask = 0,
        inherited = 0,
    }

    for _, method in ipairs(methods) do
        local decision = tools[method]
        if decision == nil then
            counts.inherited = counts.inherited + 1
        elseif counts[decision] ~= nil then
            counts[decision] = counts[decision] + 1
        end
    end

    local parts = {}
    for _, decision in ipairs({ 'allow', 'reject', 'ask' }) do
        if counts[decision] > 0 then
            table.insert(parts, string.format('%s=%d', decision, counts[decision]))
        end
    end
    return table.concat(parts, ' ')
end

---@param count integer
---@param singular string
---@return string
local function count_label(count, singular)
    return count == 1 and string.format('1 %s', singular) or string.format('%d %ss', count, singular)
end

---@param view ministry.ServerUiView
---@param status ministry.ServerStatus
---@param node ministry.ServerUiTreeNode
---@param prefix string
---@param path string[]
---@param descriptions table<string, table>
local function render_tool_tree(view, status, node, prefix, path, descriptions)
    for _, name in ipairs(sorted_child_names(node.children)) do
        local child = node.children[name]
        local next_path = vim.deepcopy(path)
        table.insert(next_path, name)
        local next_prefix = prefix .. '  '

        if child.key ~= nil and vim.tbl_isempty(child.children) then
            local item = descriptions[child.key] or {}
            local decision = (status.policy or {}).tools and (status.policy or {}).tools[child.key]
            add_line(
                view,
                row(
                    prefix .. '•',
                    name,
                    method_policy_label(status, child.key),
                    'tool',
                    item.description or 'persisted policy entry'
                ),
                policy_highlight(decision or (status.policy or {}).default),
                { server = status.name, method = child.key },
                '•'
            )
        else
            local methods = collect_keys(child)
            local item = child.key ~= nil and descriptions[child.key] or nil
            local policy = child.key ~= nil and method_policy_label(status, child.key)
                or subtree_policy_label(status, methods)
            local detail = item ~= nil and item.description
                or namespace_description(status, 'tools', next_path)
                or string.format('tool namespace with %s', count_label(#methods, 'method'))
            local target = {
                server = status.name,
                method = child.key,
                methods = methods,
            }

            add_line(
                view,
                row(prefix .. '▾', name, policy, 'namespace', detail),
                'MinistryServersNamespace',
                target,
                '▾'
            )
            local start = #view.lines
            render_tool_tree(view, status, child, next_prefix, next_path, descriptions)
            add_fold(view, start, status.name .. ':tools:' .. table.concat(next_path, '/'))
        end
    end
end

---@param view ministry.ServerUiView
---@param status ministry.ServerStatus
local function render_tools(view, status)
    local methods = method_names(status)
    if #methods == 0 then
        add_line(view, row('  •', 'Tools', '', 'tools', 'none advertised'), 'MinistryServersMuted', nil, '•')
        return
    end

    add_line(
        view,
        row(
            '  ▾',
            'Tools',
            subtree_policy_label(status, methods),
            'tools',
            namespace_description(status, 'tools', '') or 'advertised tools and activation policies'
        ),
        'MinistryServersSection',
        { server = status.name, methods = methods },
        '▾'
    )
    local start = #view.lines
    local descriptions = descriptions_by_key(status.tools, 'name')
    descriptions.__activate = { description = 'start the stdio MCP server process' }
    render_tool_tree(view, status, make_tree(methods), '    ', {}, descriptions)
    add_fold(view, start, status.name .. ':tools')
end

---@param item table
---@param key_field string
---@return string
local function item_key(item, key_field)
    return item[key_field] or item.name or '-'
end

---@param view ministry.ServerUiView
---@param status ministry.ServerStatus
---@param section_id string
---@param namespace_group 'resources'|'resource_templates'|'prompts'
---@param section_kind string
---@param singular string
---@param key_field string
---@param items table[]?
local function render_item_tree(view, status, section_id, namespace_group, section_kind, singular, key_field, items)
    local keys = {}
    local descriptions = {}
    for _, item in ipairs(items or {}) do
        local key = item_key(item, key_field)
        if key ~= '-' then
            table.insert(keys, key)
            descriptions[key] = item
        end
    end
    table.sort(keys)

    local title = section_id:gsub('^%l', string.upper)
    if #keys == 0 then
        add_line(view, row('  •', title, '', section_kind, 'none advertised'), 'MinistryServersMuted', nil, '•')
        return
    end

    add_line(
        view,
        row(
            '  ▾',
            title,
            '',
            section_kind,
            namespace_description(status, namespace_group, '') or count_label(#keys, singular)
        ),
        'MinistryServersSection',
        nil,
        '▾'
    )
    local start = #view.lines

    local function render_children(node, prefix, path)
        for _, name in ipairs(sorted_child_names(node.children)) do
            local child = node.children[name]
            local next_path = vim.deepcopy(path)
            table.insert(next_path, name)
            if child.key ~= nil and vim.tbl_isempty(child.children) then
                local item = descriptions[child.key] or {}
                local kind = namespace_group == 'resource_templates' and name:match('^{.+}$') ~= nil and 'parameter'
                    or singular
                add_line(
                    view,
                    row(prefix .. '•', name, '', kind, item.description or child.key),
                    'MinistryServersMuted',
                    nil,
                    '•'
                )
            else
                local child_keys = collect_keys(child)
                add_line(
                    view,
                    row(
                        prefix .. '▾',
                        name,
                        '',
                        'namespace',
                        namespace_description(status, namespace_group, next_path)
                            or string.format('%s namespace', count_label(#child_keys, singular))
                    ),
                    'MinistryServersNamespace',
                    nil,
                    '▾'
                )
                local child_start = #view.lines
                render_children(child, prefix .. '  ', next_path)
                add_fold(view, child_start, status.name .. ':' .. section_id .. ':' .. table.concat(next_path, '/'))
            end
        end
    end

    render_children(make_tree(keys), '    ', {})
    add_fold(view, start, status.name .. ':' .. section_id)
end

---@param view ministry.ServerUiView
---@param status ministry.ServerStatus
local function render_server(view, status)
    local policy = status.policy or {}
    local state = state_label(status)
    local group = state == 'error' and 'MinistryServersError' or 'MinistryServersServer'
    add_line(
        view,
        row(
            '▾',
            status.name,
            policy.default or '-',
            status.transport or '-',
            string.format('%s via %s', source_label(status), endpoint(status))
        ),
        group,
        { server = status.name },
        '▾'
    )
    local start = #view.lines
    add_line(view, row('  •', 'Source', '', 'meta', source_label(status)), 'MinistryServersMuted', nil, '•')
    add_line(view, row('  •', 'Endpoint', '', 'meta', endpoint(status)), 'MinistryServersMuted', nil, '•')
    if status.args ~= nil and #status.args > 0 then
        add_line(view, row('  •', 'Args', '', 'meta', display(status.args)), 'MinistryServersMuted', nil, '•')
    end
    if status.error ~= nil and status.error ~= '' then
        add_line(view, row('  •', 'Error', '', 'error', status.error), 'MinistryServersError', nil, '•')
    end
    add_line(
        view,
        row(
            '  •',
            'Policy',
            policy.default or '-',
            'policy',
            string.format('allow=%s reject=%s ask=%s', policy.allow or 0, policy.reject or 0, policy.ask or 0)
        ),
        policy_highlight(policy.default),
        nil,
        '•'
    )
    render_tools(view, status)
    render_item_tree(view, status, 'resources', 'resources', 'resources', 'resource', 'uri', status.resources)
    render_item_tree(
        view,
        status,
        'resource templates',
        'resource_templates',
        'templates',
        'template',
        'uri_template',
        status.resource_templates
    )
    render_item_tree(view, status, 'prompts', 'prompts', 'prompts', 'prompt', 'name', status.prompts)
    add_fold(view, start, status.name)
end

---@param statuses ministry.ServerStatus[]
---@return ministry.ServerUiView
function M.render_view(statuses)
    local view = {
        lines = {},
        targets = {},
        highlights = {},
        spans = {},
        folds = {},
    }

    add_line(view, 'Ministry MCP Servers', 'MinistryServersTitle')
    add_line(view, 'ga allow   gr reject   gk ask   R refresh   zo open   zc close   q close', 'MinistryServersHelp')
    add_line(view, '')
    add_line(view, row('TREE', 'NAME', 'POLICY', 'KIND / STATE', 'DESCRIPTION'), 'MinistryServersHeader')
    add_line(view, '')
    view.tree_start = #view.lines + 1

    for index, status in ipairs(statuses) do
        render_server(view, status)
        if index ~= #statuses then
            add_line(view, '')
        end
    end
    view.tree_end = #view.lines

    if #statuses == 0 then
        add_line(view, 'No MCP servers configured.', 'MinistryServersMuted')
        view.tree_start = #view.lines
        view.tree_end = #view.lines
    end

    return view
end

---@param statuses ministry.ServerStatus[]
---@return string[]
function M.render_lines(statuses)
    return M.render_view(statuses).lines
end

---@param statuses ministry.ServerStatus[]
---@param line integer
---@return ministry.ServerUiTarget?
local function target_at_line(statuses, line)
    return M.render_view(statuses).targets[line]
end

local function define_highlights()
    local highlights = {
        MinistryServersTitle = { link = 'Title' },
        MinistryServersHelp = { link = 'Comment' },
        MinistryServersHeader = { link = 'Directory' },
        MinistryServersServer = { link = 'Function' },
        MinistryServersSection = { link = 'Identifier' },
        MinistryServersNamespace = { link = 'Type' },
        MinistryServersMuted = { link = 'Comment' },
        MinistryServersAllow = { link = 'DiagnosticOk' },
        MinistryServersReject = { link = 'DiagnosticError' },
        MinistryServersAsk = { link = 'DiagnosticWarn' },
        MinistryServersError = { link = 'DiagnosticError' },
    }

    for name, spec in pairs(highlights) do
        vim.api.nvim_set_hl(0, name, spec)
    end
end

---@param view ministry.ServerUiView
---@param line integer
---@return string
local function line_highlight(view, line)
    for _, highlight in ipairs(view.highlights) do
        if highlight.line == line then
            return highlight.group
        end
    end
    return 'Folded'
end

---@param buf integer
---@param view ministry.ServerUiView
local function apply_view(buf, view)
    vim.b[buf].ministry_server_view = view
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, view.lines)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

    for _, highlight in ipairs(view.highlights) do
        vim.api.nvim_buf_set_extmark(buf, ns, highlight.line - 1, 0, {
            line_hl_group = highlight.group,
        })
    end
    for _, span in ipairs(view.spans) do
        vim.api.nvim_buf_set_extmark(buf, ns, span.line - 1, span.col, {
            end_col = span.end_col,
            hl_group = span.group,
            priority = 20,
        })
    end

    vim.bo[buf].modifiable = false
end

---@param win integer
---@param view ministry.ServerUiView
local function clamp_cursor_to_tree(win, view)
    if not vim.api.nvim_win_is_valid(win) then
        return
    end

    local row_number, column = unpack(vim.api.nvim_win_get_cursor(win))
    if row_number < view.tree_start then
        vim.api.nvim_win_set_cursor(win, { view.tree_start, column })
    elseif row_number > view.tree_end then
        vim.api.nvim_win_set_cursor(win, { view.tree_end, column })
    end
end

---@param win integer
---@param view ministry.ServerUiView
---@param previous? table<string, boolean>
---@return table<string, boolean>
local function fold_state(win, view, previous)
    local state = {}
    if win == nil or not vim.api.nvim_win_is_valid(win) then
        return state
    end

    vim.api.nvim_win_call(win, function()
        for _, fold in ipairs(view.folds) do
            local closed = vim.fn.foldclosed(fold.start)
            if closed == -1 then
                state[fold.id] = false
            elseif closed == fold.start then
                state[fold.id] = true
            elseif previous ~= nil and previous[fold.id] ~= nil then
                state[fold.id] = previous[fold.id]
            else
                state[fold.id] = true
            end
        end
    end)
    return state
end

---@param win integer
---@param view ministry.ServerUiView
---@param state? table<string, boolean>
local function apply_folds(win, view, state)
    vim.api.nvim_win_call(win, function()
        vim.wo[win].foldmethod = 'manual'
        vim.wo[win].foldenable = false
        vim.wo[win].foldlevel = 99
        vim.cmd('silent! normal! zE')

        local folds = vim.deepcopy(view.folds)
        table.sort(folds, function(left, right)
            local left_size = left.finish - left.start
            local right_size = right.finish - right.start
            if left_size == right_size then
                return left.start > right.start
            end
            return left_size < right_size
        end)

        for _, fold in ipairs(folds) do
            vim.cmd(string.format('silent! %d,%dfold', fold.start, fold.finish))
        end

        vim.wo[win].foldenable = true
        vim.wo[win].foldlevel = 99

        for _, fold in ipairs(view.folds) do
            if state == nil or state[fold.id] == nil or state[fold.id] then
                vim.cmd(string.format('silent! %dfoldclose', fold.start))
            else
                vim.cmd(string.format('silent! %dfoldopen', fold.start))
            end
        end
    end)
end

---@param buf integer
---@return table[]
function _G.MinistryServersFoldText(buf)
    local view = vim.b[buf].ministry_server_view
    local line = vim.fn.getline(vim.v.foldstart)
    local closed = line:gsub('▾', '▸', 1)
    local before, marker, after = closed:match('^(.-)(▸)(.*)$')
    if type(view) ~= 'table' then
        local chunks = {
            { before or '', 'MinistryServersMuted' },
            { marker or '', 'MinistryServersMuted' },
        }
        vim.list_extend(chunks, policy_count_chunks(after or closed, 'MinistryServersMuted'))
        return chunks
    end

    local group = line_highlight(view, vim.v.foldstart)
    local chunks = {
        { before or '', line_highlight(view, vim.v.foldstart) },
        { marker or '', group },
    }
    vim.list_extend(chunks, policy_count_chunks(after or closed, group))
    return chunks
end

---@param value number
---@param total integer
---@param fallback integer
---@param min integer
---@return integer
local function resolve_dimension(value, total, fallback, min)
    local available = math.max(1, total - 2)
    local resolved = fallback
    if value > 0 and value <= 1 then
        resolved = math.floor(total * value)
    elseif value > 1 then
        resolved = math.floor(value)
    end

    return math.max(math.min(min, available), math.min(available, resolved))
end

---@return table
local function float_config()
    local ui = config.get().ui or {}
    local columns = vim.o.columns
    local lines = vim.o.lines
    local width = resolve_dimension(ui.width or 0.8, columns, math.floor(columns * 0.8), 72)
    local height = resolve_dimension(ui.height or 0.8, lines, math.floor(lines * 0.8), 14)

    return {
        relative = 'editor',
        width = width,
        height = height,
        col = math.floor((columns - width) / 2),
        row = math.floor((lines - height) / 2),
        style = 'minimal',
        border = ui.border or 'rounded',
        title = ' Ministry ',
        title_pos = 'center',
    }
end

---@param win integer
local function hide_fold_fillchars(win)
    vim.api.nvim_win_call(win, function()
        vim.opt_local.fillchars:append({
            fold = ' ',
            foldsep = ' ',
        })
    end)
end

---@param target ministry.ServerUiTarget
---@param decision ministry.ApprovalDecision
local function set_target_policy(target, decision)
    if target.methods ~= nil then
        for _, method in ipairs(target.methods) do
            approval.set(target.server, method, decision)
        end
        return
    end
    approval.set(target.server, target.method, decision)
end

---@param statuses ministry.ServerStatus[]
local function open_buffer(statuses)
    define_highlights()

    local current_statuses = statuses
    local current_view = M.render_view(current_statuses)
    local current_fold_state = nil
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'ministry-servers'

    local win = vim.api.nvim_open_win(buf, true, float_config())
    vim.wo[win].cursorline = true
    vim.wo[win].wrap = false
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = 'no'
    vim.wo[win].foldcolumn = '0'
    vim.wo[win].statuscolumn = ''
    vim.wo[win].foldtext = string.format('v:lua.MinistryServersFoldText(%d)', buf)
    vim.wo[win].winhl = 'Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual,Folded:NormalFloat'
    hide_fold_fillchars(win)

    apply_view(buf, current_view)
    apply_folds(win, current_view)
    current_fold_state = fold_state(win, current_view)
    clamp_cursor_to_tree(win, current_view)

    local function refresh(opts)
        local row_number = vim.api.nvim_win_get_cursor(win)[1]
        local previous_state = opts ~= nil and opts.preserve_folds and fold_state(win, current_view, current_fold_state)
            or nil
        current_statuses = require('ministry').list_server_statuses()
        current_view = M.render_view(current_statuses)
        apply_view(buf, current_view)
        apply_folds(win, current_view, previous_state)
        current_fold_state = fold_state(win, current_view, previous_state)
        vim.api.nvim_win_set_cursor(win, { math.min(row_number, #current_view.lines), 0 })
        clamp_cursor_to_tree(win, current_view)
    end

    vim.api.nvim_create_autocmd('CursorMoved', {
        group = augroup,
        buffer = buf,
        callback = function()
            if vim.api.nvim_get_current_win() == win then
                clamp_cursor_to_tree(win, current_view)
            end
        end,
    })

    local function set_policy(decision)
        local row_number = vim.api.nvim_win_get_cursor(win)[1]
        local target = current_view.targets[row_number]
        if target == nil then
            return
        end
        set_target_policy(target, decision)
        refresh({ preserve_folds = true })
    end

    vim.keymap.set('n', 'ga', function()
        set_policy('allow')
    end, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'gr', function()
        set_policy('reject')
    end, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'gk', function()
        set_policy('ask')
    end, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'R', function()
        refresh({ preserve_folds = true })
    end, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'q', function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, nowait = true })
    vim.keymap.set('n', '<Esc>', function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, nowait = true })
end

---@param statuses ministry.ServerStatus[]
function M.open(statuses)
    open_buffer(statuses)
end

M._target_at_line = target_at_line

return M
