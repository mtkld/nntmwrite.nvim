local M = {}

-- Default configuration
M.config = {
	socket_path = "/tmp/nntm-stream", -- default socket path
}

function M.setup(config)
	M.config = vim.tbl_deep_extend("force", M.config, config or {})
end

-- Extract plugin-name:init.lua or plain filename
function M.extract_tag_from_source(source)
	source = source:gsub("\\", "/")
	local file = source:match("[^/]+$") or "<unknown>"

	if file == "init.lua" then
		local module = source:match("/lua/([^/]+)/init%.lua$")
		if module then
			return "@" .. module:gsub("%s+", "_") .. ":init.lua"
		end
	end

	return "@" .. file:gsub("%s+", "_")
end

-- Main log function
function M.log(...)
	local info = debug.getinfo(2, "S")
	local source = info and info.short_src or "<unknown>"
	local tag = M.extract_tag_from_source(source)

	local args = { ... }
	table.insert(args, 1, tag)

	M.write(table.concat(args, " "))
end

-- Write to the UNIX socket
function M.write(message)
	if not message or message:match("^%s*$") then
		return
	end

	local socket_path = M.config.socket_path
	local uv = vim.loop

	local sock = uv.new_pipe(false) -- false: not IPC

	sock:connect(socket_path, function(err)
		if err then
			vim.schedule(function()
				vim.notify("Socket write error: " .. err, vim.log.levels.WARN)
			end)
			sock:close()
			return
		end

		sock:write(message .. "\n")
		sock:shutdown(function()
			sock:close()
		end)
	end)
end

return M
