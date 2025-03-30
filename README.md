# lazier.nvim
Lazier is a wrapper around [lazy.nvim](https://lazy.folke.io/) and lets you
have lazy loaded plugins without any extra effort.

### Before:
Normally, we define mappings within the `keys` field so that the plugin can
be lazy loaded:

```lua
return {
    "repo/some-plugin.nvim",
    opts = {},
    keys = {
        "<leader>a", function()
            require("some-plugin").doSomething()
        end,
        "<leader>b", function()
            vim.cmd.DoSomethingElse()
        end
    }
}
```

### After
With lazier, we define mappings and configuration with normal code and get
lazy loading automatically: 

```lua
return require "lazier" {
    "repo/some-plugin.nvim",
    config = function()
        local plugin = require("some-plugin")
        plugin.setup({})
        vim.keymap.set("n", "<leader>a", plugin.doSomething)
        vim.keymap.set("n", "<leader>b", vim.cmd.DoSomethingElse)
    end
}
```

### What's Supported
The following functions and objects are supported. Any operations using them
will not occur until the plugin has loaded:
- `vim.keymap.set`
- `vim.api.nvim_set_hl`
- `vim.cmd`
- `vim.api.nvim_create_autocmd`
- `vim.api.nvim_create_augroup`
- Any module that is imported with `require`

## Faster Startup Time
You can use use `lazier` inplace of `lazy` to get a quicker startup time.
There are two optimizations:
 - Delays starting `lazy.nvim` until after Neovim has launched.
 - Compiles your plugin spec into a single file when it changes.

```lua
require("lazier").setup("plugins", {
    lazier = {
        after = function()
            -- function to run after lazy.nvim starts.
            -- you can use this for further custom lazy loading.
            -- eg: require("mappings")
        end,
        start_lazily = function()
            -- function which returns whether lazy.nvim
            -- should start delayed or not.
            local nonLazyLoadableExtensions = {
                zip = true,
                tar = true,
                gz = true
            }
            local fname = vim.fn.expand("%")
            return fname == ""
                or vim.fn.isdirectory(fname) == 0
                and not nonLazyLoadableExtensions
                    [vim.fn.fnamemodify(fname, ":e")]
        end
    },
    -- lazy.nvim config
})
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

## How it Works
When your `config` function is called, the Neovim API is wrapped so that
their calls can be captured. This lets us keep track of which keys should be
used for lazy loading. Requiring a module returns a proxy object that keeps
track the operations that occur. These operations are only applied once the
plugin is loaded. This lets you configure and use a plugin as though it were
loaded with your operations only taking once it actually loads.
