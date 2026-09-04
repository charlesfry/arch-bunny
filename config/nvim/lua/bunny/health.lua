-- :checkhealth bunny — the on-demand diagnosis CHOICES `jupyter-in-neovim`
-- requires: "a diagnosis nobody can run is not a diagnosis". Each check is a
-- failure mode actually hit on hardware in phases 3-4.
local M = {}

function M.check()
  local h = vim.health
  h.start("Bunny notebook stack")

  if vim.env.TERM == "xterm-kitty" or vim.env.KITTY_WINDOW_ID ~= nil then
    h.ok("kitty graphics terminal detected")
  else
    h.warn("not running in kitty — inline images are off (expected in a TTY or over SSH)")
  end

  local py = vim.g.python3_host_prog
  if py and vim.uv.fs_stat(py) then
    h.ok("python provider pinned: " .. py)
  else
    h.error("provider venv missing (~/.venvs/neovim) — molten/Jupyter cannot work", {
      "run the installer's venv bootstrap, or: uv venv ~/.venvs/neovim && uv pip install pynvim jupyter_client ipykernel matplotlib",
    })
  end

  if vim.fn.exists(":MoltenInit") == 2 then
    h.ok("molten commands registered")
  else
    h.error("MoltenInit absent — remote plugin manifest stale", { "run :UpdateRemotePlugins and restart" })
  end

  local rt = vim.fn.expand("~/.local/share/jupyter/runtime")
  if vim.uv.fs_stat(rt) then
    h.ok("jupyter runtime dir exists")
  else
    h.error("jupyter runtime dir missing — MoltenInit will fail with ENOENT", { "mkdir -p " .. rt })
  end
end

return M
