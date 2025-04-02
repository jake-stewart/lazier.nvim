vim.schedule(function()
    vim.api.nvim_create_user_command("LazierUpdate", function()
        require("lazier.update")()
    end, { desc = "Update lazier" })

    vim.api.nvim_create_user_command("LazierClear", function()
        require("lazier.cache").clear()
    end, { desc = "Clear the cache" })
end)
