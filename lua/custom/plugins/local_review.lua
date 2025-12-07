
-- This file implements a local code review feature.
-- It maps <leader>rn in visual mode to save the selected code and a note to review_notes.md.

vim.keymap.set('v', '<leader>rn', function()
  -- Escape to Normal mode to update the '< and '> marks
  local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  vim.api.nvim_feedkeys(esc, 'x', false)

  -- Use vim.schedule to ensure the mode change has processed before reading marks
  vim.schedule(function()
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    
    -- If end_line is less than start_line, swap them
    if end_line < start_line then
        start_line, end_line = end_line, start_line
    end

    local code_lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    local filename = vim.fn.expand('%:.')
    local filetype = vim.bo.filetype
    local current_win = vim.api.nvim_get_current_win()
    local win_height = vim.api.nvim_win_get_height(current_win)
    local cursor_winline = vim.fn.winline()
    
    -- Determine position: if cursor is in top half, show at bottom, else top
    local float_row
    local height = math.floor(win_height * 0.4)
    
    if cursor_winline < (win_height / 2) then
      -- Cursor is in top half, place window at bottom
      float_row = win_height - height - 1
    else
      -- Cursor is in bottom half, place window at top
      float_row = 1
    end

    -- Create a scratch buffer for the note
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'markdown'
    vim.bo[buf].buftype = 'acwrite' -- Allows writing with :w
    vim.api.nvim_buf_set_name(buf, "ReviewNote-" .. os.time() .. ".md")
    
    -- Calculate window size
    local width = math.floor(vim.o.columns * 0.8)
    local col = math.floor((vim.o.columns - width) / 2)
    
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      width = width,
      height = height,
      row = float_row,
      col = col,
      style = 'minimal',
      border = 'rounded',
      title = ' Review Note (:w to save, :q to close) ',
      title_pos = 'center'
    })
    
    vim.cmd('startinsert')
    
    -- Define the save function attached to BufWriteCmd
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = buf,
      callback = function()
        local note_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        
        -- Check if note is effectively empty
        local has_content = false
        for _, line in ipairs(note_lines) do
          if line:match("%S") then
            has_content = true
            break
          end
        end
        
        if not has_content then
          print("Note empty, not saved.")
          vim.bo[buf].modified = false
          return
        end

        local note_file = vim.fn.getcwd() .. '/review_notes.md'
        local f = io.open(note_file, "a")
        if f then
          f:write("### " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
          f:write("**File**: `" .. filename .. ":" .. start_line .. "`\n\n")
          
          f:write("```" .. (filetype or "") .. "\n")
          for _, line in ipairs(code_lines) do
            f:write(line .. "\n")
          end
          f:write("```\n\n")

          f:write("**Note**:\n")
          for _, line in ipairs(note_lines) do
            f:write(line .. "\n")
          end
          f:write("\n")
          
          f:write("---" .. "\n\n")
          f:close()
          print("Saved note to " .. note_file)
          vim.bo[buf].modified = false
        else
          print("Failed to open " .. note_file)
        end
      end
    })
  end)
end, { desc = '[R]eview [N]ote' })

return {}
