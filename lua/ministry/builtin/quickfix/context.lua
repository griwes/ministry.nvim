local M = {}

local function normalize_path(bufnr, filename)
    if type(filename) == 'string' and filename ~= '' then
        return vim.fs.normalize(filename)
    end

    if type(bufnr) == 'number' and bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name ~= '' then
            return vim.fs.normalize(name)
        end
    end

    return nil
end

local function normalize_item(item)
    if type(item) ~= 'table' then
        return nil
    end

    return {
        bufnr = type(item.bufnr) == 'number' and item.bufnr or nil,
        path = normalize_path(item.bufnr, item.filename),
        lnum = type(item.lnum) == 'number' and item.lnum or nil,
        end_lnum = type(item.end_lnum) == 'number' and item.end_lnum or nil,
        col = type(item.col) == 'number' and item.col or nil,
        end_col = type(item.end_col) == 'number' and item.end_col or nil,
        vcol = item.vcol == true,
        nr = type(item.nr) == 'number' and item.nr or nil,
        type = type(item.type) == 'string' and item.type or nil,
        text = type(item.text) == 'string' and item.text or nil,
        module = type(item.module) == 'string' and item.module or nil,
        pattern = type(item.pattern) == 'string' and item.pattern or nil,
        valid = item.valid ~= false,
    }
end

local function normalize_list(info, kind)
    info = type(info) == 'table' and info or {}
    local items = {}

    for _, item in ipairs(info.items or {}) do
        local normalized = normalize_item(item)
        if normalized ~= nil then
            table.insert(items, normalized)
        end
    end

    local current_index = type(info.idx) == 'number' and info.idx or 0
    local current_item = current_index >= 1 and current_index <= #items and items[current_index] or nil

    return {
        kind = kind,
        title = type(info.title) == 'string' and info.title or '',
        context = type(info.context) == 'table' and vim.deepcopy(info.context) or nil,
        id = type(info.id) == 'number' and info.id or nil,
        size = #items,
        idx = current_index,
        has_current = current_item ~= nil,
        current_item = current_item,
        items = items,
    }
end

function M.quickfix_summary()
    return normalize_list(vim.fn.getqflist({ all = 1 }), 'quickfix')
end

function M.location_list_summary()
    return normalize_list(vim.fn.getloclist(0, { all = 1 }), 'location_list')
end

return M
