--[[
  NHSV (SavedVariables) defaults: layout, seeker UI options, house metadata.
  Load immediately after Core.lua (see .toc).
]]

local NHS = NeighborhoodHideSeek

local function ensureSavedVars()
  NHSV = NHSV or {}
  if NHSV.hideGroupFramesInSeeker == nil then
    NHSV.hideGroupFramesInSeeker = true
  end
  if NHSV.hideMinimapInSeeker == nil then
    NHSV.hideMinimapInSeeker = true
  end
  if NHSV.minimapButtonAngle == nil then
    NHSV.minimapButtonAngle = math.rad(200)
  end
  -- Fine-tune ring vs icon (default 0; added to built-in CENTER nudge in Ui/MinimapButton.lua).
  if NHSV.minimapRingOffsetX == nil then
    NHSV.minimapRingOffsetX = 0
  end
  if NHSV.minimapRingOffsetY == nil then
    NHSV.minimapRingOffsetY = 0
  end
  if type(NHSV.houseSizes) ~= "table" then
    NHSV.houseSizes = {}
  end
  if type(NHSV.houseLabels) ~= "table" then
    NHSV.houseLabels = {}
  end
  if type(NHSV.housePinCoords) ~= "table" then
    NHSV.housePinCoords = {}
  end
  if type(NHSV.houseNeighborhoodNames) ~= "table" then
    NHSV.houseNeighborhoodNames = {}
  end
  if type(NHSV.houseSubdivisionNames) ~= "table" then
    NHSV.houseSubdivisionNames = {}
  end
  if type(NHSV.savedHouseListSubdivision) ~= "string" then
    NHSV.savedHouseListSubdivision = ""
  end
  if type(NHSV.neighborhoodSliceLabels) ~= "table" then
    NHSV.neighborhoodSliceLabels = {}
  end
  if NHSV.useRandomPickAnimation == nil then
    if NHSV.useSpinnerRandomSelection ~= nil then
      NHSV.useRandomPickAnimation = NHSV.useSpinnerRandomSelection
    else
      NHSV.useRandomPickAnimation = true
    end
  end
  if NHSV.gameplaySoundsEnabled == nil then
    NHSV.gameplaySoundsEnabled = true
  end
  if NHSV.showMinimapButton == nil then
    NHSV.showMinimapButton = true
  end
  if NHSV.suppressSeekerModeDialog == nil then
    NHSV.suppressSeekerModeDialog = false
  end
end

NHS.EnsureSavedVars = ensureSavedVars
