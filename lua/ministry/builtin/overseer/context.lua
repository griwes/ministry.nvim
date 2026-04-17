local M = {}

local function load_overseer()
    local ok, overseer = pcall(require, 'overseer')
    return ok and overseer or nil
end

local function normalize_command(cmd)
    if type(cmd) == 'table' then
        return vim.deepcopy(cmd)
    end

    if type(cmd) == 'string' and cmd ~= '' then
        return { cmd }
    end

    return nil
end

local function normalize_task(task)
    if type(task) ~= 'table' then
        return nil
    end

    local metadata = type(task.metadata) == 'table' and vim.deepcopy(task.metadata) or nil
    local id = type(task.id) == 'number' and task.id or nil
    local name = type(task.name) == 'string' and task.name or nil
    local status = type(task.status) == 'string' and task.status or nil
    local result = type(task.result) == 'string' and task.result or nil
    local cmd = normalize_command(task.cmd)
    local cwd = type(task.cwd) == 'string' and vim.fs.normalize(task.cwd) or nil
    local strategy = type(task.strategy) == 'string' and task.strategy or nil
    local running = type(task.is_running) == 'function' and task:is_running() or status == 'RUNNING'
    local complete = type(task.is_complete) == 'function' and task:is_complete() or (status ~= 'PENDING' and status ~= 'RUNNING')

    return {
        id = id,
        name = name,
        status = status,
        result = result,
        is_running = running,
        is_complete = complete,
        cmd = cmd,
        cwd = cwd,
        strategy = strategy,
        metadata = metadata,
    }
end

function M.summary()
    local overseer = load_overseer()
    if overseer == nil or type(overseer.list_tasks) ~= 'function' then
        return {
            available = false,
            active_task_count = 0,
            has_active_tasks = false,
            status_counts = {},
            active_tasks = {},
            tasks = {},
        }
    end

    local tasks = {}
    local status_counts = {}
    local active_tasks = {}
    for _, task in ipairs(overseer.list_tasks() or {}) do
        local normalized = normalize_task(task)
        if normalized ~= nil then
            table.insert(tasks, normalized)
            if normalized.status ~= nil then
                status_counts[normalized.status] = (status_counts[normalized.status] or 0) + 1
            end
            if normalized.is_running then
                table.insert(active_tasks, normalized)
            end
        end
    end

    table.sort(tasks, function(left, right)
        if left.is_running ~= right.is_running then
            return left.is_running
        end
        if left.name ~= right.name then
            return tostring(left.name) < tostring(right.name)
        end

        return (left.id or -1) < (right.id or -1)
    end)

    table.sort(active_tasks, function(left, right)
        if left.name ~= right.name then
            return tostring(left.name) < tostring(right.name)
        end

        return (left.id or -1) < (right.id or -1)
    end)

    return {
        available = true,
        active_task_count = #active_tasks,
        has_active_tasks = #active_tasks > 0,
        status_counts = status_counts,
        active_tasks = active_tasks,
        tasks = tasks,
    }
end

return M
