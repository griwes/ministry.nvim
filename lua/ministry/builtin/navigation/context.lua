local M = {}

local local_mark_names = {}
local global_mark_names = {}

do
    for code = string.byte('a'), string.byte('z') do
        table.insert(local_mark_names, string.char(code))
    end
    for code = string.byte('A'), string.byte('Z') do
        table.insert(global_mark_names, string.char(code))
    end
    for code = string.byte('0'), string.byte('9') do
        table.insert(global_mark_names, string.char(code))
    end
end

local function normalize_buffer_path(bufnr)
    if type(bufnr) ~= 'number' or bufnr <= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
        return nil
    end

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == '' then
        return nil
    end

    return vim.fs.normalize(name)
end

local function normalize_local_mark(name, current_buffer)
    local mark = vim.api.nvim_buf_get_mark(0, name)
    if type(mark) ~= 'table' or type(mark[1]) ~= 'number' or mark[1] == 0 then
        return nil
    end

    return {
        mark = name,
        path = current_buffer,
        line = mark[1],
        column = mark[2],
    }
end

local function normalize_global_mark(name)
    local mark = vim.fn.getcharpos("'" .. name)
    if type(mark) ~= 'table' or mark[1] == 0 then
        return nil
    end

    local bufnr = type(mark[1]) == 'number' and mark[1] or nil
    local path = normalize_buffer_path(bufnr)
    if path == nil then
        return nil
    end

    return {
        mark = name,
        path = path,
        line = mark[2],
        column = mark[3] - 1,
    }
end

local function collect_local_marks(current_buffer)
    local marks = {}

    for _, name in ipairs(local_mark_names) do
        local normalized = normalize_local_mark(name, current_buffer)
        if normalized ~= nil then
            table.insert(marks, normalized)
        end
    end
    return marks
end

local function collect_global_marks()
    local marks = {}

    for _, name in ipairs(global_mark_names) do
        local normalized = normalize_global_mark(name)
        if normalized ~= nil then
            table.insert(marks, normalized)
        end
    end

    table.sort(marks, function(left, right)
        if left.path == right.path then
            if left.line == right.line then
                return left.mark < right.mark
            end
            return left.line < right.line
        end
        return left.path < right.path
    end)

    return marks
end

function M.marks_summary()
    local current_buffer = normalize_buffer_path(vim.api.nvim_get_current_buf())
    return {
        current_buffer = current_buffer,
        local_marks = current_buffer ~= nil and collect_local_marks(current_buffer) or {},
        global_marks = collect_global_marks(),
    }
end

return M
