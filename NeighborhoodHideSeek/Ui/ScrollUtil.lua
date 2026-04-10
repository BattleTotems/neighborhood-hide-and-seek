--[[
  Shared ScrollFrame mouse wheel handling (used by main window satellite dialogs).
]]

local NHS = NeighborhoodHideSeek

--- @param scrollFrame ScrollFrame
--- @param step number pixels per wheel notch (default 30)
function NHS.SetupScrollFrameMouseWheel(scrollFrame, step)
  step = step or 30
  scrollFrame:EnableMouse(true)
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(self:GetVerticalScrollRange(), 0)
    local next = self:GetVerticalScroll() - (delta * step)
    if next < 0 then
      next = 0
    elseif next > max then
      next = max
    end
    self:SetVerticalScroll(next)
  end)
end
