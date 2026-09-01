local M = {}

function M.check()
    vim.health.start('ministry.nvim')

    if vim.fn.has('nvim-0.11') == 1 then
        vim.health.ok('Neovim 0.11 or newer')
    else
        vim.health.error('Neovim 0.11 or newer is required')
    end

    local pipe = vim.uv.new_pipe(false)
    if pipe ~= nil and pipe.bind2 ~= nil then
        vim.health.ok('libuv pipe supports filesystem socket binding')
    else
        vim.health.warn('This Neovim build cannot host Ministry filesystem sockets')
    end
    if pipe ~= nil and not pipe:is_closing() then
        pipe:close()
    end

    if vim.fn.executable('socat') == 1 then
        vim.health.ok('socat is available for endpoint bridge commands')
    else
        vim.health.warn('socat is not installed; advertised socket bridge commands will not run')
    end

    local config = require('ministry.core.config').get()
    if config.transport == 'http' and config.http_host ~= '127.0.0.1' and not config.http_token then
        vim.health.error('Non-loopback HTTP transport requires http_token')
    else
        vim.health.ok('Configured transport passes the basic trust-boundary check')
    end
end

return M
