--[[
  Third-party party/raid frame integration for seeker mode.
  Hides (and restores) frames from popular UI addon replacements so seekers
  cannot use them to locate hiders.

  Two strategies are used per addon:
    API-level  — VuhDo (SHOW_PANELS flag) and Grid2 (FrameVisibility profile)
                 so those addons' own event handlers respect the hide.
    Poll-based — ElvUI, Danders Frames, Shadowed Unit Frames, Cell
                 use global frame names added to the ~0.35s polling list;
                 re-shows triggered by internal group/zone events are
                 caught on the next poll tick.

  NHS.ThirdPartyFramesOnHide()   -- call when entering seeker mode
  NHS.ThirdPartyFramesOnShow()   -- call when leaving seeker mode
  NHS.ThirdPartyFramesPollHide() -- call each poll tick
]]

local NHS = NeighborhoodHideSeek

local function isLoaded(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    return C_AddOns.IsAddOnLoaded(name)
  end
  return IsAddOnLoaded(name)
end

local saved = {}  -- keyed values for API-level addon state

--[[
  Addon handlers table. Fields:
    addon      string  — folder/toc name for IsAddOnLoaded
    pollFrames table   — global frame name strings hidden by the poll loop
    onHide     func    — optional; API-level hide called once on seeker mode enter
    onShow     func    — optional; API-level restore called once on seeker mode exit
]]
local HANDLERS = {

  -- ElvUI wraps oUF headers with RegisterStateDriver; the state driver will
  -- re-show on group changes, but the poll re-hides on the next tick.
  {
    addon = "ElvUI",
    pollFrames = {"ElvUF_Party", "ElvUF_Raid1", "ElvUF_Raid2", "ElvUF_Raid3"},
  },

  -- VuhDo: set SHOW_PANELS=false so its own event handlers keep frames hidden.
  {
    addon = "VuhDo",
    onHide = function()
      if not VUHDO_CONFIG then return end
      saved.vuhdo_show = VUHDO_CONFIG["SHOW_PANELS"]
      VUHDO_CONFIG["SHOW_PANELS"] = false
      if VUHDO_redrawAllPanels then pcall(VUHDO_redrawAllPanels) end
    end,
    onShow = function()
      if not VUHDO_CONFIG then return end
      VUHDO_CONFIG["SHOW_PANELS"] = (saved.vuhdo_show ~= false)
      saved.vuhdo_show = nil
      if VUHDO_redrawAllPanels then pcall(VUHDO_redrawAllPanels) end
    end,
  },

  -- Danders Frames: secure containers; poll handles re-shows from group events.
  {
    addon = "DandersFrames",
    pollFrames = {"DandersFramesContainer", "DandersRaidFramesContainer"},
  },

  -- Grid2: FrameVisibility("Never") writes the profile so Grid2's own
  -- UpdateVisibility calls respect the setting; saves and restores prior value.
  {
    addon = "Grid2",
    onHide = function()
      if not Grid2Layout then return end
      saved.grid2_display = Grid2 and Grid2.db and Grid2.db.profile and Grid2.db.profile.FrameDisplay
      pcall(function() Grid2Layout:FrameVisibility("Never") end)
    end,
    onShow = function()
      if not Grid2Layout then return end
      local prev = saved.grid2_display or "Grouped"
      saved.grid2_display = nil
      pcall(function() Grid2Layout:FrameVisibility(prev) end)
    end,
  },

  -- Shadowed Unit Frames: secure group headers; poll handles re-shows.
  -- split-raid headers use "SUFHeaderraid1" .. "SUFHeaderraid8".
  {
    addon = "ShadowedUnitFrames",
    pollFrames = (function()
      local t = {"SUFHeaderparty", "SUFHeaderraid"}
      for i = 1, 8 do t[#t + 1] = "SUFHeaderraid" .. i end
      return t
    end)(),
  },

  -- Cell: non-secure root parent frame; poll handles re-shows from group events.
  {
    addon = "Cell",
    pollFrames = {"CellParent"},
  },
}

local active = false          -- true while we have hidden frames
local activePollFrames = nil  -- built from loaded addons at hide time

local function buildActivePollFrames()
  activePollFrames = {}
  for _, h in ipairs(HANDLERS) do
    if isLoaded(h.addon) and h.pollFrames then
      for _, fname in ipairs(h.pollFrames) do
        activePollFrames[#activePollFrames + 1] = fname
      end
    end
  end
end

-- Called once when entering seeker mode (guarded by hideGroupFramesInSeeker in SeekerMode.lua).
function NHS.ThirdPartyFramesOnHide()
  if active then return end
  active = true
  buildActivePollFrames()
  for _, h in ipairs(HANDLERS) do
    if isLoaded(h.addon) and h.onHide then
      pcall(h.onHide)
    end
  end
end

-- Called once when leaving seeker mode; restores all hidden frames.
function NHS.ThirdPartyFramesOnShow()
  if not active then return end
  active = false
  for _, h in ipairs(HANDLERS) do
    if isLoaded(h.addon) and h.onShow then
      pcall(h.onShow)
    end
  end
  if activePollFrames then
    local inCombat = InCombatLockdown()
    for _, fname in ipairs(activePollFrames) do
      local f = _G[fname]
      if f and f.Show and not inCombat then
        pcall(f.Show, f)
      end
    end
  end
  activePollFrames = nil
end

-- Called by the seeker UI poll loop (~0.35 s). Re-hides frames that re-showed
-- themselves via internal group/zone event handlers.
function NHS.ThirdPartyFramesPollHide()
  if not activePollFrames then return end
  local inCombat = InCombatLockdown()
  for _, fname in ipairs(activePollFrames) do
    local f = _G[fname]
    if f and f.IsShown and f:IsShown() and not inCombat then
      pcall(f.Hide, f)
    end
  end
end
