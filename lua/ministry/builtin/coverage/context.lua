local M = {}

local function load_report()
    local ok, report = pcall(require, 'coverage.report')
    return ok and report or nil
end

local function normalize_files(report_data)
    local files = {}

    if type(report_data) ~= 'table' then
        return files
    end

    for _, file in ipairs(report_data.files or {}) do
        if type(file) == 'table' and type(file.filename) == 'string' then
            table.insert(files, {
                filename = vim.fs.normalize(file.filename),
                statements = file.statements,
                missing = file.missing,
                excluded = file.excluded,
                branches = file.branches,
                partial = file.partial,
                coverage = file.coverage,
            })
        end
    end

    table.sort(files, function(left, right)
        return left.filename < right.filename
    end)

    return files
end

function M.summary()
    local report = load_report()
    if report == nil or type(report.is_cached) ~= 'function' or not report.is_cached() then
        return {
            available = false,
            language = nil,
            totals = nil,
            files = {},
        }
    end

    local data = type(report.get) == 'function' and report.get() or nil
    local language = type(report.language) == 'function' and report.language() or nil

    return {
        available = true,
        language = language,
        totals = type(data) == 'table' and type(data.totals) == 'table' and vim.deepcopy(data.totals) or nil,
        files = normalize_files(data),
    }
end

return M
