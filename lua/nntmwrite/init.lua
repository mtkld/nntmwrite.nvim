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
local uv = vim.loop
local pending = {}
local active = false

-- configurable retry limit
local MAX_RETRIES = 5

function M.write(message)
	if not message or message:match("^%s*$") then
		return
	end
	table.insert(pending, { text = message, retries = 0 })
	if not active then
		process_queue()
	end
end

function process_queue()
	if #pending == 0 then
		active = false
		return
	end

	active = true
	local item = table.remove(pending, 1)
	local message, retries = item.text, item.retries
	local sock = uv.new_pipe(false)

	local function try_connect()
		sock:connect(M.config.socket_path, function(err)
			if err then
				if tostring(err):match("EAGAIN") and retries < MAX_RETRIES then
					local retry_timer = uv.new_timer()
					retry_timer:start(40, 0, function()
						retry_timer:close()
						item.retries = retries + 1
						table.insert(pending, 1, item) -- requeue at front
						sock:close()
						process_queue()
					end)
					return
				end

				vim.schedule(function()
					vim.notify("Socket connect error: " .. err, vim.log.levels.WARN)
				end)
				sock:close()

				local fail_timer = uv.new_timer()
				fail_timer:start(50, 0, function()
					fail_timer:close()
					process_queue()
				end)
				return
			end

			local full_message = message .. "\n"
			sock:write(full_message, function(write_err)
				if write_err then
					vim.schedule(function()
						vim.notify("Socket write error: " .. write_err, vim.log.levels.WARN)
					end)
				end
				sock:shutdown(function()
					sock:close()
					process_queue()
				end)
			end)
		end)
	end

	try_connect()
end
-- Write to the UNIX socket
-- Blocking version giving EAGAIN error
--function M.write(message)
--	if not message or message:match("^%s*$") then
--		return
--	end
--
--	local socket_path = M.config.socket_path
--	local uv = vim.loop
--
--	local sock = uv.new_pipe(false) -- false: not IPC
--
--	sock:connect(socket_path, function(err)
--		if err then
--			vim.schedule(function()
--				vim.notify("Socket write error: " .. err, vim.log.levels.WARN)
--			end)
--			sock:close()
--			return
--		end
--
--		sock:write(message .. "\n")
--		sock:shutdown(function()
--			sock:close()
--		end)
--	end)
--end

return M
