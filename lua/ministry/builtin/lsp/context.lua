local M = {}

local REQUEST_TIMEOUT_MS = 1000

local function normalize_path(path)
    if type(path) ~= 'string' or path == '' then
        return path
    end

    return vim.fs.normalize(path)
end

local function normalize_uri_path(uri)
    if type(uri) ~= 'string' or uri == '' then
        return nil
    end

    if vim.startswith(uri, 'file://') then
        return normalize_path(vim.uri_to_fname(uri))
    end

    return nil
end

local function buffer_name(bufnr)
    return normalize_path(vim.api.nvim_buf_get_name(bufnr))
end

local function workspace_folders(client)
    local folders = client.workspace_folders or client.config.workspace_folders or {}
    local items = {}

    for _, folder in ipairs(folders) do
        if type(folder) == 'table' and type(folder.uri) == 'string' then
            table.insert(items, {
                name = folder.name,
                uri = folder.uri,
                path = normalize_uri_path(folder.uri),
            })
        end
    end

    return items
end

local function client_summary(client)
    local attached_buffers = {}

    for bufnr, attached in pairs(client.attached_buffers or {}) do
        if attached then
            table.insert(attached_buffers, bufnr)
        end
    end

    table.sort(attached_buffers)

    return {
        id = client.id,
        name = client.name,
        root_dir = normalize_path(client.config.root_dir or client.root_dir),
        workspace_folders = workspace_folders(client),
        attached_buffers = attached_buffers,
    }
end

local function clients(opts)
    local items = {}

    for _, client in ipairs(vim.lsp.get_clients(opts or {})) do
        table.insert(items, client_summary(client))
    end

    table.sort(items, function(left, right)
        return left.id < right.id
    end)

    return items
end

local function severity_name(severity)
    if type(severity) ~= 'number' then
        return nil
    end

    local names = vim.diagnostic.severity

    if severity == names.ERROR then
        return 'error'
    end
    if severity == names.WARN then
        return 'warn'
    end
    if severity == names.INFO then
        return 'info'
    end
    if severity == names.HINT then
        return 'hint'
    end

    return tostring(severity)
end

local function normalize_range(range)
    if type(range) ~= 'table' or type(range.start) ~= 'table' or type(range['end']) ~= 'table' then
        return nil
    end

    return {
        start = {
            line = range.start.line,
            character = range.start.character,
        },
        ['end'] = {
            line = range['end'].line,
            character = range['end'].character,
        },
    }
end

local function normalize_location(item)
    if type(item) ~= 'table' then
        return nil
    end

    if type(item.targetUri) == 'string' then
        return {
            uri = item.targetUri,
            path = normalize_uri_path(item.targetUri),
            range = normalize_range(item.targetRange),
            selection_range = normalize_range(item.targetSelectionRange),
        }
    end

    if type(item.uri) == 'string' then
        return {
            uri = item.uri,
            path = normalize_uri_path(item.uri),
            range = normalize_range(item.range),
        }
    end

    return nil
end

local function normalize_text_edit(edit)
    if type(edit) ~= 'table' then
        return nil
    end

    return {
        range = normalize_range(edit.range),
        new_text = edit.newText,
        annotation_id = edit.annotationId,
    }
end

