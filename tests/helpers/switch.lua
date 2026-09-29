vim.g.mapleader = " "
vim.api.nvim_create_autocmd("VimEnter", { callback = function()
  local mapped = vim.fn.maparg("<leader>n", "n") ~= ""
  vim.cmd.Notes()
  local switched = vim.wait(5000, function() return vim.fn.expand("%:t") == "second.md" end, 20)
  -- A loosened mode must be tightened again when shellnote regains control.
  vim.fn.setfperm(vim.fn.expand("%:p"), "rw-r--r--")
  vim.fn.writefile({ tostring(mapped), tostring(switched), vim.fn.expand("%:t") }, vim.env.TEST_NVIM_RESULT)
  vim.cmd("qa!")
end })
