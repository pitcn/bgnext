if BG.IsBlackListPlayer then return end
local addonName, ns = ...
local LibBG = ns.LibBG
local L = ns.L
local print = print
local After = C_Timer.After
local auctionID = "auctionID"
local wa = {}
wa.ver = "v4.0"
function wa.GetVerNum(version)
 return tonumber(string.match(version, "v(%d+%.%d+)")) or 0
end
-- 统一计时入口：优先 GetTimePreciseSec（毫秒精度，用于 1s 出价 CD、0.3s 中继 CD、暂停/恢复计时），
-- 经典服客户端若缺失则兜底 GetTime（毫秒 API 在 Classic 1.15/60 引擎存在性见 docs/09 A3 风险）。
function wa.Now()
 if GetTimePreciseSec then
  return GetTimePreciseSec()
 end
 return GetTime()
end
BGA = BGA or {}
BGA.Frames = {}
BGA.ver = wa.ver
BGA.aura_env = wa
wa.AddonChannel = "BiaoGeAuction"
wa.AddonChannel2 = "BiaoGeAuction(%d+)"
C_ChatInfo.RegisterAddonMessagePrefix(wa.AddonChannel)
wa.addonChannelCount = 10
for i = 1, wa.addonChannelCount do
 local channelName = wa.AddonChannel .. i
 C_ChatInfo.RegisterAddonMessagePrefix(channelName)
end
wa.currentChannelIndex = 0
function wa.GetAddonChannelName()
 wa.currentChannelIndex = wa.currentChannelIndex % wa.addonChannelCount + 1
 return wa.AddonChannel .. wa.currentChannelIndex