local function normalize_workspace_edit(edit)
    if type(edit) ~= 'table' then
        return nil
    end

    local changes = {}
    for uri, items in pairs(edit.changes or {}) do
        local normalized_edits = {}
        for _, item in ipairs(items or {}) do
            local normalized = normalize_text_edit(item)
            if normalized ~= nil then
                table.insert(normalized_edits, normalized)
            end
        end

        table.insert(changes, {
            uri = uri,
            path = normalize_uri_path(uri),
            edits = normalized_edits,
        })
    end

    table.sort(changes, function(left, right)
        return tostring(left.uri) < tostring(right.uri)
    end)

    local document_changes = {}
    for _, item in ipairs(edit.documentChanges or {}) do
        if type(item) == 'table' then
            if type(item.kind) == 'string' then
                table.insert(document_changes, {
                    kind = item.kind,
                    uri = item.uri or item.oldUri or item.newUri,
                    old_uri = item.oldUri,
                    new_uri = item.newUri,
                    path = normalize_uri_path(item.uri or item.oldUri or item.newUri),
                    options = item.options,
                    annotation_id = item.annotationId,
                })
            elseif type(item.textDocument) == 'table' and type(item.textDocument.uri) == 'string' then
                local edits = {}
                for _, edit_item in ipairs(item.edits or {}) do
                    local normalized = normalize_text_edit(edit_item)
                    if normalized ~= nil then
                        table.insert(edits, normalized)
                    end
                end

                table.insert(document_changes, {
                    kind = 'textDocumentEdit',
                    uri = item.textDocument.uri,
                    path = normalize_uri_path(item.textDocument.uri),
                    version = item.textDocument.version,
                    edits = edits,
                })
            end
        end
    end

    return {
        changes = changes,
        document_changes = document_changes,
        change_annotations = edit.changeAnnotations,
    }
end

local function normalize_response_error(client_id, client, response)
    if type(response) ~= 'table' then
        return nil
    end

    local err = response.error or response.err
    if err == nil then
        return nil
    end

    if type(err) == 'table' then
        return {
            client_id = client_id,
            client_name = client and client.name or nil,
            code = err.code,
            message = err.message or tostring(err),
        }
    end

    return {
        client_id = client_id,
        client_name = client and client.name or nil,
        message = tostring(err),
    }
end

local function request_error_entry(message, client_id, client_name)
    if message == nil then
        return nil
    end

    return {
        client_id = client_id,
        client_name = client_name,
        message = tostring(message),
    }
end

local function normalize_symbol(item)
    if type(item) ~= 'table' then
        return nil
    end

    if type(item.location) == 'table' then
        return {
            name = item.name,
            kind = item.kind,
            tags = item.tags,
            container_name = item.containerName,
            location = normalize_location(item.location),
        }
    end

    local children = {}
    for _, child in ipairs(item.children or {}) do
        local normalized = normalize_symbol(child)
        if normalized ~= nil then
            table.insert(children, normalized)
        end
    end

    return {
        name = item.name,
        detail = item.detail,
        kind = item.kind,
        tags = item.tags,
        deprecated = item.deprecated,
        range = normalize_range(item.range),
        selection_range = normalize_range(item.selectionRange),
        children = children,
    }
end

local function normalize_diagnostic(item)
    if type(item) ~= 'table' then
        return nil
    end

    local bufnr = item.bufnr
    local path = type(bufnr) == 'number' and vim.api.nvim_buf_is_valid(bufnr) and buffer_name(bufnr) or nil

    return {
        bufnr = bufnr,
        path = path,
        lnum = item.lnum,
        end_lnum = item.end_lnum,
        col = item.col,
        end_col = item.end_col,
        severity = item.severity,
        severity_name = severity_name(item.severity),
        source = item.source,
        code = item.code,
        message = item.message,
    }
end

local function request_params(bufnr, line, character)
    local params = vim.lsp.util.make_text_document_params(bufnr)
    params.position = {
        line = line,
        character = character,
    }

    return params
end

local function normalize_request_result(response)
    if response == nil then
        return {}
    end

    if vim.islist(response) then
        return response
    end

    return { response }
end

local function range_params(bufnr, line, character, end_line, end_character)
    local params = request_params(bufnr, line, character)
    params.range = {
        start = {
            line = line,
            character = character,
        },
        ['end'] = {
            line = end_line or line,
            character = end_character or character,
        },
    }

    return params
end

