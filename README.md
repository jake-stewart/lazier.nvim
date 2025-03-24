# lazier.nvim
Lazier is a wrapper around [lazy.nvim](https://lazy.folke.io/) and lets you
have lazy loaded plugins without any extra effort.

### Before:
Normally, we define mappings within the `keys` field so that the plugin can
be lazy loaded:

```lua
return {
    "jake-stewart/multicursor.nvim",
    opts = {},
    keys = {
        "<leader>h", function()
            require("multicursor-nvim").prevCursor()
        end,
        "<leader>l", function()
            require("multicursor-nvim").nextCursor()
        end
    }
}
```

### After
With lazier, we define mappings and configuration with normal code and get
lazy loading automatically: 

```lua
return require "lazier" {
    "jake-stewart/multicursor.nvim",
    config = function()
        local mc = require("multicursor-nvim")
        mc.setup()
        vim.keymap.set("n", "<leader>h", mc.prevCursor)
        vim.keymap.set("n", "<leader>l", mc.nextCursor)
    end
}
```

## Install Instructions (macOS/Linux)
Make sure lazy.nvim is installed by following
[their instructions](https://lazy.folke.io/installation).
Then, add this code to your `init.lua`:

```lua
local lazierPath = vim.fn.stdpath("data") .. "/lazier.nvim"
if not (vim.uv or vim.loop).fs_stat(lazierPath) then
    local repo = "https://github.com/jake-stewart/lazier.nvim.git"
    local out = vim.fn.system({
        "git", "clone", "--branch=stable", repo, lazierPath })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({{
            "Failed to clone lazier.nvim:\n" .. out, "Error"
        }}, true, {})
    end
end
vim.opt.runtimepath:prepend(lazierPath)
```

## What's supported
The following functions and objects are supported. Any operations using them
not occur until the plugin has loaded:
- `vim.keymap.set`
- `vim.api.nvim_set_hl`
- `vim.cmd`
- `vim.api.nvim_create_autocmd`
- `vim.api.nvim_create_augroup`
- Any module that is imported with `require`

## How it works
When your `config` function is called, the Neovim API is wrapped so that
their calls can be captured. This lets us keep track of which keys should be
used for lazy loading. Requiring a module returns a proxy object that keeps
track the operations that occur. These operations are only applied once the
plugin is loaded. This lets you configure and use a plugin as though it were
loaded with your operations only taking once it actually loads.
