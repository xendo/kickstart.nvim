-- This file implements a local code review feature.
-- It maps <leader>rn in visual mode to save/edit code review notes.
-- It also parses review_notes.md to display annotations in the editor.

local M = {}
local ns_id = vim.api.nvim_create_namespace('LocalReview')

-- Helper: Parse review_notes.md
-- Returns a table: { ["filename:line"] = { content = "...", header_line_idx = int, end_line_idx = int } }
function M.parse_notes()
  local note_file = vim.fn.getcwd() .. '/review_notes.md'
  local f = io.open(note_file, "r")
  if not f then return {}, {} end

  local lines = {}
  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()

  local notes = {}
  local current_entry = nil
  local state = "idle" -- idle, inside_entry, inside_note

  for i, line in ipairs(lines) do
    if line:match("^%#%#%#") then
      current_entry = { start_idx = i }
      state = "header"
    elseif state == "header" and line:match("^%*%*File%*%*:") then
       -- Extract filename:line from `**File**: `filename:line`
       local file_key = line:match('`([^`]+)`')
       if file_key then
         current_entry.file_key = file_key
         state = "inside_entry"
       end
    elseif state == "inside_entry" and line:match("^%*%*Note%*%*:") then
        current_entry.note_start_idx = i + 1
        state = "inside_note"
        current_entry.note_content = {}
    elseif state == "inside_note" then
        if line:match("^%-%-%-$") then
            -- End of entry
            current_entry.end_idx = i
            -- Save the note
            if current_entry.file_key then
                current_entry.note_text = table.concat(current_entry.note_content, "\n")
                notes[current_entry.file_key] = current_entry
            end
            state = "idle"
            current_entry = nil
        else
            table.insert(current_entry.note_content, line)
        end
    end
  end
  
  return notes, lines
end

-- Helper: Refresh annotations for a specific buffer
function M.refresh_annotations(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  
  local notes, _ = M.parse_notes()
  -- Get the filename relative to CWD to match the key format
  local current_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
  
  for key, note in pairs(notes) do
    -- Match filename and line number from the key (last colon is separator)
    local fname, linestr = key:match("^(.*):(%d+)$")
    
    if fname == current_file and linestr then
       local line = tonumber(linestr) - 1 -- 0-indexed
       -- Sanity check line number
       if line >= 0 and line < vim.api.nvim_buf_line_count(bufnr) then
           -- Truncate note for display
           local display_text = note.note_text:gsub("[\r\n]", " "):gsub("%s+", " "):sub(1, 40)
           if #note.note_text > 40 then display_text = display_text .. "..." end
           
           pcall(vim.api.nvim_buf_set_extmark, bufnr, ns_id, line, 0, {
               virt_text = { { "📝 " .. display_text, "Comment" } },
               virt_text_pos = 'eol',
           })
       end
    end
  end
end

-- Setup Autocommands for Refreshing
local group = vim.api.nvim_create_augroup('LocalReview', { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    pattern = "*",
    callback = function(ev) M.refresh_annotations(ev.buf) end
})

-- The main mapping function
vim.keymap.set('v', '<leader>rn', function()
  -- Escape to Normal mode to update the '< and '> marks
  local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  vim.api.nvim_feedkeys(esc, 'x', false)

  -- Use vim.schedule to ensure the mode change has processed before reading marks
  vim.schedule(function()
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    
    if end_line < start_line then start_line, end_line = end_line, start_line end

    local code_lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    local filename = vim.fn.expand('%:.')
    local file_key = filename .. ":" .. start_line
    local filetype = vim.bo.filetype
    local current_win = vim.api.nvim_get_current_win()
    local original_buf = vim.api.nvim_get_current_buf()

    -- Check for existing note
    local notes, raw_lines = M.parse_notes()
    local existing_note = notes[file_key]
    
    -- Create buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'markdown'
    vim.bo[buf].buftype = 'acwrite'
    vim.api.nvim_buf_set_name(buf, "ReviewNote-" .. os.time() .. ".md")

    -- If existing, populate buffer
    if existing_note then
        local content = existing_note.note_content
        -- Remove trailing empty lines for cleaner editing if desired
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
        print("Editing existing note for " .. file_key)
    end

    -- Create Split
    vim.cmd('belowright split')
    local note_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(note_win, buf)
    vim.api.nvim_win_set_height(note_win, 10)
    vim.api.nvim_set_option_value('winhl', 'Normal:Pmenu,FloatBorder:Pmenu', { win = note_win })
    vim.api.nvim_set_option_value('winbar', ' Review Note (:w to save, :q to close) ', { win = note_win })

    if not existing_note then
        vim.cmd('startinsert')
    end

    -- Cleanup on close
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      callback = function()
        if vim.api.nvim_win_is_valid(current_win) then
            vim.api.nvim_set_current_win(current_win)
        end
        -- Clean close of split if valid
        if vim.api.nvim_win_is_valid(note_win) then
             pcall(vim.api.nvim_win_close, note_win, true)
        end
      end,
    })

    -- Save Logic
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = buf,
      callback = function()
        local note_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local note_file_path = vim.fn.getcwd() .. '/review_notes.md'
        
        -- Re-read file to get fresh indices/content
        local fresh_notes, fresh_raw_lines = M.parse_notes()
        local fresh_existing = fresh_notes[file_key]

        local new_block = {}
        -- If creating NEW note
        if not fresh_existing then
           table.insert(new_block, "### " .. os.date("%Y-%m-%d %H:%M:%S"))
           table.insert(new_block, "**File**: `" .. file_key .. "`")
           table.insert(new_block, "")
           table.insert(new_block, "```" .. (filetype or ""))
           for _, l in ipairs(code_lines) do table.insert(new_block, l) end
           table.insert(new_block, "```")
           table.insert(new_block, "")
           table.insert(new_block, "**Note**:")
           for _, l in ipairs(note_lines) do table.insert(new_block, l) end
           table.insert(new_block, "")
           table.insert(new_block, "---")
           table.insert(new_block, "")
           
           local f = io.open(note_file_path, "a")
           if f then
             f:write(table.concat(new_block, "\n"))
             f:close()
             print("Created new note.")
           end
        else
           -- Updating EXISTING note
           local start_idx = fresh_existing.note_start_idx
           local end_idx = fresh_existing.end_idx
           
           local new_file_lines = {}
           for i = 1, start_idx - 1 do
               table.insert(new_file_lines, fresh_raw_lines[i])
           end
           for _, l in ipairs(note_lines) do table.insert(new_file_lines, l) end
           for i = end_idx, #fresh_raw_lines do
               table.insert(new_file_lines, fresh_raw_lines[i])
           end
           
           local f = io.open(note_file_path, "w")
           if f then
               f:write(table.concat(new_file_lines, "\n") .. "\n")
               f:close()
               print("Updated existing note.")
           end
        end
        
        vim.bo[buf].modified = false
        -- Refresh annotations on the ORIGINAL buffer
        M.refresh_annotations(original_buf)
      end
    })
  end)
end, { desc = '[R]eview [N]ote' })

return {}