local function location_request(bufnr, method, params)
    local items = {}
    local responses
    local errors = {}
    local request_err
    responses, request_err = vim.lsp.buf_request_sync(bufnr, method, params, REQUEST_TIMEOUT_MS)
    responses = responses or {}

    local top_level_error = request_error_entry(request_err)
    if top_level_error ~= nil then
        table.insert(errors, top_level_error)
    end

    for client_id, response in pairs(responses) do
        local client = vim.lsp.get_client_by_id(client_id)
        local response_error = normalize_response_error(client_id, client, response)
        if response_error ~= nil then
            table.insert(errors, response_error)
        end

        for _, item in ipairs(normalize_request_result(response.result)) do
            local normalized = normalize_location(item)
            if normalized ~= nil then
                normalized.client_id = client_id
                normalized.client_name = client and client.name or nil
                table.insert(items, normalized)
            end
        end
    end

    table.sort(items, function(left, right)
        if left.path ~= right.path then
            return tostring(left.path) < tostring(right.path)
        end

        local left_line = left.range and left.range.start and left.range.start.line or -1
        local right_line = right.range and right.range.start and right.range.start.line or -1
        if left_line ~= right_line then
            return left_line < right_line
        end

        return (left.client_id or -1) < (right.client_id or -1)
    end)

    table.sort(errors, function(left, right)
        return (left.client_id or -1) < (right.client_id or -1)
    end)

    return items, errors
end

function M.summary()
    local current_bufnr = vim.api.nvim_get_current_buf()

    return {
        current_buffer = {
            bufnr = current_bufnr,
            path = buffer_name(current_bufnr),
        },
        clients = clients(),
        current_buffer_clients = clients({ bufnr = current_bufnr }),
    }
end

---@param bufnr integer
---@return table|nil, table|nil
function M.ensure_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return nil,
            {
                code = -32000,
                message = string.format('Invalid buffer id: %s', tostring(bufnr)),
            }
    end

    return {
        bufnr = bufnr,
        path = buffer_name(bufnr),
        filetype = vim.bo[bufnr].filetype,
    },
        nil
end

---@param bufnr? integer
function M.diagnostics(bufnr)
    local items = {}

    for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
        local normalized = normalize_diagnostic(diagnostic)
        if normalized ~= nil then
            table.insert(items, normalized)
        end
    end

    table.sort(items, function(left, right)
        if left.path ~= right.path then
            return tostring(left.path) < tostring(right.path)
        end
        if left.lnum ~= right.lnum then
            return left.lnum < right.lnum
        end
        return left.col < right.col
    end)

    return items
end

function M.document_symbols(bufnr)
    local items = {}
    local responses
    local errors = {}
    local request_err
    responses, request_err = vim.lsp.buf_request_sync(
        bufnr,
        'textDocument/documentSymbol',
        vim.lsp.util.make_text_document_params(bufnr),
        REQUEST_TIMEOUT_MS
    )
    responses = responses or {}

    local top_level_error = request_error_entry(request_err)
    if top_level_error ~= nil then
        table.insert(errors, top_level_error)
    end

    for client_id, response in pairs(responses) do
        local client = vim.lsp.get_client_by_id(client_id)
        local response_error = normalize_response_error(client_id, client, response)
        if response_error ~= nil then
            table.insert(errors, response_error)
        end
        local symbols = {}

        for _, item in ipairs(normalize_request_result(response.result)) do
            local normalized = normalize_symbol(item)
            if normalized ~= nil then
                table.insert(symbols, normalized)
            end
        end

        table.insert(items, {
            client_id = client_id,
            client_name = client and client.name or nil,
            symbols = symbols,
        })
    end

    table.sort(items, function(left, right)
        return left.client_id < right.client_id
    end)

    table.sort(errors, function(left, right)
        return left.client_id < right.client_id
    end)

    return items, errors
end

function M.workspace_symbols(query)
    local items = {}
    local errors = {}

    for _, client in ipairs(vim.lsp.get_clients()) do
        local ok, response, request_err = pcall(client.request_sync, client, 'workspace/symbol', {
            query = query,
        }, REQUEST_TIMEOUT_MS)

        if not ok then
            table.insert(errors, {
                client_id = client.id,
                client_name = client.name,
                message = tostring(response),
            })
        elseif request_err ~= nil then
            table.insert(errors, request_error_entry(request_err, client.id, client.name))
        elseif response ~= nil then
            local response_error = normalize_response_error(client.id, client, response)
            if response_error ~= nil then
                table.insert(errors, response_error)
            end
        end

        if ok and response and response.result then
            local symbols = {}
            for _, item in ipairs(normalize_request_result(response.result)) do
                local normalized = normalize_symbol(item)
                if normalized ~= nil then
                    table.insert(symbols, normalized)
                end
            end

            table.insert(items, {
                client_id = client.id,
                client_name = client.name,
                symbols = symbols,
            })
        end
    end

    table.sort(items, function(left, right)
        return left.client_id < right.client_id
    end)

    table.sort(errors, function(left, right)
        return left.client_id < right.client_id
    end)

    return items, errors
