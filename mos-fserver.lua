local component = require("component")
local fs = require("filesystem")
local event = require("event")
local computer = require("computer")
local serialization = require("serialization")

local NAME = "MineOS FileServer"
local PORT = 1488
local DIR_PATH = "/"
local IS_PUBLIC = false

local ALLOWED_USERS = { 
	
}

local modemProxy = component.proxy(component.list("modem")())
modemProxy.open(PORT)
local filesystemHandles = {}
local fs_proxy = fs.get(DIR_PATH)

local function broadcastComputerState(state)
	return modemProxy.broadcast(PORT, "network", state and "computerAvailable" or "computerNotAvailable", NAME)
end

local exceptionMethods = {
	getLabel = function()
		return NAME or modemProxy.address
	end,

	list = function(path)
		local list, reason = fs_proxy.list(fs.concat(DIR_PATH, path))
		return serialization.serialize(list)
	end,

	exists = function(path)
		return fs_proxy.exists(fs.concat(DIR_PATH, path))
	end,

	remove = function(path)
		return fs_proxy.remove(fs.concat(DIR_PATH, path))
	end,

	rename = function(opath, npath)
		return fs_proxy.rename(fs.concat(DIR_PATH, opath), fs.concat(DIR_PATH, npath))
	end,

	makeDirectory = function(path)
		return fs_proxy.makeDirectory(fs.concat(DIR_PATH, path))
	end,

	size = function(path)
		return fs_proxy.size(fs.concat(DIR_PATH, path))
	end,

	isDirectory = function(path)
		return fs_proxy.isDirectory(fs.concat(DIR_PATH, path))
	end,

	lastModified = function(path)
		return fs_proxy.lastModified(fs.concat(DIR_PATH, path))
	end,	

	open = function(path, mode)
		local ID
		while not ID do
			ID = math.random(1, 0x7FFFFFFF)
			for handleID in pairs(filesystemHandles) do
				if handleID == ID then
					ID = nil
				end
			end
		end

		filesystemHandles[ID] = fs_proxy.open(fs.concat(DIR_PATH, path), mode)
		
		return ID
	end,

	close = function(ID)
		local data, reason = fs_proxy.close(filesystemHandles[ID])
		filesystemHandles[ID] = nil
		return data, reason
	end,

	read = function(ID, ...)
		return fs_proxy.read(filesystemHandles[ID], ...)
	end,

	write = function(ID, ...)
		return fs_proxy.write(filesystemHandles[ID], ...)
	end,

	seek = function(ID, ...)
		return fs_proxy.seek(filesystemHandles[ID], ...)
	end,
}

local function handleRequest(eventData)	
	if IS_PUBLIC or ALLOWED_USERS[eventData[3]] then
		local result = { pcall(exceptionMethods[eventData[8]] or fs_proxy[eventData[8]], table.unpack(eventData, 9)) }
		modemProxy.send(eventData[3], PORT, "network", "response", eventData[8], table.unpack(result, result[1] and 2 or 1))
	else
		modemProxy.send(eventData[3], PORT, "network", "accessDenied")
	end
end

local eventHandler = function(...)
	local eventData = {...}
	if eventData[1] == "modem_message" and eventData[6] == "network" then
		if eventData[7] == "request" then
			handleRequest(eventData)
		elseif eventData[7] == "computerAvailable" or eventData[7] == "computerAvailableRedirect" then
			if eventData[7] == "computerAvailable" then
				modemProxy.send(eventData[3], PORT, "network", "computerAvailableRedirect", NAME)
			end
		end
	end
end

broadcastComputerState(true)
while true do
  eventHandler(event.pull())
end