end
BG.Init(function()
 local font = BIAOGE_TEXT_FONT or STANDARD_TEXT_FONT
 local realmName = GetRealmName():gsub(" ", ""):gsub("%-", "")
 do
  function wa.GN(unit)
   unit = unit or "player"
   if unit == "t" then
    unit = "target"
   end
   return GetUnitName(unit, true)
  end
  function wa.IsMe(bidFrame)
   return bidFrame.player and bidFrame.player == wa.GN() or false
  end
  function wa.GFN(name)
   if not name then return end
   local name, realm = strsplit("-", name)
   realm = realm or realmName
   return name .. "-" .. realm
  end
  function wa.GSN(name)
   if not name then return end
   local name, realm = strsplit("-", name)
   if not realm or realm == "" or realm == realmName then
    return name
   else
    return name .. "-" .. realm
   end
  end
  function wa.SPN(name)
   if not name then return end
   return strsplit("-", name)
  end
  function wa.RGB(hex, alpha)
   local r = string.sub(hex, 1, 2)
   local g = string.sub(hex, 3, 4)
   local b = string.sub(hex, 5, 6)
   r = tonumber(r, 16) / 255
   g = tonumber(g, 16) / 255
   b = tonumber(b, 16) / 255
   if alpha then
    return r, g, b, alpha
   else
    return r, g, b
   end
  end
 end
 do
  wa.sound1 = SOUNDKIT.GS_TITLE_OPTION_OK
  wa.sound2 = 569593
  wa.GREEN1 = "00FF00"
  wa.RED1 = "FF0000"
  wa.maxNumFrame = 20
  wa.WIDTH = 310
  wa.HEIGHT = 105
  wa.SMALL_HEIGHT = 23
  wa.REPEAT_TIME = 20
  wa.HIDEFRAME_TIME = 1
  wa.edgeSize = 2.5
  wa.backdropColor = { 0, 0, 0, .6 }
  wa.backdropBorderColor = { 1, 1, 0, 1 }
  wa.backdropColor_filter = { .5, .5, .5, .5 }
  wa.backdropBorderColor_filter = { .5, .5, .5, 1 }
  wa.barColor_filter = { .5, .5, .5, .8 }
  wa.backdropColor_IsMe = { 0, .6, 0, .6 }
  wa.backdropBorderColor_IsMe = { 0, 1, 0, 1 }
  wa.raidRosterInfo = {}
  wa.endMsg = {}
  wa.tooLateTime = 3
  wa.MiniMoneyTbl = {
   { 50, 1, 1 },
   { 100, 10, 1 },
   { 2000, 100, 100 },
   { 5000, 200, 100 },
   { 1 * 10000, 500, 100 },
   { 2 * 10000, 1000, 500 },
   { 5 * 10000, 2000, 500 },
   { 10 * 10000, 5000, 500 },
   { 20 * 10000, 10000, 1000 },
   { 50 * 10000, 20000, 1000 },
   { 100 * 10000, 50000, 1000 },
   { nil, 100000, 5000 },
  }
 end
 do
  local v = "Gold18" 
  BGA.FontGold18 = CreateFont("BGA.Font" .. v)
  BGA.FontGold18:SetTextColor(1, 0.82, 0)
  BGA.FontGold18:SetFont(font, 18, "OUTLINE")
  local v = "Dis18" 
  BGA.FontDis18 = CreateFont("BGA.Font" .. v)
  BGA.FontDis18:SetTextColor(.5, .5, .5)
  BGA.FontDis18:SetFont(font, 18, "OUTLINE")
  local v = "Dis15" 
  BGA.FontDis15 = CreateFont("BGA.Font" .. v)
  BGA.FontDis15:SetTextColor(.5, .5, .5)
  BGA.FontDis15:SetFont(font, 15, "OUTLINE")
  local v = "Green15" 
  BGA.FontGreen15 = CreateFont("BGA.Font" .. v)
  BGA.FontGreen15:SetTextColor(0, 1, 0)
  BGA.FontGreen15:SetFont(font, 15, "OUTLINE")
  local v = "white15" 
  BGA.FontWhite15 = CreateFont("BGA.Font" .. v)
  BGA.FontWhite15:SetTextColor(1, 1, 1)
  BGA.FontWhite15:SetFont(font, 15, "OUTLINE")
 end
 do
  function wa.SetClassCFF(name, player, type)
   if type then return name end
   local k, classFile
   if player then
    k, classFile = UnitClass(player)
   else
    k, classFile = UnitClass(wa.GSN(name))
   end
   local coloredName = ""
   if classFile then
    local colorHex = select(4, GetClassColor(classFile))
    coloredName = "|c" .. colorHex .. name .. "|r"
    return coloredName, colorHex
   else
    return name, ""
   end
  end
  function wa.SetEditBg(edit)
   edit:SetFont(font, 14, "OUTLINE")
  end
  function wa.FormatNumber(amount)
   if not tonumber(amount) then return amount end
   if Locale == "enUS" then
    local s = tostring(amount)
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return s
   else
    amount = tostring(amount)
    local len = strlen(amount)
    if len < 5 then return amount end
    local last4 = amount:sub(-4, -1)
    local head = amount:sub(1, -5)
    if tonumber(last4) == 0 then
     return head .. L["万"]
    else
     for i = 1, 4 do
      local len = strlen(last4)
      local last = last4:sub(len, len)
      if last == "0" then
       last4 = last4:sub(1, len - 1)
      else
       break
      end
     end
     return head .. "." .. last4 .. L["万"]
    end
   end
  end
  function wa.IsRight(self)
   if self.owner:GetCenter() > UIParent:GetCenter() then
    return true
   end
  end
  function wa.OnLeave(self)
   GameTooltip_Hide()
   self.isOnEnter = false
  end
  function wa.OnEditFocusGained(self)
   wa.lastFocus = self
   self:HighlightText()
  end
  function wa.IsRaidLeader()
   return IsInRaid(1) and UnitIsGroupLeader("player")
  end
  function wa.IsML(player)
   if not player then
    player = wa.GN()
   end
   if (player == wa.raidLeader) or (player == wa.masterLooter) then
    return true
   end
  end
  function wa.UpdateRaidRosterInfo(sendVer)
   wipe(wa.raidRosterInfo)
   wa.raidLeader = nil
   wa.masterLooter = nil
   wa.onlineCount = 0
   if IsInRaid(1) then
    for i = 1, GetNumGroupMembers() do
     local name, rank, subgroup, level, class2, class, zone, online,
     isDead, role, isML, combatRole = GetRaidRosterInfo(i)
     if name then
      local member = {
       name = name,
       rank = rank,
       subgroup = subgroup,
       level = level,
       class2 = class2,
       class = class,
       zone = zone,
       online = online,
       isDead = isDead,
       role = role,
       isML = isML,
       combatRole = combatRole
      }
      tinsert(wa.raidRosterInfo, member)
      if rank == 2 then
       wa.raidLeader = name
      end
      if isML then
       wa.masterLooter = name
      end
     end
    end
    if sendVer then
     C_ChatInfo.SendAddonMessage(wa.AddonChannel, "MyVer" .. "," .. wa.ver, "RAID")
    end
   end
   for k, bidFrame in pairs(BGA.Frames) do
    wa.UpdateButtonState(bidFrame)
   end
  end
  function wa.IsSecret(value)
   return issecretvalue and issecretvalue(value)
  end
  function wa.InBoss()
   return issecretvalue and C_InstanceEncounter.IsEncounterInProgress()
  end
  local receivedCount = 0
  function wa.canSend()
   local memberCount
   local canSend = true
   if IsInRaid(1) then
    memberCount = GetNumGroupMembers(1)
    if receivedCount >= memberCount then
     canSend = false
    end
   else
    canSend = false
    memberCount = 0
   end
   receivedCount = memberCount
   return canSend
  end
  function wa.GetAuctioningFromRaid()
   if not IsInRaid(1) then return end
   wa.canGetAuctioning = true
   C_ChatInfo.SendAddonMessage(wa.AddonChannel, "GetAuctioning", "RAID")
   After(1, function()
    wa.canGetAuctioning = false
   end)
  end
  function wa.SetFrameColor(bidFrame, colorIndex)
   local backdropColor, borderColor, font
   if colorIndex == 1 then
    backdropColor = wa.backdropColor_IsMe
    borderColor = wa.backdropBorderColor_IsMe
    font = BGA.FontGreen15
   elseif colorIndex == 2 then
    backdropColor = wa.backdropColor_filter
    borderColor = wa.backdropBorderColor_filter
    font = BGA.FontDis15
   else
    backdropColor = wa.backdropColor
    borderColor = wa.backdropBorderColor
    font = BGA.FontGreen15
   end
   for k, frame in ipairs({ bidFrame, bidFrame.autoFrame }) do
    frame:SetBackdropColor(unpack(backdropColor))
    frame:SetBackdropBorderColor(unpack(borderColor))
   end
   for k, name in ipairs({ "hide", "cancelButton", "puaseButton", "autoTextButton", "logTextButton", }) do
    if bidFrame[name] then
     bidFrame[name]:SetNormalFontObject(font)
    end
   end
  end
 end
 do
  local function expandFrame(bidFrame)
   if not bidFrame.hide:IsEnabled() then return end
   bidFrame.IsSmallWindow = false
   bidFrame.hide:SetText(L["折叠"])
   wa.UpdateButtonState(bidFrame)
   bidFrame.topMoneyFrame:Show()
   if not bidFrame.IsEnd and not bidFrame.isPaused then
    bidFrame.myMoneyEdit:Show()
   end
   bidFrame.itemFrame2:Show()
   bidFrame:SetSize(wa.WIDTH, wa.HEIGHT)
   bidFrame.itemFrame:ClearAllPoints()
   bidFrame.itemFrame:SetPoint("TOPLEFT", bidFrame, "TOPLEFT", wa.edgeSize + 1, -bidFrame.hide:GetHeight() - 3)
   bidFrame.itemFrame:SetPoint("BOTTOMRIGHT", bidFrame, "TOPRIGHT", -wa.edgeSize, -55)
   bidFrame.itemFrame.iconFrame:ClearAllPoints()
   bidFrame.itemFrame.iconFrame:SetPoint("TOPLEFT", bidFrame.itemFrame, "TOPLEFT", 0, 0)
   bidFrame.itemFrame.iconFrame:SetPoint("BOTTOMRIGHT", bidFrame.itemFrame, "TOPLEFT", bidFrame.itemFrame:GetHeight(), -bidFrame.itemFrame:GetHeight())
   bidFrame.itemFrame.iconFrame:SetBackdropBorderColor(unpack(bidFrame.itemFrame.iconFrame.color))
   bidFrame.itemFrame.itemNameText:ClearAllPoints()
   bidFrame.itemFrame.itemNameText:SetPoint("TOPLEFT", bidFrame.itemFrame.iconFrame, "TOPRIGHT", 2, -2)
   bidFrame.itemFrame.bg:ClearAllPoints()
   bidFrame.itemFrame.bg:SetAllPoints()
   bidFrame.bar:ClearAllPoints()
   bidFrame.bar:SetPoint("TOPLEFT", bidFrame.itemFrame.iconFrame, "TOPRIGHT", 0, 0)
   bidFrame.bar:SetPoint("BOTTOMRIGHT", bidFrame.itemFrame, "BOTTOMRIGHT", 0, 0)
   bidFrame.currentMoneyFrame:ClearAllPoints()
   bidFrame.currentMoneyFrame:SetPoint("TOPLEFT", bidFrame.itemFrame, "BOTTOMLEFT", 3, -3)
   if bidFrame.start then
    bidFrame.currentMoneyText:SetText(L["|cffFFD100起拍价：|r"] .. wa.FormatNumber(bidFrame.money))
   else
    bidFrame.currentMoneyText:SetText(L["|cffFFD100当前价格：|r"] .. wa.FormatNumber(bidFrame.money))
   end
   bidFrame.currentMoneyText:SetJustifyH("LEFT")
  end
  local function collapseFrame(bidFrame)
   if not bidFrame.hide:IsEnabled() then return end
   bidFrame.IsSmallWindow = true
   bidFrame.hide:SetText(L["展开"])
   wa.UpdateButtonState(bidFrame)
   bidFrame.autoFrame:Hide()
   bidFrame.topMoneyFrame:Hide()
   bidFrame.myMoneyEdit:Hide()
   bidFrame.itemFrame2:Hide()
   bidFrame:SetSize(wa.WIDTH, wa.SMALL_HEIGHT)
   bidFrame.itemFrame:ClearAllPoints()
   bidFrame.itemFrame:SetAllPoints()
   bidFrame.itemFrame.iconFrame:ClearAllPoints()
   bidFrame.itemFrame.iconFrame:SetPoint("TOPLEFT", wa.edgeSize, -wa.edgeSize)
   bidFrame.itemFrame.iconFrame:SetPoint("BOTTOMRIGHT", bidFrame.itemFrame, "TOPLEFT", bidFrame.itemFrame:GetHeight() - wa.edgeSize, -bidFrame.itemFrame:GetHeight() + wa.edgeSize)
   bidFrame.itemFrame.iconFrame:SetBackdropBorderColor(1, 1, 1, 0)
   bidFrame.itemFrame.itemNameText:ClearAllPoints()
   bidFrame.itemFrame.itemNameText:SetPoint("LEFT", bidFrame.itemFrame.iconFrame, "RIGHT", 2, 0)
   bidFrame.itemFrame.bg:ClearAllPoints()
   bidFrame.itemFrame.bg:SetPoint("TOPLEFT", wa.edgeSize, -wa.edgeSize)
   bidFrame.itemFrame.bg:SetPoint("BOTTOMRIGHT", -wa.edgeSize, wa.edgeSize)
   bidFrame.bar:ClearAllPoints()
   bidFrame.bar:SetPoint("TOPLEFT", bidFrame.itemFrame.iconFrame, "TOPRIGHT", 0, 0)
   bidFrame.bar:SetPoint("BOTTOMRIGHT", bidFrame.itemFrame, "BOTTOMRIGHT", -wa.edgeSize, wa.edgeSize)
   bidFrame.currentMoneyFrame:ClearAllPoints()
   bidFrame.currentMoneyFrame:SetPoint("RIGHT", bidFrame.hide, "LEFT", -5, -0)
   if bidFrame.start then
    bidFrame.currentMoneyText:SetText("")
   else
    bidFrame.currentMoneyText:SetText(wa.FormatNumber(bidFrame.money))
   end
   bidFrame.currentMoneyText:SetJustifyH("RIGHT")
  end
  function wa.Hide_OnClick(self, button)
   local bidFrame = self.owner
   local layoutFunc = bidFrame.IsSmallWindow and expandFrame or collapseFrame
   if (IsAltKeyDown() or button == "RightButton") and not bidFrame.notClick then
    for k, bidFrame in pairs(BGA.Frames) do
     layoutFunc(bidFrame)
    end
   else
    layoutFunc(bidFrame)
   end
   if not bidFrame.notClick then
    wa.UpdateAllOnEnters()
    wa.UpdateAllFrames()
    PlaySound(wa.sound1)
   end
  end
  function wa.Hide_OnEnter(self)
   local bidFrame = self.owner
   if wa.IsRight(self) then
    GameTooltip:SetOwner(bidFrame, "ANCHOR_LEFT", 0, 0)
   else
    GameTooltip:SetOwner(bidFrame, "ANCHOR_RIGHT", 0, 0)
   end
   GameTooltip:ClearLines()
   if bidFrame.IsSmallWindow then
    GameTooltip:AddLine(L["展开"], 1, 1, 1, true)
    GameTooltip:AddLine(L["左键：单个展开"], 1, 0.82, 0, true)
    GameTooltip:AddLine(L["右键：全部展开"], 1, 0.82, 0, true)
   else
    GameTooltip:AddLine(L["折叠"], 1, 1, 1, true)
    GameTooltip:AddLine(L["左键：单个折叠"], 1, 0.82, 0, true)
    GameTooltip:AddLine(L["右键：全部折叠"], 1, 0.82, 0, true)
   end
   GameTooltip:Show()
   self.isOnEnter = true
  end
 end
 function wa.SendAddonMessage(bidFrame, ...)
  local separator = bidFrame.isGen2 and "^" or ","
  local buffer = ""
  for i, part in ipairs({ ... }) do
   buffer = buffer .. (i == 1 and "" or separator) .. part
  end
  C_ChatInfo.SendAddonMessage(bidFrame.isGen2 and wa.GetAddonChannelName() or wa.AddonChannel, buffer, "RAID")
 end
 do
  function wa.Cancel_OnClick(self)
   local bidFrame = self.owner
   wa.SendAddonMessage(bidFrame, "CancelAuction", bidFrame[auctionID])
   PlaySound(wa.sound1)
  end
  function wa.Cancel_OnEnter(self)
   local bidFrame = self.owner
   if wa.IsRight(self) then
    GameTooltip:SetOwner(bidFrame, "ANCHOR_LEFT", 0, 0)
   else
    GameTooltip:SetOwner(bidFrame, "ANCHOR_RIGHT", 0, 0)
   end
   GameTooltip:ClearLines()
   GameTooltip:AddLine(self:GetText(), 1, 1, 1, true)
   GameTooltip:AddLine(L["Alt+点击才能生效"], 1, 0.82, 0, true)
   GameTooltip:AddLine(L["只有团长或物品分配者有权限取消拍卖"], 0.5, 0.5, 0.5, true)
   GameTooltip:Show()
  end
 end
 do
  function wa.Pause_OnClick(self)
   local bidFrame = self.owner
   wa.SendAddonMessage(bidFrame, bidFrame.isPaused and "ResumeAuction" or "PauseAuction", bidFrame.itemID)
   PlaySound(wa.sound1)
  end
  function wa.PauseAuction(bidFrame)
   if bidFrame.IsEnd or bidFrame.isPaused then return end
   bidFrame.isPaused = true
   bidFrame.pausedRemaining = bidFrame.endTime - wa.Now()
   bidFrame.myMoneyEdit:Hide()
   bidFrame.ButtonJian:Hide()
   bidFrame.ButtonJia:Hide()
   bidFrame.ButtonSendMyMoney:Hide()
   bidFrame.remainingTime:SetText(L["已暂停"])
   bidFrame.remainingTime:SetTextColor(1, 1, 0)
   wa.UpdateButtonState(bidFrame)
  end
  function wa.ResumeAuction(bidFrame)
   if bidFrame.IsEnd or not bidFrame.isPaused then return end
   bidFrame.isPaused = false
   bidFrame.endTime = wa.Now() + bidFrame.pausedRemaining
   bidFrame.pausedRemaining = nil
   bidFrame.myMoneyEdit:Show()
   bidFrame.ButtonJian:Show()
   bidFrame.ButtonJia:Show()
   bidFrame.ButtonSendMyMoney:Show()
   wa.RefreshTimer(bidFrame)
   wa.AutoSendMyMoney(bidFrame)
   wa.UpdateButtonState(bidFrame)
  end
 end
 do
  local function buildLogTooltip(bidFrame, i)
   local timeText = bidFrame.logs[i].time and L["剩余%s秒时出价"]:format(bidFrame.logs[i].time) or ""
   GameTooltip:AddLine(format(L["%s、%s（%s）|cffff0000%s"], i, bidFrame.logs[i].money, bidFrame.logs[i].player, timeText), 1, .82, 0, true)
  end
  function wa.LogTextButton_OnEnter(self)
   self.isOnEnter = true
   local bidFrame = self.owner
   if wa.IsRight(self) then
    GameTooltip:SetOwner(bidFrame, "ANCHOR_LEFT", 0, 0)
   else
    GameTooltip:SetOwner(bidFrame, "ANCHOR_RIGHT", 0, 0)
   end
   GameTooltip:ClearLines()
   GameTooltip:AddLine(L["出价记录"], 1, 1, 1, true)
   if #bidFrame.logs == 0 then
    GameTooltip:AddLine(L["没有人出价"], .5, .5, .5, true)
   elseif #bidFrame.logs > 15 then
    GameTooltip:AddLine("......", .5, .5, .5, true)
    for i = #bidFrame.logs - 14, #bidFrame.logs do
     buildLogTooltip(bidFrame, i)
    end
   else
    for i = 1, #bidFrame.logs do
     buildLogTooltip(bidFrame, i)
    end
   end
   GameTooltip:Show()
  end
 end
 do
  function wa.itemOnEnter(self)
   local bidFrame = self.owner
   if bidFrame.IsSmallWindow then return end
   local anchor
   if wa.IsRight(self) then
    GameTooltip:SetOwner(self, "ANCHOR_LEFT", 0, 0)
    anchor = "LEFT"
   else
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
    anchor = "RIGHT"
   end
   GameTooltip:ClearLines()
   GameTooltip:SetHyperlink(self.link)
   if BG and BG.SetZUGSetTooltip then
    BG.SetZUGSetTooltip(self.itemID, anchor)
   end
   if IsControlKeyDown() then
    SetCursor("Interface/Cursor/Inspect")
   end
   self.isOnEnter = true
   wa.itemIsOnEnter = true
   if BG then
    if BG.Show_AllHighlight then
     BG.Show_AllHighlight(self.link)
    end
   end
  end
  function wa.itemOnLeave(self)
   GameTooltip:Hide()
   self.isOnEnter = false
   wa.itemIsOnEnter = false
   SetCursor(nil)
   if BG then
    if BG.Hide_AllHighlight then
     BG.Hide_AllHighlight()
    end
   end
  end
 end
 do
  function wa.JiaJian(money, delta, op)
   if op == "+" then
    return money + delta
   elseif op == "-" then
    if money - delta > 0 then
     return money - delta
    elseif (money == delta) and money ~= 1 then
     return money - 10
    else
     return 0
    end
   end
  end
  function wa.Addmoney(money, op)
   local money = tonumber(money) or 0
   local delta
   for i, tier in ipairs(wa.MiniMoneyTbl) do
    if not tier[1] or money < tier[1] then
     delta = tier[2]
     break
    end
   end
   return wa.JiaJian(money, delta, op), delta
  end
  function wa.TooSmallMoney(amount, threshold)
   local money = amount - threshold
   for i, tier in ipairs(wa.MiniMoneyTbl) do
    if not tier[1] or threshold < tier[1] then
     if money < tier[3] then
      return tier[3]
     else
      return false
     end
    end
   end
  end
  function wa.TooSmall(self)
   local amount = tonumber(self:GetText()) or 0
   local threshold = self.owner.money
   return wa.TooSmallMoney(amount, threshold)
  end
  function wa.currentMoney_OnMouseDown(self)
   self.owner:GetScript("OnMouseDown")(BGA.AuctionMainFrame)
  end
  function wa.currentMoney_OnMouseUp(self)
   local bidFrame = self.owner
   bidFrame:GetScript("OnMouseUp")(BGA.AuctionMainFrame)
  end
  function wa.myMoney_OnTextChanged(self)
   local bidFrame = self.owner
   local money = tonumber(self:GetText()) or 0
   if bidFrame.start then
    if money < bidFrame.money then
     self:SetTextColor(1, 0, 0)
     bidFrame.ButtonSendMyMoney:Disable()
     if not wa.IsMe(bidFrame) then
      bidFrame.ButtonSendMyMoney.disf:Show()
      bidFrame.ButtonSendMyMoney.disf.text = L["需高于或等于起拍价"]
     end
    else
     self:SetTextColor(1, 1, 1)
     bidFrame.ButtonSendMyMoney:Enable()
     bidFrame.ButtonSendMyMoney.disf:Hide()
    end
   elseif money <= bidFrame.money then
    bidFrame.ButtonSendMyMoney:Disable()
    if wa.IsMe(bidFrame) then
     self:SetTextColor(1, 1, 1)
    else
     self:SetTextColor(1, 0, 0)
     bidFrame.ButtonSendMyMoney.disf:Show()
     bidFrame.ButtonSendMyMoney.disf.text = L["需高于当前价格"]
    end
   elseif wa.TooSmall(self) then
    self:SetTextColor(1, 0, 0)
    bidFrame.ButtonSendMyMoney:Disable()
    bidFrame.ButtonSendMyMoney.disf:Show()
    bidFrame.ButtonSendMyMoney.disf.text = format(L["最小加价幅度为%s"], wa.TooSmall(self))
   else
    self:SetTextColor(1, 1, 1)
    bidFrame.ButtonSendMyMoney:Enable()
    bidFrame.ButtonSendMyMoney.disf:Hide()
   end
   if money <= bidFrame.money then
    bidFrame.ButtonJian:Disable()
   else
    bidFrame.ButtonJian:Enable()
   end
   wa.UpdateAllOnEnters()
  end
  function wa.myMoney_OnMouseWheel(self, delta)
   local op = "-"
   if delta == 1 then
    op = "+"
   end
   if op == "-" then
    local bidFrame = self.owner
    local price = tonumber(self:GetText())
    if price and price <= bidFrame.money then
     return
    end
   end
   self:SetText(wa.Addmoney(self:GetText(), op))
  end
  function wa.myMoney_OnEnter(self)
   GameTooltip:SetOwner(self.owner, "ANCHOR_BOTTOM", 0, 0)
   GameTooltip:ClearLines()
   GameTooltip:AddLine(wa.FormatNumber(self:GetText()), 1, 1, 1)
   GameTooltip:AddLine(L["滚轮：快速调整价格"], 1, 0.82, 0, true)
   GameTooltip:Show()
   self.isOnEnter = true
  end
  function wa.JiaJian_OnEnter(self)
   local bidFrame = self.owner
   local price = tonumber(self.edit:GetText()) or 0
   local k, delta = wa.Addmoney(price, self._type)
   GameTooltip:SetOwner(bidFrame, "ANCHOR_BOTTOM", 0, 0)
   GameTooltip:ClearLines()
   if not bidFrame.start and not bidFrame.IsEnd and not wa.IsMe(bidFrame) and self._type == "+" and price <= bidFrame.money then
    GameTooltip:AddLine(L["出价设为："] .. "|cffffffff" .. wa.FormatNumber(wa.Addmoney(bidFrame.money, "+")), 1, 0.82, 0, true)
   else
    local r, g, b = 1, 0, 0
    if self._type == "+" then
     r, g, b = 0, 1, 0
    end
    GameTooltip:AddLine(self._type .. " " .. wa.FormatNumber(delta), r, g, b, true)
    GameTooltip:AddLine(L["根据你的出价动态改变增减幅度"], 1, 0.82, 0, true)
    GameTooltip:AddLine(L["长按：快速调整价格"], 1, 0.82, 0, true)
   end
   GameTooltip:Show()
   self.isOnEnter = true
  end
  function wa.JiaJian_OnClick(self)
   local bidFrame = self.owner
   local price = tonumber(self.edit:GetText()) or 0
   if not bidFrame.start and not bidFrame.IsEnd and not wa.IsMe(bidFrame) and self._type == "+" and price <= bidFrame.money then
    self.edit:SetText(wa.Addmoney(bidFrame.money, "+"))
   else
    self.edit:SetText(wa.Addmoney(price, self._type))
   end
   wa.UpdateAllOnEnters()
   PlaySound(wa.sound1)
  end
  function wa.JiaJian_OnMouseDown(self)
   local holdTime = 0
   local longPressTime = 0.5
   self:SetScript("OnUpdate", function(self, elapsed)
    holdTime = holdTime + elapsed
    if not self:IsEnabled() then
     self:SetScript("OnUpdate", nil)
     return
    end
    if holdTime >= longPressTime then
     holdTime = longPressTime - 0.1
     self.edit:SetText(wa.Addmoney(self.edit:GetText(), self._type))
     wa.JiaJian_OnEnter(self)
    end
   end)
  end
  function wa.JiaJian_OnMouseUp(self)
   self:SetScript("OnUpdate", nil)
  end
 end
 do
  local function sendMoney(bidFrame)
   if bidFrame.ButtonSendMyMoney:IsEnabled() then
    local money = tonumber(bidFrame.myMoneyEdit:GetText()) or 0
    wa.SendMyMoneyMsg(bidFrame, money)
    bidFrame.myMoneyEdit:ClearFocus()
    PlaySound(wa.sound1)
   end
  end
  -- 统一出价发送：按模式选择匿名/普通通道。IsEnabled 门保留在各调用点（SendMyMoney_OnClick），
  -- 不得收进本函数——否则自动出价路径在按钮禁用态会被意外加门而静默失效。
  function wa.SendMyMoneyMsg(bidFrame, money)
   wa.SendAddonMessage(bidFrame, "SendMyMoney", bidFrame[auctionID], money)
  end
  function wa.SendMyMoney_OnClick(self)
   local bidFrame = self.owner
   if bidFrame.ButtonSendMyMoney:IsEnabled() then
    self.cd = self.cd or 0
    if wa.Now() - self.cd < 1 then return end
    self.cd = wa.Now()
    if wa.IsMe(bidFrame) then
     if not StaticPopupDialogs["BiaoGeAuction_RepeatSend"] then
      StaticPopupDialogs["BiaoGeAuction_RepeatSend"] = {
       text = L["你已是%s的出价最高者，|cffff0000没必要自己顶自己|r。真的要继续出价到 %s ？"],
       button1 = YES,
       button2 = NO,
       OnCancel = function()
       end,
       timeout = 0,
       whileDead = true,
       hideOnEscape = true,
       showAlert = true,
      }
     end
     StaticPopupDialogs["BiaoGeAuction_RepeatSend"].OnAccept = function()
      sendMoney(bidFrame)
     end
     StaticPopup_Show("BiaoGeAuction_RepeatSend", bidFrame.link, tonumber(bidFrame.myMoneyEdit:GetText()) or 0)
    else
     sendMoney(bidFrame)
    end
   end
  end
  function wa.SetMoney(bidFrame, money, player)
   if not bidFrame.IsSmallWindow then
    bidFrame.updateFrame:Show()
    bidFrame.autoFrame.updateFrame:Show()
   end
   if not bidFrame.isAuto and BG and BG.PlayTopPriceSound then
    BG.PlayTopPriceSound(bidFrame, player)
   end
   bidFrame.money = money
   if bidFrame.IsSmallWindow then
    bidFrame.currentMoneyText:SetText(wa.FormatNumber(money))
   else
    bidFrame.currentMoneyText:SetText(L["|cffFFD100当前价格：|r"] .. wa.FormatNumber(money))
    bidFrame.myMoneyEdit:Show()
   end
   bidFrame.player = player
   bidFrame.colorplayer = wa.SetClassCFF(player)
   bidFrame.start = false
   local isLate = ((bidFrame.remaining or 10) <= wa.tooLateTime) and format("%.1f", bidFrame.remaining) or nil
   if player == wa.GN() then
    bidFrame.topMoneyText:SetText(L["|cffFFD100出价最高者：|r"] .. "|cff" .. wa.GREEN1 .. L[">> 你 <<"])
    wa.SetFrameColor(bidFrame, 1)
    tinsert(bidFrame.logs, { money = money, player = "|cff" .. wa.GREEN1 .. L["你"] .. "|r", time = isLate })
    if isLate then
     SendChatMessage(format(L["%s的剩余时间不到%s秒时我出价%s。卡秒出价可能导致拍卖出错！"], bidFrame.link, isLate, bidFrame.money), "RAID")
     if BG and BG.PlaySound then
      BG.PlaySound("tooLate")
     end
    end
   else
    bidFrame.topMoneyText:SetText(L["|cffFFD100出价最高者：|r"] .. bidFrame.colorplayer)
    tinsert(bidFrame.logs, { money = money, player = bidFrame.colorplayer, time = isLate })
    if bidFrame.filter then
     wa.SetFrameColor(bidFrame, 2)
    else
     wa.SetFrameColor(bidFrame, 0)
    end
    if bidFrame.isAuto then
     bidFrame.autoSendDelayFrame.t = 0
     bidFrame.autoSendDelayFrame.delay = wa.AutoSendLate()
     bidFrame.autoSendDelayFrame:SetScript("OnUpdate", function(self, elapsed)
      self.t = self.t + elapsed
      if self.t >= self.delay then
       wa.AutoSendMyMoney(bidFrame)
       self:SetScript("OnUpdate", nil)
      end
     end)
    end
   end
   wa.myMoney_OnTextChanged(bidFrame.myMoneyEdit)
   if bidFrame.isAuto and (bidFrame.money >= bidFrame.autoMoney or wa.TooSmallMoney(bidFrame.autoMoney, bidFrame.money)) then
    bidFrame.autoTitleText:SetText(L["设置心理价格"])
    bidFrame.autoTitleText:SetTextColor(1, .82, 0)
    bidFrame.isAutoTex:Hide()
    bidFrame.autoButton:SetText(L["开启自动出价"])
    bidFrame.autoButton:Enable()
    bidFrame.autoMoneyEdit.Left:SetAlpha(1)
    bidFrame.autoMoneyEdit.Right:SetAlpha(1)
    bidFrame.autoMoneyEdit.Middle:SetAlpha(1)
    bidFrame.isAuto = false
    bidFrame.autoSendDelayFrame:SetScript("OnUpdate", nil)
    bidFrame.autoTextButton:SetText(L["自动出价"])
    bidFrame.autoTextButton:SetWidth(bidFrame.autoTextButton:GetFontString():GetWidth())
    bidFrame.autoMoneyEdit:SetTextColor(1, 1, 1)
    bidFrame.autoMoneyEdit:SetEnabled(true)
    bidFrame.autoMoneyEdit.isLocked = false
    bidFrame.hide:Enable()
    wa.AutoSendEndPlaySound()
   end
   wa.Auto_OnTextChanged(bidFrame.autoMoneyEdit)
   wa.RefreshTimer(bidFrame)
   if bidFrame.isGen2 then
    for k, otherFrame in pairs(BGA.Frames) do
     if otherFrame ~= bidFrame and otherFrame.itemID == bidFrame.itemID then
      wa.RefreshTimer(otherFrame)
     end
    end
   end
   -- 新高价到达即取消自动出价 ticker（v2.3.5 三处取消点之①）：避免旧 ticker 在延迟出价后重复顶价，
   -- 重投时机交给上方的 autoSendDelayFrame。
   if bidFrame.autoTimer then
    bidFrame.autoTimer:Cancel()
   end
  end
  function wa.SendMyMoney_OnEnter(self)
   self.isOnEnter = true
  end
  function wa.SendMyMoneyDis_OnEnter(self)
   local bidFrame = self.owner
   GameTooltip:SetOwner(self.owner, "ANCHOR_BOTTOM", 0, 0)
   GameTooltip:ClearLines()
   GameTooltip:AddLine(self.text, 1, 0, 0, true)
   GameTooltip:Show()
  end
 end
 do
  function wa.UpdateAllOnEnters()
   for k, bidFrame in pairs(BGA.Frames) do
    if bidFrame.myMoneyEdit.isOnEnter then
     wa.myMoney_OnEnter(bidFrame.myMoneyEdit)
    end
    if bidFrame.ButtonJian.isOnEnter then
     wa.JiaJian_OnEnter(bidFrame.ButtonJian)
    end
    if bidFrame.ButtonJia.isOnEnter then
     wa.JiaJian_OnEnter(bidFrame.ButtonJia)
    end
    if bidFrame.ButtonSendMyMoney.isOnEnter then
     wa.SendMyMoney_OnEnter(bidFrame.ButtonSendMyMoney)
    end
    if bidFrame.logTextButton.isOnEnter then
     bidFrame.logTextButton:GetScript("OnEnter")(bidFrame.logTextButton)
    end
    if bidFrame.autoMoneyEdit.isOnEnter then
     wa.AutoEdit_OnEnter(bidFrame.autoMoneyEdit)
    end
    if bidFrame.hide.isOnEnter then
     wa.Hide_OnEnter(bidFrame.hide)
    end
   end
  end
  function wa.GetFrameTotolHeight(count)
   local height = 0
   for i = 1, count - 1 do
    local bidFrame = BGA.Frames[i]
    if bidFrame then
     if bidFrame.IsSmallWindow then
      height = height + wa.SMALL_HEIGHT + 5
     else
      height = height + wa.HEIGHT + 5
     end
    end
   end
   return height
  end
  local function arrangeFrames()
   local idx = 0
   local frames = {}
   for i = 1, wa.maxNumFrame do
    local bidFrame = BGA.Frames[i]
    if bidFrame then
     idx = idx + 1
     bidFrame.num = idx
     frames[idx] = bidFrame
    end
   end
   BGA.Frames = frames
  end
  function wa.UpdateAllFrames()
   arrangeFrames()
   for k, bidFrame in pairs(BGA.Frames) do
    if bidFrame.showCantClickFrame and not bidFrame.IsSmallWindow then
     bidFrame.cantClickFrame:Show()
     bidFrame.cantClickFrame.t = 0
     bidFrame.cantClickFrame:SetScript("OnUpdate", function(self, elapsed)
      self.t = self.t + elapsed
      if self.t >= .8 then
       self:SetScript("OnUpdate", nil)
       self:Hide()
      end
     end)
    end
    bidFrame:ClearAllPoints()
    bidFrame:SetPoint("TOP", 0, -wa.GetFrameTotolHeight(bidFrame.num))
   end
  end
  function wa.UpdateFrame(bidFrame)
   local alpha = 1
   bidFrame:SetScript("OnUpdate", function(self, elapsed)
    alpha = alpha - elapsed
    if alpha >= 0 then
     bidFrame:SetAlpha(alpha)
    else
     bidFrame:SetScript("OnUpdate", nil)
     BGA.Frames[bidFrame.num] = nil
     bidFrame:Hide()
     BGA.AuctionMainFrame:StopMovingOrSizing()
     if BG and BG.options and BiaoGe.options.autoAuctionUp == 1 then
      for k, otherFrame in pairs(BGA.Frames) do
       if otherFrame.num < bidFrame.num then
        otherFrame.showCantClickFrame = false
       else
        otherFrame.showCantClickFrame = true
       end
      end
      wa.UpdateAllFrames()
     end
    end
   end)
  end
  function wa.UpdateButtonState(bidFrame)
   local btn = bidFrame.cancelButton
   btn:ClearAllPoints()
   if bidFrame.isGen2 then
    btn:SetText(CANCEL)
    btn:SetPoint("TOP", bidFrame, "TOPLEFT", wa.WIDTH / 10 * 3, -2)
   else
    btn:SetText(L["取消拍卖"])
    btn:SetPoint("TOP", bidFrame, "TOPLEFT", wa.WIDTH / 10 * 3.3, -2)
   end
   btn:SetSize(btn:GetFontString():GetWidth() + 10, 18)
   btn:SetShown(wa.IsML() and not bidFrame.IsEnd and not bidFrame.IsSmallWindow)
   local btn = bidFrame.puaseButton
   if btn then
    btn:SetText(bidFrame.isPaused and L["恢复"] or L["暂停"])
    btn:SetSize(btn:GetFontString():GetWidth() + 10, 18)
    btn:SetShown(wa.IsML() and not bidFrame.IsEnd and not bidFrame.IsSmallWindow)
   end
   local btn = bidFrame.autoTextButton
   btn:ClearAllPoints()
   if wa.IsML() then
    if bidFrame.isGen2 then
     btn:SetPoint("TOP", bidFrame, "TOPLEFT", wa.WIDTH / 10 * 7, -2)
     btn:SetText(L["自动"])
    else
     btn:SetPoint("TOP", bidFrame, "TOPLEFT", btn.offset, -2)
     btn:SetText(L["自动出价"])
    end
   else
    btn:SetPoint("TOP", 0, -2)
    btn:SetText(L["自动出价"])
   end
   btn:SetSize(btn:GetFontString():GetWidth() + 10, 18)
   btn:SetShown(not bidFrame.IsSmallWindow)
   local btn = bidFrame.logTextButton
   btn:SetShown(not bidFrame.IsSmallWindow)
  end
 end
 do
  local function checkOverlap()
   for j = 1, wa.maxNumFrame do
    local bidFrame = BGA.Frames[j]
    if bidFrame and not bidFrame.animing then
     local top = bidFrame:GetTop()
     local bottom = bidFrame:GetBottom()
     for i = 1, wa.maxNumFrame do
      local otherFrame = BGA.Frames[i]
      if otherFrame and not otherFrame.animing and bidFrame.num ~= otherFrame.num then
       local otherTop = otherFrame:GetTop()
       local otherBottom = otherFrame:GetBottom()
       if (top <= otherTop and top >= otherBottom) or (bottom <= otherTop and bottom >= otherBottom) then
        wa.UpdateAllFrames()
        return
       end
      end
     end
    end
   end
  end
  function wa.anim(parent)
   parent.alltime = 0.5
   parent.t = 0.5
   parent.animing = true
   parent:SetScript("OnUpdate", function(self, delta)
    self.t = self.t - delta
    if self.t <= 0 then self.t = 0 end
    self:SetAlpha(max(1 - self.t / self.alltime, 0.01))
    self.myMoneyEdit:SetCursorPosition(0)
    if self.t <= 0 then
     self.animing = nil
     self:SetScript("OnUpdate", nil)
     After(0, function()
      checkOverlap()
     end)
    end
   end)
  end
 end
 do
  function wa.AutoText_OnClick(self)
   self.owner.autoFrame:SetShown(not self.owner.autoFrame:IsVisible())
   self.owner.autoFrame.isClicked = true
   PlaySound(wa.sound1)
  end
  function wa.Auto_OnTextChanged(self)
   local bidFrame = self.owner
   local money = tonumber(self:GetText()) or 0
   bidFrame.autoMoney = money
   bidFrame.autoButton:Enable()
   bidFrame.autoButton.disf:Hide()
   if not bidFrame.isAuto then
    local isMe = wa.IsMe(bidFrame)
    local isZero = money == 0
    local shouldTip = isZero and (bidFrame.start or not isMe)
    local tipMsg
    if not isZero then
     if bidFrame.start and money < bidFrame.money then
      isZero = true
      shouldTip = true
      if not isMe then
       tipMsg = L["心理价格需高于或等于起拍价"]
      end
     elseif not bidFrame.start and money <= bidFrame.money then
      isZero = true
      shouldTip = not isMe
      if not isMe then
       tipMsg = L["心理价格需高于当前价格"]
      end
     elseif not bidFrame.start then
      local minInc = wa.TooSmallMoney(money, bidFrame.money)
      if minInc then
       isZero = true
       shouldTip = true
       tipMsg = format(L["最小加价幅度为%s"], minInc)
      end
     end
    end
    if isZero then
     bidFrame.autoButton:Disable()
     if tipMsg then
      bidFrame.autoButton.onEnterText = tipMsg
      bidFrame.autoButton.disf:Show()
     end
    end
    if shouldTip then
     self:SetTextColor(1, 0, 0)
    else
     self:SetTextColor(1, 1, 1)
    end
   end
   wa.UpdateAllOnEnters()
  end
  function wa.AutoEdit_OnEnter(self)
   local bidFrame = self.owner
   GameTooltip:SetOwner(bidFrame.autoFrame, "ANCHOR_BOTTOM", 0, 0)
   GameTooltip:ClearLines()
   if self.isLocked then
    local money = self:GetText()
    if tonumber(money) then
     GameTooltip:AddLine(L["心理价格锁定中"] .. format(L["（%s）"], wa.FormatNumber(money)), 1, 0, 0, true)
    else
     GameTooltip:AddLine(L["心理价格锁定中"], 1, 0, 0, true)
    end
    GameTooltip:AddLine(L["取消自动出价后才能修改。"], 1, 0.82, 0, true)
   else
    local money = self:GetText()
    if tonumber(money) then
     GameTooltip:AddLine(L["自动出价"], 1, 1, 1, true)
     GameTooltip:AddLine(L["心理价格："] .. wa.FormatNumber(money), 1, 1, 1, true)
    else
     GameTooltip:AddLine(L["自动出价"], 1, 1, 1, true)
    end
    GameTooltip:AddLine(L["如果别人出价比你高时，自动帮你出价，每次加价为最低幅度，出价不会高于你设定的心理价格。"], 1, 0.82, 0, true)
   end
   GameTooltip:Show()
   self.isOnEnter = true
  end
  function wa.AutoButton_OnClick(self)
   local bidFrame = self.owner
   if not bidFrame.autoButton:IsEnabled() then return end
   if bidFrame.isAuto then
    bidFrame.isAuto = false
    bidFrame.autoSendDelayFrame:SetScript("OnUpdate", nil)
    bidFrame.autoTitleText:SetText(L["设置心理价格"])
    bidFrame.autoTitleText:SetTextColor(1, .82, 0)
    bidFrame.isAutoTex:Hide()
    bidFrame.autoButton:SetText(L["开启自动出价"])
    bidFrame.autoMoneyEdit.Left:SetAlpha(1)
    bidFrame.autoMoneyEdit.Right:SetAlpha(1)
    bidFrame.autoMoneyEdit.Middle:SetAlpha(1)
    bidFrame.autoTextButton:SetWidth(bidFrame.autoTextButton:GetFontString():GetWidth())
    bidFrame.autoMoneyEdit:SetTextColor(1, 1, 1)
    bidFrame.autoMoneyEdit:SetEnabled(true)
    bidFrame.autoMoneyEdit.isLocked = false
    bidFrame.hide:Enable()
   else
    bidFrame.isAuto = true
    bidFrame.autoTitleText:SetText(L["心理价格"])
    bidFrame.autoTitleText:SetTextColor(0, 1, 0)
    bidFrame.isAutoTex:Show()
    bidFrame.autoButton:SetText(L["取消自动出价"])
    bidFrame.autoMoneyEdit:ClearFocus()
    bidFrame.autoMoneyEdit.Left:SetAlpha(bidFrame.autoMoneyEdit.alpha)
    bidFrame.autoMoneyEdit.Right:SetAlpha(bidFrame.autoMoneyEdit.alpha)
    bidFrame.autoMoneyEdit.Middle:SetAlpha(bidFrame.autoMoneyEdit.alpha)
    bidFrame.autoTextButton:SetWidth(bidFrame.autoTextButton:GetFontString():GetWidth())
    bidFrame.autoMoneyEdit:SetTextColor(0, 1, 0)
    bidFrame.autoMoneyEdit:SetEnabled(false)
    bidFrame.autoMoneyEdit.isLocked = true
    wa.AutoSendMyMoney(bidFrame)
    bidFrame.hide:Disable()
   end
   wa.UpdateAllOnEnters()
   PlaySound(wa.sound1)
  end
  function wa.AutoButton_OnEnter(self)
   local bidFrame = self.owner
   GameTooltip:SetOwner(bidFrame.autoFrame, "ANCHOR_BOTTOM", 0, 0)
   GameTooltip:ClearLines()
   GameTooltip:AddLine(bidFrame.autoButton.onEnterText, 1, 0, 0, true)
   GameTooltip:Show()
  end
  function wa.AutoSendMyMoney(bidFrame)
   if bidFrame.IsEnd or not bidFrame.isAuto or bidFrame.isPaused then return end
   if wa.IsMe(bidFrame) then return end
   local newAmount
   if bidFrame.start then
    newAmount = bidFrame.money
   else
    newAmount = wa.Addmoney(bidFrame.money, "+")
    if newAmount > bidFrame.autoMoney and bidFrame.money < bidFrame.autoMoney then
     if wa.TooSmallMoney(bidFrame.autoMoney, bidFrame.money) then return end
     newAmount = bidFrame.autoMoney
    end
   end
   if newAmount <= bidFrame.autoMoney then
    wa.SendMyMoneyMsg(bidFrame, newAmount)
    -- v2.3.5 三处取消点之②：重建 ticker 前先取消旧 ticker，防堆叠
    if bidFrame.autoTimer then
     bidFrame.autoTimer:Cancel()
    end
    bidFrame.autoTimer = C_Timer.NewTicker(3, function()
     -- v2.3.5 三处取消点之③：回调开头自检，任一条件变化即取消并退出
     if bidFrame.IsEnd or not bidFrame.isAuto or bidFrame.isPaused or wa.IsMe(bidFrame) then
      if bidFrame.autoTimer then
       bidFrame.autoTimer:Cancel()
      end
      return
     end
     wa.AutoSendMyMoney(bidFrame)
    end)
   end
  end
  function wa.AutoSendEndPlaySound()
   if BiaoGe and BiaoGe.options and BiaoGe.options.autoAuctionAutoEndTips == 1 then
    BG.PlaySound("autoAuctionAutoEndTips")
   end
  end
  function wa.AutoSendLate()
   if BiaoGe and BiaoGe.options and BiaoGe.options.aotoSendLate == 1 then
    local delay = tonumber(BiaoGe.Auction.aotoSendLate)
    if delay then
     delay = min(max(delay, 1), 5)
     delay = random(1 * 10, delay * 10) / 10
     return delay
    end
   end
   if BG and BG.IsTitan then
    return 1.5 + random(-5, 5) / 100
   end
   return 0.5 + random(-5, 5) / 100
  end
 end
 function wa.SetEndState(bidFrame, text, r, g, b, barNotHide)
  if not bidFrame.endText then
   bidFrame.endText = bidFrame.itemFrame2:CreateFontString()
   bidFrame.endText:SetFont(font, 30, "OUTLINE")
   bidFrame.endText:SetPoint("TOPRIGHT", bidFrame.itemFrame, "BOTTOMRIGHT", -10, -5)
  end
  bidFrame.endText:SetText(text)
  bidFrame.endText:SetTextColor(r, g, b)
  bidFrame.remainingTime:Hide()
  if not barNotHide then
   bidFrame.bar:Hide()
  end
  bidFrame.IsEnd = true
  bidFrame.autoSendDelayFrame:SetScript("OnUpdate", nil)
  bidFrame.myMoneyEdit:Hide()
  bidFrame.cancelButton:Hide()
  bidFrame.hide:Disable()
  wa.UpdateButtonState(bidFrame)
  return bidFrame.endText
 end
 local function updateEndState(bidFrame)
  if bidFrame.player and bidFrame.player ~= "" then
   wa.SetEndState(bidFrame, L["拍卖成功"], 0, 1, 0)
   if bidFrame.IsSmallWindow then
    bidFrame.currentMoneyText:SetText("|cff00FF00" .. wa.FormatNumber(bidFrame.money))
   else
    bidFrame.currentMoneyText:SetText(L["|cff00FF00成交价：|r"] .. wa.FormatNumber(bidFrame.money))
   end
   if bidFrame.player == wa.GN() then
    bidFrame.topMoneyText:SetText(L["|cff00FF00买家：|r"] .. "|cff" .. wa.GREEN1 .. L[">> 你 <<"])
   else
    bidFrame.topMoneyText:SetText(L["|cff00FF00买家：|r"] .. bidFrame.colorplayer)
   end
   if wa.IsRaidLeader() then
    After(.2, function()
     if not wa.InBoss() then
      SendChatMessage(format(L["{rt6}拍卖成功{rt6} %s %s %s"], bidFrame.link, bidFrame.player, bidFrame.money), "RAID")
     end
    end)
   end
   if BG and BG.AuctionWAEnd then
    BG.AuctionWAEnd(1, bidFrame.link, bidFrame.player, bidFrame.money, bidFrame.logs)
   end
  else
   wa.SetEndState(bidFrame, L["流拍"], 1, 0, 0)
   if bidFrame.IsSmallWindow then
    bidFrame.currentMoneyText:SetText(L["|cffFF0000流拍"])
   else
    bidFrame.currentMoneyText:SetText(L["|cffFF0000流拍：|r"] .. wa.FormatNumber(bidFrame.money))
   end
   bidFrame.topMoneyText:SetText("")
   if wa.IsRaidLeader() then
    if not wa.InBoss() then
     SendChatMessage(format(L["{rt7}流拍{rt7} %s"], bidFrame.link), "RAID")
    end
   end
   if BG and BG.AuctionWAEnd then
    BG.AuctionWAEnd(2, bidFrame.link, bidFrame.player, bidFrame.money)
   end
  end
  After(wa.HIDEFRAME_TIME, function()
   wa.UpdateFrame(bidFrame)
  end)
 end
 function wa.Auctioning(bidFrame, duration)
  bidFrame.bar:Show()
  bidFrame.endTime = wa.Now() + duration
  bidFrame.bar:SetScript("OnUpdate", function(self, elapsed)
   local remaining = tonumber(format("%.3f", bidFrame.endTime - wa.Now()))
   if bidFrame.isPaused then
    return
   end
   local progress = remaining / duration
   local sender, max = bidFrame.bar:GetMinMaxValues()
   local entry = progress * max
   bidFrame.bar:SetValue(entry)
   if remaining <= 10 then
    if bidFrame.filter and not wa.IsMe(bidFrame) then
     bidFrame.bar:SetStatusBarColor(unpack(BGA.aura_env.barColor_filter))
    else
     bidFrame.bar:SetStatusBarColor(1, 0, 0, 0.6)
    end
    bidFrame.remainingTime:SetTextColor(1, 0, 0)
    bidFrame.remainingTime:SetFont(font, 20, "OUTLINE")
   else
    if bidFrame.filter and not wa.IsMe(bidFrame) then
     bidFrame.bar:SetStatusBarColor(unpack(BGA.aura_env.barColor_filter))
    else
     bidFrame.bar:SetStatusBarColor(1, 1, 0, 0.6)
    end
    bidFrame.remainingTime:SetTextColor(1, 1, 1)
    bidFrame.remainingTime:SetFont(font, 15, "OUTLINE")
   end
   bidFrame.remainingTime:SetText((remaining <= 0 and 0 or (format("%d", remaining) + 1)) .. "s")
   bidFrame.remaining = remaining
   if remaining <= 1 then
    bidFrame.myMoneyEdit:Hide()
   end
   if remaining <= -0.5 then
    updateEndState(bidFrame)
   end
  end)
 end
 function wa.RefreshTimer(bidFrame)
  if bidFrame.IsEnd or bidFrame.isPaused then return end
  if bidFrame.remaining and bidFrame.remaining <= bidFrame.resetThreshold then
   wa.Auctioning(bidFrame, bidFrame.resetThreshold)
  end
 end
end)