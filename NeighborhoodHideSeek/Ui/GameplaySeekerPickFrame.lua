--[[
  Gameplay "Select seeker" roster list + bottom Random seeker (animation) button.
  opts: onAfterPick(). Uses BuildMainFrameBridge at refresh/click time.
  Load after Ui/ScrollUtil.lua; before Ui/MainFrame.lua.
]]

local NHS = NeighborhoodHideSeek

--- @param opts table|nil { onAfterPick = function() }
function NHS.CreateGameplaySeekerPickFrame(opts)
  opts = opts or {}
  local State = NHS.State
  local onAfterPick = opts.onAfterPick or function() end

  local gsfp = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  gsfp:SetSize(300, 380)
  gsfp:SetClampedToScreen(true)
  gsfp:SetMovable(true)
  gsfp:EnableMouse(true)
  gsfp:RegisterForDrag("LeftButton")
  gsfp:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  gsfp:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    NHS.EnsureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.gameplaySeekerPickFramePoint = { p, rp or "UIParent", x, y }
  end)
  gsfp:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  gsfp:SetBackdropColor(0, 0, 0, 0.9)
  local gsfpTitle = gsfp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  gsfpTitle:SetPoint("TOP", 0, -14)
  gsfpTitle:SetText("Select Seeker")
  local gsfpStatus = gsfp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gsfpStatus:SetPoint("TOPLEFT", 16, -40)
  gsfpStatus:SetWidth(268)
  gsfpStatus:SetJustifyH("LEFT")
  gsfpStatus:SetText("—")
  local gsfpScroll = CreateFrame("ScrollFrame", nil, gsfp)
  gsfpScroll:SetPoint("TOPLEFT", 16, -62)
  gsfpScroll:SetSize(268, 258)
  NHS.SetupScrollFrameMouseWheel(gsfpScroll)

  local gsfpScrollChild = CreateFrame("Frame", nil, gsfpScroll)
  gsfpScrollChild:SetSize(268, 1)
  gsfpScrollChild:EnableMouse(true)
  gsfpScroll:SetScrollChild(gsfpScrollChild)
  local gsfpAnimRandomSeekerBtn = CreateFrame("Button", nil, gsfp, "UIPanelButtonTemplate")
  gsfpAnimRandomSeekerBtn:SetSize(268, 24)
  gsfpAnimRandomSeekerBtn:SetText("Random Seeker")
  gsfpAnimRandomSeekerBtn:SetPoint("BOTTOM", gsfp, "BOTTOM", 0, 12)
  gsfpAnimRandomSeekerBtn:Hide()
  local gsfpCloseBtn = CreateFrame("Button", nil, gsfp, "UIPanelCloseButton")
  gsfpCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  gsfpCloseBtn:SetScript("OnClick", function()
    gsfp:Hide()
  end)
  gsfp:Hide()

  local gameplaySeekerPickRowBtns = {}

  local function refreshGroupSeekerPickList()
    local B = NHS.BuildMainFrameBridge
    if not B or not B.nhsGetGroupRoster then
      return
    end
    local roster = B.nhsGetGroupRoster()
    local required = B.nhsGetRequiredSeekerCount and B.nhsGetRequiredSeekerCount() or 1
    local isHiderMode = NHS.IsHiderMode and NHS.IsHiderMode()
    local picked = #State.gameCandidateKeys
    -- Build a set of already-picked keys so we can disable those rows.
    local pickedSet = {}
    for _, k in ipairs(State.gameCandidateKeys) do
      pickedSet[k] = true
    end
    if required > 1 then
      gsfpTitle:SetText(("Select Seeker %d/%d"):format(picked + 1, required))
      gsfpStatus:SetText(("Pick %d more seeker(s). Tap a row."):format(required - picked))
    elseif isHiderMode then
      gsfpTitle:SetText("Select Hider")
      gsfpStatus:SetText(("Tap a row to choose (%d in group)."):format(#roster))
    else
      gsfpTitle:SetText("Select Seeker")
      gsfpStatus:SetText(("Tap a row to choose (%d in group)."):format(#roster))
    end
    for i = 1, #gameplaySeekerPickRowBtns do
      gameplaySeekerPickRowBtns[i]:Hide()
    end
    local y = 0
    for i, m in ipairs(roster) do
      local btn = gameplaySeekerPickRowBtns[i]
      if not btn then
        btn = CreateFrame("Button", nil, gsfpScrollChild, "UIPanelButtonTemplate")
        gameplaySeekerPickRowBtns[i] = btn
      end
      btn:SetSize(252, 22)
      local alreadyPicked = pickedSet[m.key] == true
      btn:SetText(alreadyPicked and (m.display .. " (picked)") or m.display)
      btn:SetEnabled(not alreadyPicked)
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", 8, -y)
      btn._gspMember = m
      btn:SetScript("OnClick", function(self)
        local mem = self._gspMember
        if not mem then
          return
        end
        -- Add to candidate list (don't replace).
        State.gameCandidateKeys[#State.gameCandidateKeys + 1] = mem.key
        local newPicked = #State.gameCandidateKeys
        if B.nhsPersistGameSessionToSaved then
          B.nhsPersistGameSessionToSaved()
        end
        -- Close the frame if we now have enough seekers, otherwise refresh for the next pick.
        if newPicked >= required then
          gsfp:Hide()
          local names = {}
          for _, k in ipairs(State.gameCandidateKeys) do
            names[#names + 1] = Ambiguate(k, "short")
          end
          local nameStr = table.concat(names, ", ")
          if required > 1 then
            print(
              ("|cff88ccff[NHS]|r Seekers (%d/%d): |cffffffff%s|r — Confirm seekers to lock in."):format(
                newPicked, required, nameStr
              )
            )
          elseif isHiderMode then
            print(
              ("|cff88ccff[NHS]|r Hider pick: |cffffffff%s|r — Confirm hider to lock in (or pick again)."):format(
                mem.display
              )
            )
          else
            print(
              ("|cff88ccff[NHS]|r Seeker pick: |cffffffff%s|r — Confirm seeker to lock in (or pick again)."):format(
                mem.display
              )
            )
          end
        else
          -- Still need more picks — refresh the list in-place.
          refreshGroupSeekerPickList()
          print(
            ("|cff88ccff[NHS]|r Seeker %d/%d: |cffffffff%s|r — pick %d more."):format(
              newPicked, required, mem.display, required - newPicked
            )
          )
        end
        onAfterPick()
      end)
      btn:Show()
      y = y + 24
    end
    gsfpScrollChild:SetHeight(math.max(y + 8, 1))
    gsfpScroll:SetVerticalScroll(0)
    gsfpAnimRandomSeekerBtn:SetText(isHiderMode and "Random Hider" or "Random Seeker")
    gsfpAnimRandomSeekerBtn:SetShown(#roster > 0)
    gsfpAnimRandomSeekerBtn:SetEnabled(B.nhsMayUseLeaderGameActions and B.nhsMayUseLeaderGameActions() and #roster > 0)
  end

  return {
    frame = gsfp,
    animRandomSeekerBtn = gsfpAnimRandomSeekerBtn,
    refresh = refreshGroupSeekerPickList,
  }
end
