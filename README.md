# lazier.nvim
lazier is a wrapper around [lazy.nvim](https://lazy.folke.io/) which lets you
have lazy loaded plugins without any extra effort.

### Before:
Normally, we define the mappings within the `keys` field so that the plugin
can be lazy loaded:

```lua
return {
    "jake-stewart/multicursor.nvim",
    opts = {},
    keys = {
        "<leader>h", function()
            require("multicursorn-vim").prevCursor()
        end,
        "<leader>l", function()
            require("multicursorn-vim").nextCursor()
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
local lazierpath = vim.fn.stdpath("data") .. "/lazier.nvim"
if not (vim.loop.fs_stat(lazierpath)) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/jake-stewart/lazier.nvim.git",
        "--branch=stable",
        lazierpath
    })
end
vim.opt.runtimepath:prepend(lazierpath)
```

## How it works
When your `config` function is called, the Neovim API is wrapped so that
their calls can be captured. This lets us keep track of which keys should be
used for lazy loading automatically. Requiring a module returns a proxy
object that keeps track the operations that occur. These operations are only
applied once the plugin is loaded. This lets you configure and use plugin as
though it were loaded, your operations only taking once it actually loads.
