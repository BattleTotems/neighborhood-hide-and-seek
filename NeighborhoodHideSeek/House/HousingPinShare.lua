--[[
  Chat pin share: sanitize plain text, Blizzard waypoint hyperlinks, SendChatMessage tiers.
  Loaded after House/Housing.lua — uses NeighborhoodHideSeek.GetPinCoordsForHouseEntry.
]]

local NHS = NeighborhoodHideSeek

local function getPinCoords(entry, rowIndex)
  local f = NHS.GetPinCoordsForHouseEntry
  if f then
    return f(entry, rowIndex)
  end
  return nil, nil, nil
end

-- Plain-text pin lines: | in SendChatMessage starts UI escapes — strip/replace for those only.
local function housingSanitizePinShareForChat(s)
  if not s then
    return ""
  end
  return (s:gsub("|", " · "))
end

-- Blizzard user-waypoint chat link (click sets map pin for the reader). Do not sanitize | in this string.
local function housingBuildBlizzardWaypointHyperlink(mapID, x, y)
  if not C_Map.SetUserWaypoint or not C_Map.GetUserWaypointHyperlink then
    return nil
  end
  local newPt
  if UiMapPoint.CreateFromCoordinates then
    newPt = UiMapPoint.CreateFromCoordinates(mapID, x, y)
  end
  if not newPt then
    return nil
  end
  if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
    return nil
  end
  local oldPt = nil
  if C_Map.GetUserWaypoint then
    local ok, prev = pcall(C_Map.GetUserWaypoint)
    if ok and prev ~= nil then
      oldPt = prev
    end
  end
  if not pcall(C_Map.SetUserWaypoint, newPt) then
    return nil
  end
  local okH, link = pcall(C_Map.GetUserWaypointHyperlink)
  if oldPt then
    pcall(C_Map.SetUserWaypoint, oldPt)
  elseif C_Map.ClearUserWaypoint then
    pcall(C_Map.ClearUserWaypoint)
  end
  if okH and type(link) == "string" and link ~= "" then
    return link
  end
  return nil
end

-- Only real SendChatMessage counts as “shared” — no edit-box prefill, no Yell, no printing coords on failure.
-- Channels: raid → party → say (no instance group requirement).
local function housingSendPinShareTryChannels(text)
  if IsInRaid() then
    local ok = pcall(SendChatMessage, text, "RAID")
    if ok then
      return true, "RAID", nil
    end
  end
  if IsInGroup() then
    local ok = pcall(SendChatMessage, text, "PARTY")
    if ok then
      return true, "PARTY", nil
    end
  end
  local ok = pcall(SendChatMessage, text, "SAY")
  if ok then
    return true, "SAY", nil
  end
  return false, nil, "Could not send to raid, party, or say."
end

local function housingSendPinShareChatRaw(text)
  if not text or text == "" then
    return false, nil, "empty message"
  end
  return housingSendPinShareTryChannels(text)
end

local function housingSendPinShareChat(text)
  text = housingSanitizePinShareForChat(text)
  if not text or text == "" then
    return false, nil, "empty message"
  end
  return housingSendPinShareTryChannels(text)
end

-- Plain-text fallback when a waypoint hyperlink cannot be built or sent (same tiers as Share House Pin).
local function housingPinShareCoordinateMessage(mapID, x, y, labelText)
  local pctX = x * 100
  local pctY = y * 100
  local label = (labelText and labelText ~= "") and labelText or "plot"
  if #label > 72 then
    label = label:sub(1, 69) .. "..."
  end
  local msg = ("[NHS] Neighborhood pin: %s — uiMapID %d  %.4f %.4f  (~%.1f%% , ~%.1f%%)"):format(
    label,
    mapID,
    x,
    y,
    pctX,
    pctY
  )
  if #msg > 255 then
    msg = ("[NHS] Pin uiMapID %d %.4f %.4f — %s"):format(mapID, x, y, label)
  end
  if #msg > 255 then
    msg = ("[NHS] %d %.4f %.4f"):format(mapID, x, y)
  end
  return msg
end

local function housingShareSelectedPinInChat(entry, rowIndex, labelText)
  local mapID, x, y = getPinCoords(entry, rowIndex)
  if not mapID or x == nil or y == nil then
    return false, "No coordinates for this plot — Refresh houses (Housing map open helps)."
  end
  local msg = housingPinShareCoordinateMessage(mapID, x, y, labelText)
  local link = housingBuildBlizzardWaypointHyperlink(mapID, x, y)
  if link and #link <= 255 then
    local ok, ch, err = housingSendPinShareChatRaw(link)
    if ok then
      return true, ch
    end
  end
  local ok, ch, err = housingSendPinShareChat(msg)
  if ok then
    return true, ch
  end
  return false, err or "Send failed."
end

NHS.HousingPinShare = {
  SanitizeForChat = housingSanitizePinShareForChat,
  BuildWaypointHyperlink = housingBuildBlizzardWaypointHyperlink,
  CoordinateMessage = housingPinShareCoordinateMessage,
  ShareSelectedPinInChat = housingShareSelectedPinInChat,
}
