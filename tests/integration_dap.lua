local function fail(message)
    io.stderr:write(tostring(message) .. '\n')
    vim.cmd('cquit 1')
end

local function assert_truthy(value, message)
    if not value then
        fail(message or 'assertion failed')
    end
end

local function wait_until(predicate, timeout_ms, message)
    local ok = vim.wait(timeout_ms or 15000, predicate, 20)
    assert_truthy(ok, message or 'timed out')
end

local function read_json_resource(plugin, uri, id)
    local response = plugin.handle_request('resources/read', { uri = uri }, id, {})
    assert_truthy(response ~= nil and response.error == nil, 'resource read failed for ' .. uri)
    return vim.json.decode(response.result.contents[1].text)
end

local function read_json_template(plugin, uri, id)
    local response = plugin.handle_request('resources/templates/read', { uri = uri }, id, {})
    assert_truthy(response ~= nil and response.error == nil, 'resource template read failed for ' .. uri)
    return vim.json.decode(response.result.contents[1].text)
end

local fixture_dir = vim.fn.tempname()
vim.fn.mkdir(fixture_dir, 'p')

local ok, err = pcall(function()
    local plugin = require('ministry')
    local dap = require('dap')

    require('tests.helpers.ministry').reset(plugin)
    require('tests.helpers.ministry').setup(plugin)

    local fixture_path = fixture_dir .. '/sample_debuggee.py'
    vim.fn.writefile({
        'def main():',
        '    answer = 40',
        '    answer += 2',
        '    print(answer)',
        '',
        'if __name__ == "__main__":',
        '    main()',
    }, fixture_path)

    local debugpy = vim.fn.exepath('debugpy')
    assert_truthy(debugpy ~= nil and debugpy ~= '', 'debugpy executable not found')

    local python = '/usr/bin/python3'
    assert_truthy(vim.fn.executable(python) == 1, 'system python3 executable not found')

    local session_finished = false
    dap.listeners.before.event_terminated.ministry_integration = function()
        session_finished = true
    end
    dap.listeners.before.event_exited.ministry_integration = function()
        session_finished = true
    end

    dap.adapters.ministry_debugpy = {
        type = 'executable',
        command = python,
        args = { '-m', 'debugpy.adapter' },
    }

    dap.configurations.python = {
        {
            type = 'ministry_debugpy',
            request = 'launch',
            name = 'Ministry DAP Integration',
            program = fixture_path,
            console = 'integratedTerminal',
            pythonPath = python,
        },
    }

    vim.cmd('edit ' .. vim.fn.fnameescape(fixture_path))
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    dap.toggle_breakpoint()
    dap.run(dap.configurations.python[1])

    wait_until(function()
        local payload = read_json_resource(plugin, 'neovim/dap://summary', 1)
        return payload.active == true and payload.session ~= nil and payload.session.current_frame ~= nil
    end, 20000, 'dap session did not reach a stopped frame')

    local summary = read_json_resource(plugin, 'neovim/dap://summary', 2)
    assert_truthy(summary.active == true, 'dap summary was not active')
    assert_truthy(summary.session.current_frame.source.path == vim.fs.normalize(fixture_path), 'unexpected frame path')

    local breakpoints = read_json_resource(plugin, 'neovim/dap://breakpoints', 3)
    assert_truthy(#(breakpoints.breakpoints or {}) >= 1, 'expected at least one breakpoint')
    assert_truthy(breakpoints.breakpoints[1].path == vim.fs.normalize(fixture_path), 'unexpected breakpoint path')
    assert_truthy(breakpoints.breakpoints[1].line == 4, 'unexpected breakpoint line')

    local threads = read_json_resource(plugin, 'neovim/dap://threads', 4)
    assert_truthy(#(threads.threads or {}) >= 1, 'expected at least one thread')
    local thread_id = threads.stopped_thread_id or threads.threads[1].id
    assert_truthy(type(thread_id) == 'number', 'expected numeric thread id')

    local stack = read_json_template(plugin, 'neovim/dap://stack/' .. thread_id, 5)
    assert_truthy(#(stack.stack_frames or {}) >= 1, 'expected at least one stack frame')
    local frame_id = stack.stack_frames[1].id
    assert_truthy(stack.stack_frames[1].source.path == vim.fs.normalize(fixture_path), 'unexpected stack frame path')

    local scopes = read_json_template(plugin, 'neovim/dap://scopes/' .. frame_id, 6)
    assert_truthy(#(scopes.scopes or {}) >= 1, 'expected at least one scope')
    local variables_reference = scopes.scopes[1].variables_reference
    assert_truthy(type(variables_reference) == 'number', 'expected numeric variables reference')

    local variables = read_json_template(plugin, 'neovim/dap://variables/' .. variables_reference, 7)
    local found_answer = false
    for _, variable in ipairs(variables.variables or {}) do
        if variable.name == 'answer' then
            found_answer = true
            assert_truthy(tostring(variable.value) == '42', 'unexpected answer variable value')
        end
    end
    assert_truthy(found_answer, 'expected answer variable in scope')

    local continue_result, continue_err = plugin.call_tool('neovim/dap/continue', {}, {})
    assert_truthy(continue_err == nil, 'continue tool failed')
    assert_truthy(continue_result.ok == true, 'continue tool did not report success')

    wait_until(function()
        return session_finished
    end, 20000, 'dap session did not terminate after continue')

    dap.listeners.before.event_terminated.ministry_integration = nil
    dap.listeners.before.event_exited.ministry_integration = nil
    pcall(dap.disconnect, { terminateDebuggee = true })
    pcall(dap.terminate)
    dap.adapters.ministry_debugpy = nil
    dap.configurations.python = nil
    dap.clear_breakpoints()
end)

vim.fn.delete(fixture_dir, 'rf')

if not ok then
    fail(err)
end

vim.cmd('cquit 0')
