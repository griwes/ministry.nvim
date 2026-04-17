local M = {}

local function load_conform()
    local ok, conform = pcall(require, 'conform')
    return ok and conform or nil
end

function M.summary()
    local conform = load_conform()
    if conform == nil then
        return {
            available = false,
            filetype = vim.bo.filetype,
            formatters = {},
        }
    end

    local filetype = vim.bo.filetype
    local configured = {}
    local by_ft = type(conform.formatters_by_ft) == 'table' and conform.formatters_by_ft[filetype] or nil

    if type(by_ft) == 'table' then
        for _, entry in ipairs(by_ft) do
            if type(entry) == 'string' then
                table.insert(configured, entry)
            elseif type(entry) == 'table' and type(entry.name) == 'string' then
                table.insert(configured, entry.name)
            end
        end
    end

    table.sort(configured)

    return {
        available = true,
        filetype = filetype,
        formatters = configured,
    }
end

return M
