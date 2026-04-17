local M = {}

local function load_lint()
    local ok, lint = pcall(require, 'lint')
    return ok and lint or nil
end

function M.summary()
    local lint = load_lint()
    if lint == nil then
        return {
            available = false,
            filetype = vim.bo.filetype,
            linters = {},
            running = {},
        }
    end

    local filetype = vim.bo.filetype
    local configured = {}
    local by_ft = type(lint.linters_by_ft) == 'table' and lint.linters_by_ft[filetype] or nil

    if type(by_ft) == 'table' then
        for _, entry in ipairs(by_ft) do
            if type(entry) == 'string' then
                table.insert(configured, entry)
            end
        end
    end

    table.sort(configured)

    local running = type(lint.get_running) == 'function' and lint.get_running(0) or {}
    table.sort(running)

    return {
        available = true,
        filetype = filetype,
        linters = configured,
        running = running,
    }
end

return M
