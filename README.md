# lazier.nvim
Lazier is a wrapper around [lazy.nvim](https://lazy.folke.io/) and lets you
have extremely fast startup time and lazy loaded plugins
without any extra effort.

### Start up time optimizations
 - Delays starting `lazy.nvim` until after Neovim has rendered its first frame.
 - Compiles your plugin spec into a single file when it changes.
 - Bundles and bytecode compiles part of the Neovim Lua API and
   your config files.

<img width="3052" height="1980" alt="lazier" src="https://github.com/user-attachments/assets/d2ffa3c7-b3ec-4a26-b63e-bbb1d9fd3ee4" />

*The above was measured with `--startuptime` on my own config modified for each scenario while opening a typescript file.* 

### Automatic lazy loaded plugins
 - The first time you open Neovim after your config changes, lazy loading is disabled.
   Parts of the Neovim API like `vim.keymap.set` are wrapped and used to automatically build up
   a lazy loading spec.
 - Subsequent Neovim launches will use the previously generated, bundled and bytecode compiled
   lazy loading specs to avoid run-time cost.

### Backwards compatible with Lazy
 - You can add lazier and get the improved start up time without having to change your config structure.

## Setup

```lua
local lazierPath = vim.fn.stdpath("data") .. "/lazier/lazier.nvim"
if not (vim.uv or vim.loop).fs_stat(lazierPath) then
    local repo = "https://github.com/jake-stewart/lazier.nvim.git"
    local out = vim.fn.system({
        "git", "clone", "--branch=stable-v2", repo, lazierPath })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({{
            "Failed to clone lazier.nvim:\n" .. out, "Error"
        }}, true, {})
    end
end
vim.opt.runtimepath:prepend(lazierPath)

require("lazier").setup("plugins", {
    lazier = {
        before = function()
            -- function to run before the ui renders.
            -- it is faster to require parts of your config here
            -- since at this point they will be bundled and bytecode compiled.
            -- eg: require("options")
        end,

        after = function()
            -- function to run after the ui renders.
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
        end,

        -- whether plugins should be included in the bytecode
        -- compiled bundle. this will make your startup slower.
        bundle_plugins = false,

        -- whether to automatically generate lazy loading config
        -- by identifying the mappings set when the plugin loads
        generate_lazy_mappings = true,

        -- automatically rebundle and compile nvim config when it changes
        -- if set to false then you will need to :LazierClear manually
        detect_changes = true,
    },

    -- your usual lazy.nvim config goes here
    -- ...
})
```

## Example Plugin Config

#### Before
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

#### After
With lazier, we define mappings and configuration with normal code and get
lazy loading automatically (This new way of configuring is optional. Your old configs are backwards compatible): 

```lua
return {
    "repo/some-plugin.nvim",
    config = function()
        local plugin = require("some-plugin")
        plugin.setup({})
        vim.keymap.set("n", "<leader>a", plugin.doSomething)
        vim.keymap.set("n", "<leader>b", vim.cmd.DoSomethingElse)
    end
}
```


## Updating Lazier
Run `:LazierUpdate` from within Neovim.