end

function M.definitions(bufnr, line, character)
    return location_request(bufnr, 'textDocument/definition', request_params(bufnr, line, character))
end

function M.declarations(bufnr, line, character)
    return location_request(bufnr, 'textDocument/declaration', request_params(bufnr, line, character))
end

function M.type_definitions(bufnr, line, character)
    return location_request(bufnr, 'textDocument/typeDefinition', request_params(bufnr, line, character))
end

function M.implementations(bufnr, line, character)
    return location_request(bufnr, 'textDocument/implementation', request_params(bufnr, line, character))
end

function M.references(bufnr, line, character, include_declaration)
    local params = request_params(bufnr, line, character)
    params.context = {
        includeDeclaration = include_declaration == true,
    }

    return location_request(bufnr, 'textDocument/references', params)
end

function M.code_actions(bufnr, line, character, end_line, end_character)
    local params = range_params(bufnr, line, character, end_line, end_character)
    params.context = {
        diagnostics = vim.diagnostic.get(bufnr, { lnum = line }),
    }

    local items = {}
    local responses
    local errors = {}
    local request_err
    responses, request_err = vim.lsp.buf_request_sync(bufnr, 'textDocument/codeAction', params, REQUEST_TIMEOUT_MS)
    responses = responses or {}

    local top_level_error = request_error_entry(request_err)
    if top_level_error ~= nil then
        table.insert(errors, top_level_error)
    end

    for client_id, response in pairs(responses) do
        local client = vim.lsp.get_client_by_id(client_id)
        local response_error = normalize_response_error(client_id, client, response)
        if response_error ~= nil then
            table.insert(errors, response_error)
        end

        for _, item in ipairs(normalize_request_result(response.result)) do
            if type(item) == 'table' then
                table.insert(items, {
                    client_id = client_id,
                    client_name = client and client.name or nil,
                    title = item.title,
                    kind = item.kind,
                    is_preferred = item.isPreferred,
                    disabled = item.disabled,
                    has_edit = item.edit ~= nil,
                    has_command = item.command ~= nil,
                    edit = normalize_workspace_edit(item.edit),
                    command = item.command,
                })
            end
        end
    end

    table.sort(items, function(left, right)
        if left.client_id ~= right.client_id then
            return left.client_id < right.client_id
        end

        return tostring(left.title) < tostring(right.title)
    end)

    table.sort(errors, function(left, right)
        return (left.client_id or -1) < (right.client_id or -1)
    end)

    return items, errors
end

function M.rename(bufnr, line, character, new_name)
    local params = request_params(bufnr, line, character)
    params.newName = new_name

    local edits = {}
    local responses
    local errors = {}
    local request_err
    responses, request_err = vim.lsp.buf_request_sync(bufnr, 'textDocument/rename', params, REQUEST_TIMEOUT_MS)
    responses = responses or {}

    local top_level_error = request_error_entry(request_err)
    if top_level_error ~= nil then
        table.insert(errors, top_level_error)
    end

    for client_id, response in pairs(responses) do
        local client = vim.lsp.get_client_by_id(client_id)
        local response_error = normalize_response_error(client_id, client, response)
        if response_error ~= nil then
            table.insert(errors, response_error)
        end
        if response.result ~= nil then
            table.insert(edits, {
                client_id = client_id,
                client_name = client and client.name or nil,
                workspace_edit = normalize_workspace_edit(response.result),
            })
        end
    end

    table.sort(edits, function(left, right)
        return left.client_id < right.client_id
    end)

    table.sort(errors, function(left, right)
        return left.client_id < right.client_id
    end)

    return edits, errors
end

return M
