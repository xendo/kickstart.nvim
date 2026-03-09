### 2025-12-08 11:28:57
**File**: `init.lua:152`

```lua
vim.o.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
```

**Note**:
This is my note

This is it

---
### 2025-12-08 11:30:07
**File**: `init.lua:172`

```lua
-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
```

**Note**:
new note

---
