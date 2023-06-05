local PathSeparator = vim.fn.has('win32') > 0 and "\\" or "/"
local LogPath = vim.fn.stdpath('data') .. PathSeparator .. "fzf-lua.log"

local function info(fmt, ...)
    local messages = string.format(fmt, ...)
    local split_messages = vim.split(messages, "\n")
    local fp = io.open(LogPath, "a")
    if fp then
        for _, line in ipairs(split_messages) do
            fp:write(
                string.format( "%s: %s\n", os.date("%Y-%m-%d %H:%M:%S"), line)
            )
        end
        fp:close()
    end
end

local M = {
    info = info,
}

return M
