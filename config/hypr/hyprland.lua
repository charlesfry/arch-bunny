local mod = "SUPER"

hl.on("hyprland.start", function()
  hl.exec_cmd("uwsm finalize")
end)

hl.config({
  animations = { enabled = false },
})

hl.config({
  input = {
    repeat_delay = 300,
    repeat_rate = 50,
    numlock_by_default = true,
  },
})

-- Displays (Hyprland needs resolution / scale to be whole numbers; 1.504 gives 1500x1000)
hl.monitor({ output = "eDP-1", mode = "2880x1920@120.000", position = "auto", scale = 2 })
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60.000", position = "auto", scale = 1 })

-- Terminal
hl.bind(mod .. " + Return", hl.dsp.exec_cmd("bunny-launch-term-cwd"))

-- App launcher
hl.bind(mod .. " + space", hl.dsp.exec_cmd("fuzzel"))

-- Window focus
hl.bind(mod .. " + h", hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + j", hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + l", hl.dsp.focus({ direction = "right" }))

-- Cycle workspaces
hl.bind(mod .. " + d", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + u", hl.dsp.focus({ workspace = "e-1" }))

-- Move windows
hl.bind(mod .. " + SHIFT + h", hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. " + SHIFT + j", hl.dsp.window.move({ direction = "down" }))
hl.bind(mod .. " + SHIFT + k", hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. " + SHIFT + l", hl.dsp.window.move({ direction = "right" }))

-- Resize windows
hl.bind(mod .. " + CTRL + h", hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true })
hl.bind(mod .. " + CTRL + l", hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { repeating = true })
hl.bind(mod .. " + CTRL + j", hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { repeating = true })
hl.bind(mod .. " + CTRL + k", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true })

-- Window actions
hl.bind(mod .. " + w", hl.dsp.window.close())
hl.bind(mod .. " + f", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))

-- Workspaces
for i = 1, 9 do
  hl.bind(mod .. " + " .. i, hl.dsp.focus({ workspace = i }))
  hl.bind(mod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Audio controls
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("bunny-osd volume 10%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("bunny-osd volume 10%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("bunny-osd volume mute"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("bunny-osd mic mute"), { locked = true })

-- Media controls
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Brightness controls
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("bunny-osd brightness +10%"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("bunny-osd brightness 10%-"), { locked = true, repeating = true })
