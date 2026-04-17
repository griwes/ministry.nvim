vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'

if vim.fn.isdirectory(lazypath) == 0 then
    vim.fn.system({
        'git',
        'clone',
        '--filter=blob:none',
        'https://github.com/folke/lazy.nvim.git',
        '--branch=stable',
        lazypath,
    })
end

vim.opt.runtimepath:prepend(lazypath)

require('lazy').setup({
    { dir = vim.fn.getcwd(), lazy = false },
    { 'nvim-lua/plenary.nvim', lazy = false },
    { 'andythigpen/nvim-coverage', lazy = false },
    { 'stevearc/conform.nvim', lazy = false },
    { 'williamboman/mason.nvim', lazy = false },
    { 'mfussenegger/nvim-dap', lazy = false },
    { 'mfussenegger/nvim-lint', lazy = false },
    { 'stevearc/overseer.nvim', lazy = false },
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
