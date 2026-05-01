local config = require('ministry.core.config')

local M = {}

---@param value any
---@return string[]|nil
local function list_or_single(value)
    if value == nil then
        return nil
    end
    if type(value) == 'string' then
        return { value }
    end
    if type(value) == 'table' and vim.islist(value) then
        return vim.deepcopy(value)
    end
    return nil
end

---@param path string
---@return table?, string?
local function read_json(path)
    if vim.fn.filereadable(path) ~= 1 then
        return nil, nil
    end

    local text = table.concat(vim.fn.readfile(path), '\n')
    if text == '' then
        return {}, nil
    end

    local ok, decoded = pcall(vim.json.decode, text)
    if not ok then
        return nil, tostring(decoded)
    end

    return decoded, nil
end

---@param path string
---@param source_name string
---@param name string
---@param spec table
---@return ministry.ExternalServerSpec?
local function normalize_server(path, source_name, name, spec)
    if type(name) ~= 'string' or name == '' or type(spec) ~= 'table' then
        return nil
    end

    local normalized = {
        name = name,
        source = {
            kind = 'config',
            name = source_name,
            path = path,
        },
    }

    if type(spec.url) == 'string' and spec.url ~= '' then
        normalized.transport = 'http'
        normalized.url = spec.url
        normalized.headers = type(spec.headers) == 'table' and vim.deepcopy(spec.headers) or nil
        return normalized
    end

    if type(spec.command) == 'string' and spec.command ~= '' then
        normalized.transport = 'stdio'
        normalized.command = spec.command
        normalized.args = type(spec.args) == 'table' and vim.deepcopy(spec.args) or {}
        normalized.env = type(spec.env) == 'table' and vim.deepcopy(spec.env) or {}
        normalized.cwd = type(spec.cwd) == 'string' and spec.cwd ~= '' and spec.cwd or nil
        return normalized
    end

    return nil
end

---@param path string
---@return ministry.ExternalServerSpec[], table[]
function M.discover_file(path)
    local decoded, err = read_json(path)
    local servers = {}
    local errors = {}

    if err ~= nil then
        table.insert(errors, {
            path = path,
            message = err,
        })
        return servers, errors
    end

    if decoded == nil then
        return servers, errors
    end

    local maps = {
        mcpServers = decoded.mcpServers,
        servers = decoded.servers,
    }

    for source_name, source_servers in pairs(maps) do
        if type(source_servers) == 'table' then
            for name, spec in pairs(source_servers) do
                local normalized = normalize_server(path, source_name, name, spec)
                if normalized ~= nil then
                    table.insert(servers, normalized)
                end
            end
        end
    end

    table.sort(servers, function(left, right)
        return left.name < right.name
    end)

    return servers, errors
end

---@param start_dir string
---@return string[]
local function workspace_paths(start_dir)
    local applied = config.get().external.workspace
    if not applied.enabled then
        return {}
    end

    local seen = {}
    local paths = {}
    local dir = vim.fs.normalize(start_dir)

    while dir ~= nil and dir ~= '' do
        for _, relative in ipairs(applied.look_for or {}) do
            local path = vim.fs.joinpath(dir, relative)
            if not seen[path] and vim.fn.filereadable(path) == 1 then
                seen[path] = true
                table.insert(paths, path)
            end
        end

        local parent = vim.fs.dirname(dir)
        if parent == nil or parent == dir then
            break
        end
        dir = parent
    end

    local ordered = {}
    for index = #paths, 1, -1 do
        table.insert(ordered, paths[index])
    end

    return ordered
end

---@param opts? { cwd?: string }
---@return ministry.ExternalServerSpec[], table[]
function M.discover(opts)
    local applied = config.get().external
    local paths = {}
    local seen = {}

    local configured_paths = list_or_single(applied.config)
    if configured_paths ~= nil then
        for _, path in ipairs(configured_paths) do
            local expanded = vim.fn.expand(path)
            if not seen[expanded] then
                seen[expanded] = true
                table.insert(paths, expanded)
            end
        end
    else
        local default_path = vim.fs.joinpath(vim.fn.stdpath('config'), 'mcphub', 'servers.json')
        seen[default_path] = true
        table.insert(paths, default_path)
    end

    for _, path in ipairs(workspace_paths(opts ~= nil and opts.cwd or vim.fn.getcwd())) do
        if not seen[path] then
            seen[path] = true
            table.insert(paths, path)
        end
    end

    local servers = {}
    local errors = {}
    local by_name = {}

    for _, path in ipairs(paths) do
        local discovered, file_errors = M.discover_file(path)
        vim.list_extend(errors, file_errors)
        for _, server in ipairs(discovered) do
            by_name[server.name] = server
        end
    end

    for _, server in pairs(by_name) do
        table.insert(servers, server)
    end

    table.sort(servers, function(left, right)
        return left.name < right.name
    end)

    return servers, errors
end

return M
