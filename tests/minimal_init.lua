vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
local dependency_versions = dofile('tests/dependency_versions.lua')

local function run_git(args)
    local output = vim.fn.system(args)
    if vim.v.shell_error ~= 0 then
        error(table.concat(args, ' ') .. '\n' .. output)
    end
    return output
end

if vim.fn.isdirectory(lazypath) == 0 then
    run_git({
        'git',
        'clone',
        '--filter=blob:none',
        'https://github.com/folke/lazy.nvim.git',
        '--branch=stable',
        lazypath,
    })
end

local lazy_head = vim.trim(run_git({ 'git', '-C', lazypath, 'rev-parse', 'HEAD' }))
if lazy_head ~= dependency_versions.lazy then
    run_git({ 'git', '-C', lazypath, 'checkout', '--force', '--detach', dependency_versions.lazy })
end

vim.opt.runtimepath:prepend(lazypath)

require('lazy').setup({
    { dir = vim.fn.getcwd(), lazy = false },
    { 'nvim-lua/plenary.nvim', commit = dependency_versions.plenary, lazy = false },
    { 'andythigpen/nvim-coverage', commit = dependency_versions.coverage, lazy = false },
    { 'stevearc/conform.nvim', commit = dependency_versions.conform, lazy = false },
    { 'williamboman/mason.nvim', commit = dependency_versions.mason, lazy = false },
    { 'mfussenegger/nvim-dap', commit = dependency_versions.dap, lazy = false },
    { 'mfussenegger/nvim-lint', commit = dependency_versions.lint, lazy = false },
    { 'stevearc/overseer.nvim', commit = dependency_versions.overseer, lazy = false },
}, {
    root = vim.fn.stdpath('data') .. '/lazy',
    lockfile = vim.fn.stdpath('state') .. '/lazy-lock.json',
    headless = {
        process = false,
        log = false,
        task = false,
        colors = false,
    },
})

pcall(require, 'dap')
pcall(require, 'conform')
pcall(require, 'mason')
pcall(require, 'lint')
pcall(require, 'overseer')

local lazy_config_ok, lazy_config = pcall(require, 'lazy.core.config')
if lazy_config_ok and type(lazy_config.options) == 'table' then
    lazy_config.options.headless = vim.tbl_extend('force', {
        process = false,
        log = false,
        task = false,
        colors = false,
    }, lazy_config.options.headless or {})
end
