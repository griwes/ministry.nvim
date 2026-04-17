local M = {}

local function load_registry()
    local ok, registry = pcall(require, 'mason-registry')
    return ok and registry or nil
end

function M.inventory()
    local registry = load_registry()
    if registry == nil or type(registry.get_installed_packages) ~= 'function' then
        return {
            available = false,
            packages = {},
        }
    end

    local packages = {}
    for _, package in ipairs(registry.get_installed_packages() or {}) do
        local name = nil

        if type(package) == 'table' then
            if type(package.name) == 'string' then
                name = package.name
            elseif type(package.get_name) == 'function' then
                local ok, value = pcall(package.get_name, package)
                if ok and type(value) == 'string' then
                    name = value
                end
            end
        end

        if name ~= nil and name ~= '' then
            table.insert(packages, {
                name = name,
            })
        end
    end

    table.sort(packages, function(left, right)
        return left.name < right.name
    end)

    return {
        available = true,
        packages = packages,
    }
end

return M
