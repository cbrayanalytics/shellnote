vim.g.mapleader = " "
local messages = {}
vim.notify = function(message) table.insert(messages, message) end
local function position() return vim.fn.expand("%:t") .. ":" .. vim.fn.line(".") end
-- Each picker runs asynchronously, so wait until the expected note and line are showing.
local function run_until(command, match, expected)
  vim.env.TEST_PICKER_MATCH = match
  vim.cmd(command)
  vim.wait(5000, function() return position() == expected end, 20)
  return position()
end
vim.api.nvim_create_autocmd("VimEnter", { callback = function()
  local results = {}
  for _, key in ipairs({ "<leader>nn", "<leader>nf", "<leader>nt", "<leader>nr" }) do
    table.insert(results, key .. "=" .. tostring(vim.fn.maparg(key, "n") ~= ""))
  end
  table.insert(results, run_until("Notes", "Second", "second.md:1"))
  table.insert(results, run_until("NoteFind needle", "needle", "first.md:3"))
  table.insert(results, run_until("NoteTags work", "Second", "second.md:2"))
  vim.cmd("NoteRun echo hi")
  table.insert(results, table.concat(vim.api.nvim_buf_get_lines(0, 2, 5, false), "|"))
  vim.cmd("NoteFind absent")
  vim.wait(5000, function() return #messages > 0 end, 20)
  table.insert(results, messages[1] or "")
  -- Loosened last, since pickers reject unsafe notes. It must be tightened again on exit.
  vim.fn.setfperm(vim.fn.expand("%:p"), "rw-r--r--")
  vim.fn.writefile(results, vim.env.TEST_NVIM_RESULT)
  vim.cmd("qa!")
end })
