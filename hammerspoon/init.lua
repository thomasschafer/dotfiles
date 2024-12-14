local appShortcuts = {
	A = "Ghostty",
	S = "Slack",
	D = "YouTube Music",
	F = "Zed",
	Z = "Zoom",
	X = "Terminal",
	C = "Chrome",
	V = "Visual Studio Code",
}

local function launchApp(name)
	return function()
		hs.application.launchOrFocus(name)
		if hs.application.get(name) then
			hs.application.get(name):activate()
		end
	end
end

local meh = { "ctrl", "alt", "shift" }
for key, appName in pairs(appShortcuts) do
	hs.hotkey.bind(meh, key, launchApp(appName))
end
