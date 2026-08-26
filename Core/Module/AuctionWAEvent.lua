if BG.IsBlackListPlayer then return end
local addonName, ns = ...
local LibBG = ns.LibBG
local L = ns.L
local print = print
local After = C_Timer.After
local auctionIdKey = "auctionID"
BG.Init(function()
 local font = BIAOGE_TEXT_FONT or STANDARD_TEXT_FONT
 local wa = BGA.aura_env
 local function createMenuItem(parentFrame, text, onClickFunc)
  local button = CreateFrame("Button", nil, parentFrame)
  button:SetNormalFontObject(BGA.FontWhite15)
  button:SetText(text)
  local fontString = button:GetFontString()
  local width = fontString:GetWidth() + 30
  fontString:SetJustifyH("LEFT")
  button:SetSize(width, 20)
  button:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, -(#parentFrame.buttons * 20 + 10))
  button.owner = parentFrame.owner
  tinsert(parentFrame.buttons, button)
  parentFrame:SetHeight(#parentFrame.buttons * 20 + 20)
  parentFrame:SetWidth(max(width, parentFrame:GetWidth() or 0))
  if onClickFunc then
   fontString:SetTextColor(1, 1, 1)
   button:SetScript("OnClick", function(self)
    onClickFunc(self)
    parentFrame:Hide()
   end)
   local highlightTex = button:CreateTexture()
   highlightTex:SetAllPoints()
   highlightTex:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
   highlightTex:SetVertexColor(1, .82, 0)
   button:SetHighlightTexture(highlightTex)
  else
   fontString:SetTextColor(1, .82, 0)
   button:Disable()
  end
  return button
 end
 function wa.ShowMenu(self)
  local frame = self.owner
  if frame.menuFrame and frame.menuFrame:IsVisible() then
   frame.menuFrame:Hide()
   return
  end
  if not frame.menuFrame then
   local menuFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
   menuFrame:SetBackdrop({
    bgFile = "Interface/ChatFrame/ChatFrameBackground",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
   })
   menuFrame:SetBackdropColor(0, 0, 0, 1)
   menuFrame:SetBackdropBorderColor(1, 1, 1, 1)
   menuFrame:SetFrameLevel(frame:GetFrameLevel() + 20)
   menuFrame:SetPoint("BOTTOM", self, "TOP", 0, -1)
   menuFrame:EnableMouse(true)
   menuFrame:SetClampedToScreen(true)
   menuFrame.buttons = {}
   menuFrame.owner = frame
   frame.menuFrame = menuFrame
   menuFrame:SetScript("OnUpdate", function()
    if not self:IsMouseOver() and not menuFrame:IsMouseOver() then
     menuFrame:Hide()
    end
   end)
  end
  frame.menuFrame:Show()
  for i = #frame.menuFrame.buttons, 1, -1 do
   local menuItem = frame.menuFrame.buttons[i]
   menuItem:Hide()
   menuItem:SetParent(nil)
   tremove(frame.menuFrame.buttons, i)
  end
  createMenuItem(frame.menuFrame, L["更多操作"])
  createMenuItem(frame.menuFrame, L["取消拍卖"], wa.Cancel_OnClick)
  createMenuItem(frame.menuFrame, frame.isPaused and L["恢复拍卖"] or L["暂停拍卖"], wa.Pause_OnClick)
  for i, menuItem in ipairs(frame.menuFrame.buttons) do
   local width = frame.menuFrame:GetWidth()
   menuItem:SetWidth(width)
   menuItem:GetFontString():SetWidth(width - 30)
  end
 end
 function wa.CreateAuction(auctionID, itemID, money, duration, player, mod, link, resetThreshold, isGen2)
  for minLevel, frame in pairs(BGA.Frames) do
   if frame[auctionIdKey] == auctionID then
    return
   end
  end
  local itemName, link, rarity, itemLevel, minLevel, itemType, itemSubType, minLevel, equipLoc, icon,
  minLevel, sellPrice, classID, subclassID = GetItemInfo(link or itemID)
  local auctionFrame
  mod = isGen2 and mod or "normal"
  do
   local frame = CreateFrame("Frame", nil, BGA.AuctionMainFrame, "BackdropTemplate")
   frame:SetBackdrop({
    bgFile = "Interface/ChatFrame/ChatFrameBackground",
    edgeFile = "Interface/ChatFrame/ChatFrameBackground",
    edgeSize = wa.edgeSize,
   })
   frame:SetBackdropColor(unpack(wa.backdropColor))
   frame:SetBackdropBorderColor(unpack(wa.backdropBorderColor))
   frame:SetSize(wa.WIDTH, wa.HEIGHT)
   if #BGA.Frames == 0 then
    frame:SetPoint("TOP")
    frame.num = 1
   else
    for i = 1, wa.maxNumFrame do
     if not BGA.Frames[i] then
      frame.num = i
      frame:SetPoint("TOP", 0, -wa.GetFrameTotolHeight(frame.num))
      break
     end
    end
   end
   frame:EnableMouse(true)
   frame[auctionIdKey] = auctionID
   frame.itemID = itemID
   frame.link = link
   frame.mod = mod
   frame.logs = {}
   frame.resetThreshold = resetThreshold
   frame.isGen2 = isGen2
   auctionFrame = frame
   BGA.Frames[frame.num] = frame
   frame:SetScript("OnMouseUp", function(self)
    local mainFrame = BGA.AuctionMainFrame
    mainFrame:StopMovingOrSizing()
    if BiaoGe and BiaoGe.point then
     BiaoGe.point.Auction = { mainFrame:GetPoint(1) }
    end
    mainFrame:SetScript("OnUpdate", nil)
   end)
   frame:SetScript("OnMouseDown", function(self)
    if wa.lastFocus then
     wa.lastFocus:ClearFocus()
    end
    if BiaoGe and BiaoGe.options and BiaoGe.options.auctionMoveByShift == 1
     and not IsShiftKeyDown() then
     return
    end
    local mainFrame = BGA.AuctionMainFrame
    mainFrame:StartMoving()
    mainFrame.time = 0
    mainFrame:SetScript("OnUpdate", function(self, time)
     mainFrame.time = mainFrame.time + time
     if mainFrame.time >= 0.2 then
      mainFrame.time = 0
      for minLevel, frame in pairs(BGA.Frames) do
       if frame.itemFrame.isOnEnter then
        GameTooltip:Hide()
        frame.itemFrame:GetScript("OnEnter")(frame.itemFrame)
       end
       if frame.autoFrame:IsVisible() then
        frame.autoFrame:GetScript("OnShow")(frame.autoFrame)
       end
      end
     end
    end)
   end)
   frame.cantClickFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
   frame.cantClickFrame:SetAllPoints()
   frame.cantClickFrame:SetFrameLevel(200)
   frame.cantClickFrame:EnableMouse(true)
   After(.6, function()
    frame.cantClickFrame:Hide()
   end)
   frame.updateFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
   frame.updateFrame:SetBackdrop({
    bgFile = "Interface/ChatFrame/ChatFrameBackground",
   })
   frame.updateFrame:SetBackdropColor(1, 1, 1, .4)
   frame.updateFrame:SetAllPoints()
   frame.updateFrame:SetFrameLevel(150)
   frame.updateFrame.alpha = .5
   frame.updateFrame.totalTime = .4
   frame.updateFrame:Hide()
   frame.updateFrame:SetScript("OnShow", function(self)
    self.time = 0
    self:SetScript("OnUpdate", function(self, time)
     self.time = self.time + time
     local alpha = self.alpha - self.time / self.totalTime * self.alpha
     if alpha < 0 then alpha = 0 end
     self:SetAlpha(alpha)
     frame.autoFrame.updateFrame:SetAlpha(alpha)
     if self:GetAlpha() <= 0 then
      self:SetScript("OnUpdate", nil)
      self:Hide()
      frame.autoFrame.updateFrame:Hide()
     end
    end)
   end)
  end
  do
   local frame = CreateFrame("Frame", nil, auctionFrame, "BackdropTemplate")
   do
    frame:SetBackdrop({
     bgFile = "Interface/ChatFrame/ChatFrameBackground",
     edgeFile = "Interface/ChatFrame/ChatFrameBackground",
     edgeSize = wa.edgeSize,
    })
    frame:SetBackdropColor(unpack(wa.backdropColor))
    frame:SetBackdropBorderColor(unpack(wa.backdropBorderColor))
    frame:SetSize(120, 73)
    frame:EnableMouse(true)
    frame:Hide()
    frame.owner = auctionFrame
    auctionFrame.autoFrame = frame
    frame:SetScript("OnShow", function(self)
     frame:ClearAllPoints()
     if wa.IsRight(self) then
      frame:SetPoint("BOTTOMRIGHT", auctionFrame, "BOTTOMLEFT", 2, 0)
     else
      frame:SetPoint("BOTTOMLEFT", auctionFrame, "BOTTOMRIGHT", -2, 0)
     end
    end)
    frame:SetScript("OnMouseUp", function(self)
     auctionFrame:GetScript("OnMouseUp")(BGA.AuctionMainFrame)
    end)
    frame:SetScript("OnMouseDown", function(self)
     auctionFrame:GetScript("OnMouseDown")(BGA.AuctionMainFrame)
    end)
    auctionFrame.cantClickFrame.autoFrame = CreateFrame("Frame", nil, auctionFrame.cantClickFrame, "BackdropTemplate")
    auctionFrame.cantClickFrame.autoFrame:SetPoint("TOPLEFT", frame, 0, 0)
    auctionFrame.cantClickFrame.autoFrame:SetPoint("BOTTOMRIGHT", frame, 0, 0)
    auctionFrame.cantClickFrame.autoFrame:EnableMouse(true)
    After(.6, function()
     auctionFrame.cantClickFrame.autoFrame:Hide()
    end)
    frame.updateFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.updateFrame:SetBackdrop({
     bgFile = "Interface/ChatFrame/ChatFrameBackground",
    })
    frame.updateFrame:SetBackdropColor(1, 1, 1, .3)
    frame.updateFrame:SetAllPoints()
    frame.updateFrame:SetFrameLevel(150)
    frame.updateFrame:Hide()
   end
   local fontString = frame:CreateFontString()
   do
    fontString:SetFont(font, 15, "OUTLINE")
    fontString:SetPoint("TOP", 0, -8)
    fontString:SetTextColor(1, 0.82, 0)
    fontString:SetText(L["设置心理价格"])
    auctionFrame.autoTitleText = fontString
   end
   local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
   do
    wa.SetEditBg(editBox)
    editBox:SetSize(frame:GetWidth() - 30, 20)
    editBox:SetPoint("BOTTOM", 2, 27)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)
    editBox:SetMaxLetters(8)
    editBox.owner = auctionFrame
    editBox.alpha = .3
    auctionFrame.autoMoney = 0
    auctionFrame.autoMoneyEdit = editBox
    editBox:SetScript("OnTextChanged", wa.Auto_OnTextChanged)
    editBox:SetScript("OnEnterPressed", wa.AutoButton_OnClick)
    editBox:SetScript("OnEnter", wa.AutoEdit_OnEnter)
    editBox:SetScript("OnLeave", wa.OnLeave)
    editBox:SetScript("OnEditFocusGained", wa.OnEditFocusGained)
    local frame = CreateFrame("Frame", nil, editBox)
    frame:SetPoint("RIGHT", 12, 2)
    frame:SetSize(25, 25)
    frame:Hide()
    auctionFrame.isAutoTex = frame
    local texture = frame:CreateTexture()
    texture:SetAllPoints()
    texture:SetTexture("interface/raidframe/readycheck-ready")
    texture:SetAlpha(1)
   end
   local autoButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
   do
    autoButton:SetPoint("BOTTOM", 0, 5)
    autoButton:SetSize(frame:GetWidth() - 20, 22)
    autoButton:SetText(L["开启自动出价"])
    autoButton:Disable()
    autoButton.owner = auctionFrame
    auctionFrame.autoButton = autoButton
    autoButton:SetScript("OnClick", wa.AutoButton_OnClick)
    local autoMenuFrame = CreateFrame("Frame", nil, auctionFrame.autoButton)
    autoMenuFrame:SetAllPoints()
    autoMenuFrame:Hide()
    autoMenuFrame.dis = true
    autoMenuFrame.owner = auctionFrame
    autoMenuFrame:SetScript("OnEnter", wa.AutoButton_OnEnter)
    autoMenuFrame:SetScript("OnLeave", GameTooltip_Hide)
    auctionFrame.autoButton.disf = autoMenuFrame
   end
   auctionFrame.autoSendDelayFrame = CreateFrame("Frame", nil, auctionFrame)
  end
  do
   do
    local autoButton = CreateFrame("Button", nil, auctionFrame)
    autoButton:SetNormalFontObject(BGA.FontGreen15)
    autoButton:SetHighlightFontObject(BGA.FontWhite15)
    autoButton:SetDisabledFontObject(BGA.FontDis15)
    autoButton:SetPoint("TOPRIGHT", -wa.edgeSize - 1, -2)
    autoButton:SetText(L["折叠"])
    autoButton:SetSize(autoButton:GetFontString():GetWidth(), 18)
    autoButton:SetFrameLevel(autoButton:GetParent():GetFrameLevel() + 15)
    autoButton:RegisterForClicks("AnyUp")
    autoButton.owner = auctionFrame
    autoButton:SetScript("OnClick", wa.Hide_OnClick)
    autoButton:SetScript("OnEnter", wa.Hide_OnEnter)
    autoButton:SetScript("OnLeave", wa.OnLeave)
    auctionFrame.hide = autoButton
   end
   do
    local autoButton = CreateFrame("Button", nil, auctionFrame)
    autoButton:SetNormalFontObject(BGA.FontGreen15)
    autoButton:SetHighlightFontObject(BGA.FontWhite15)
    autoButton:SetDisabledFontObject(BGA.FontDis15)
    autoButton:SetPoint("TOPLEFT", wa.edgeSize + 1, -2)
    autoButton:SetText(L["记录"])
    autoButton:SetSize(autoButton:GetFontString():GetWidth(), 18)
    autoButton.owner = auctionFrame
    auctionFrame.logTextButton = autoButton
    autoButton:SetScript("OnEnter", wa.LogTextButton_OnEnter)
    autoButton:SetScript("OnLeave", wa.OnLeave)
   end
   do
    local autoButton = CreateFrame("Button", nil, auctionFrame)
    autoButton:SetNormalFontObject(BGA.FontGreen15)
    autoButton:SetHighlightFontObject(BGA.FontWhite15)
    autoButton:SetDisabledFontObject(BGA.FontDis15)
    autoButton.owner = auctionFrame
    auctionFrame.cancelButton = autoButton
    autoButton:SetScript("OnClick", wa.Cancel_OnClick)
   end
   if auctionFrame.isGen2 then
    local autoButton = CreateFrame("Button", nil, auctionFrame)
    autoButton:SetNormalFontObject(BGA.FontGreen15)
    autoButton:SetHighlightFontObject(BGA.FontWhite15)
    autoButton:SetDisabledFontObject(BGA.FontDis15)
    autoButton:SetPoint("TOP", auctionFrame, "TOPLEFT", wa.WIDTH / 10 * 5, -2)
    autoButton.owner = auctionFrame
    auctionFrame.puaseButton = autoButton
    autoButton:SetScript("OnClick", wa.Pause_OnClick)
   end
   do
    local autoButton = CreateFrame("Button", nil, auctionFrame)
    autoButton:SetNormalFontObject(BGA.FontGreen15)
    autoButton:SetHighlightFontObject(BGA.FontWhite15)
    autoButton:SetDisabledFontObject(BGA.FontDis15)
    autoButton.offset = wa.WIDTH / 10 * 6.4
    autoButton.owner = auctionFrame
    auctionFrame.autoTextButton = autoButton
    autoButton:SetScript("OnClick", wa.AutoText_OnClick)
   end
   wa.UpdateButtonState(auctionFrame)
  end
  do
   local frame = CreateFrame("Frame", nil, auctionFrame, "BackdropTemplate")
   frame:SetPoint("TOPLEFT", frame:GetParent(), "TOPLEFT", wa.edgeSize + 1, -auctionFrame.hide:GetHeight() - 3)
   frame:SetPoint("BOTTOMRIGHT", frame:GetParent(), "TOPRIGHT", -wa.edgeSize, -55)
   frame:SetFrameLevel(frame:GetParent():GetFrameLevel() + 10)
   frame.owner = auctionFrame
   frame.itemID = itemID
   frame.link = link
   frame:SetScript("OnEnter", wa.itemOnEnter)
   frame:SetScript("OnLeave", wa.itemOnLeave)
   frame:SetScript("OnMouseUp", function(self)
    auctionFrame:GetScript("OnMouseUp")(BGA.AuctionMainFrame)
   end)
   frame:SetScript("OnMouseDown", function(self)
    if IsShiftKeyDown() then
     if not GetCurrentKeyBoardFocus() then
      ChatEdit_ActivateChat(ChatEdit_ChooseBoxForSend())
     end
     ChatEdit_InsertLink(link)
    elseif IsControlKeyDown() then
     DressUpItemLink(link)
    else
     auctionFrame:GetScript("OnMouseDown")(BGA.AuctionMainFrame)
    end
   end)
   auctionFrame.itemFrame = frame
   local itemFrame2 = CreateFrame("Frame", nil, frame)
   auctionFrame.itemFrame2 = itemFrame2
   local texture = frame:CreateTexture(nil, "BACKGROUND")
   texture:SetAllPoints()
   texture:SetColorTexture(0, 0, 0, 0.5)
   auctionFrame.itemFrame.bg = texture
   local qualityR, qualityG, qualityB = GetItemQualityColor(rarity)
   local itemFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
   itemFrame:SetBackdrop({
    edgeFile = "Interface/ChatFrame/ChatFrameBackground",
    edgeSize = 2,
   })
   itemFrame:SetBackdropBorderColor(qualityR, qualityG, qualityB, 1)
   itemFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
   itemFrame:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", frame:GetHeight(), -frame:GetHeight())
   itemFrame.tex = itemFrame:CreateTexture(nil, "BACKGROUND")
   itemFrame.tex:SetAllPoints()
   itemFrame.tex:SetTexture(icon)
   itemFrame.tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
   itemFrame.color = { qualityR, qualityG, qualityB }
   auctionFrame.itemFrame.iconFrame = itemFrame
   local fontString = itemFrame2:CreateFontString()
   fontString:SetFont(font, 12, "OUTLINE")
   fontString:SetPoint("BOTTOM", itemFrame, "BOTTOM", 0, 1)
   fontString:SetText(itemLevel)
   fontString:SetTextColor(qualityR, qualityG, qualityB)
   auctionFrame.itemFrame.levelText = fontString
   if subclassID == 2 then
    local fontString = itemFrame2:CreateFontString()
    fontString:SetFont(font, 11, "OUTLINE")
    fontString:SetPoint("TOP", itemFrame, 0, -2)
    fontString:SetText(L["装绑"])
    fontString:SetTextColor(0, 1, 0)
    auctionFrame.itemFrame.bindTypeText = fontString
   end
   local fontString = frame:CreateFontString()
   fontString:SetFont(font, 15, "OUTLINE")
   fontString:SetPoint("TOPLEFT", itemFrame, "TOPRIGHT", 2, -2)
   fontString:SetWidth(frame:GetWidth() - frame:GetHeight() - 50)
   fontString:SetText(link:gsub("%[", ""):gsub("%]", ""))
   fontString:SetJustifyH("LEFT")
   fontString:SetWordWrap(false)
   auctionFrame.itemFrame.itemNameText = fontString
   if BG and BG.GetItemCount and BG.GetItemCount(itemID) ~= 0 or GetItemCount(itemID, true) ~= 0 then
    local texture = itemFrame2:CreateTexture(nil, "ARTWORK")
    texture:SetSize(15, 15)
    texture:SetPoint("LEFT", fontString, "LEFT", fontString:GetWrappedWidth(), 0)
    texture:SetTexture("interface/raidframe/readycheck-ready")
    local texture = itemFrame:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexture("interface/raidframe/readycheck-ready")
    auctionFrame.itemFrame.havedTex = texture
   end
   local fontString = itemFrame2:CreateFontString()
   fontString:SetFont(font, 12, "OUTLINE")
   fontString:SetPoint("BOTTOMLEFT", itemFrame, "BOTTOMRIGHT", 2, 2)
   fontString:SetHeight(13)
   fontString:SetWidth(auctionFrame.itemFrame.itemNameText:GetWidth())
   local tooltipClassText = BG and BG.GetTooltipClassText and BG.GetTooltipClassText(itemID) or ""
   if _G[equipLoc] then
    if sellPrice == 2 then
     fontString:SetText(itemSubType .. "  " .. tooltipClassText)
    else
     fontString:SetText(_G[equipLoc] .. " " .. itemSubType .. "  " .. tooltipClassText)
    end
   else
    fontString:SetText(tooltipClassText)
   end
   fontString:SetJustifyH("LEFT")
   auctionFrame.itemFrame.itemTypeText = fontString
   local statusBar = CreateFrame("StatusBar", nil, frame)
   statusBar:SetPoint("TOPLEFT", itemFrame, "TOPRIGHT", 0, 0)
   statusBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
   statusBar:SetFrameLevel(statusBar:GetParent():GetFrameLevel())
   statusBar:SetStatusBarTexture("Interface/ChatFrame/ChatFrameBackground")
   statusBar:SetStatusBarColor(1, 1, 0, 0.6)
   statusBar:SetMinMaxValues(0, 1000)
   statusBar.owner = auctionFrame
   auctionFrame.bar = statusBar
   local fontString2 = itemFrame2:CreateFontString()
   fontString2:SetFont(font, 15, "OUTLINE")
   fontString2:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
   fontString2:SetTextColor(1, 1, 1)
   auctionFrame.remainingTime = fontString2
  end
  do
   local width = 190
   local offset = 25
   local height = 22
   local frame = CreateFrame("Frame", nil, auctionFrame)
   frame:SetSize(width, 20)
   frame:SetPoint("TOPLEFT", auctionFrame.itemFrame, "BOTTOMLEFT", 3, -3)
   frame:SetFrameLevel(frame:GetParent():GetFrameLevel() + 11)
   frame:SetScript("OnMouseDown", wa.currentMoney_OnMouseDown)
   frame:SetScript("OnMouseUp", wa.currentMoney_OnMouseUp)
   frame.owner = auctionFrame
   local fontString = frame:CreateFontString()
   fontString:SetFont(font, 14, "OUTLINE")
   fontString:SetAllPoints()
   fontString:SetJustifyH("LEFT")
   if player and player ~= "" then
    fontString:SetText(L["|cffFFD100当前价格：|r"] .. wa.FormatNumber(money))
    auctionFrame.start = false
   else
    fontString:SetText(L["|cffFFD100起拍价：|r"] .. wa.FormatNumber(money))
    auctionFrame.start = true
   end
   local prevFrame = frame
   auctionFrame.currentMoneyFrame = frame
   auctionFrame.currentMoneyText = fontString
   auctionFrame.money = money
   local frame = CreateFrame("Frame", nil, prevFrame)
   frame:SetSize(width, height)
   frame:SetPoint("TOPLEFT", prevFrame, "BOTTOMLEFT", 0, 0)
   local fontString = frame:CreateFontString()
   fontString:SetFont(font, 14, "OUTLINE")
   fontString:SetAllPoints()
   fontString:SetJustifyH("LEFT")
   if player then
    auctionFrame.player = player
    auctionFrame.colorplayer = wa.SetClassCFF(player)
   end
   if player and player ~= "" then
    if player == wa.GN() then
     fontString:SetText(L["|cffFFD100出价最高者：|r"] .. "|cff" .. wa.GREEN1 .. L[">> 你 <<"])
     auctionFrame:SetBackdropColor(unpack(wa.backdropColor_IsMe))
     auctionFrame:SetBackdropBorderColor(unpack(wa.backdropBorderColor_IsMe))
     auctionFrame.autoFrame:SetBackdropColor(unpack(wa.backdropColor_IsMe))
     auctionFrame.autoFrame:SetBackdropBorderColor(unpack(wa.backdropBorderColor_IsMe))
    else
     fontString:SetText(L["|cffFFD100出价最高者：|r"] .. auctionFrame.colorplayer)
     auctionFrame:SetBackdropColor(unpack(wa.backdropColor))
     auctionFrame:SetBackdropBorderColor(unpack(wa.backdropBorderColor))
     auctionFrame.autoFrame:SetBackdropColor(unpack(wa.backdropColor))
     auctionFrame.autoFrame:SetBackdropBorderColor(unpack(wa.backdropBorderColor))
    end
   end
   auctionFrame.topMoneyFrame = frame
   auctionFrame.topMoneyText = fontString
   local editBox = CreateFrame("EditBox", nil, prevFrame, "InputBoxTemplate")
   wa.SetEditBg(editBox)
   editBox:SetSize(auctionFrame:GetRight() - prevFrame:GetRight() - 3, 20)
   editBox:SetPoint("TOPLEFT", prevFrame, "TOPRIGHT", 0, 0)
   editBox:SetAutoFocus(false)
   editBox:SetNumeric(true)
   editBox:SetText(money)
   editBox:SetMaxLetters(8)
   editBox.owner = auctionFrame
   editBox:SetScript("OnTextChanged", wa.myMoney_OnTextChanged)
   editBox:SetScript("OnEnterPressed", wa.SendMyMoney_OnClick)
   editBox:SetScript("OnMouseWheel", wa.myMoney_OnMouseWheel)
   editBox:SetScript("OnEnter", wa.myMoney_OnEnter)
   editBox:SetScript("OnLeave", wa.OnLeave)
   editBox:SetScript("OnEditFocusGained", wa.OnEditFocusGained)
   auctionFrame.myMoneyEdit = editBox
   local autoButton = CreateFrame("Button", nil, editBox, "UIPanelButtonTemplate")
   autoButton:SetSize(offset, 22)
   autoButton:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -5, 0)
   autoButton:SetNormalFontObject(BGA.FontGold18)
   autoButton:SetDisabledFontObject(BGA.FontDis18)
   autoButton.owner = auctionFrame
   autoButton.edit = editBox
   autoButton._type = "-"
   autoButton:SetText(autoButton._type)
   autoButton:SetScript("OnMouseDown", wa.JiaJian_OnMouseDown)
   autoButton:SetScript("OnMouseUp", wa.JiaJian_OnMouseUp)
   autoButton:SetScript("OnClick", wa.JiaJian_OnClick)
   autoButton:SetScript("OnEnter", wa.JiaJian_OnEnter)
   autoButton:SetScript("OnLeave", wa.OnLeave)
   auctionFrame.ButtonJian = autoButton
   local autoButton = CreateFrame("Button", nil, editBox, "UIPanelButtonTemplate")
   autoButton:SetSize(offset, 22)
   autoButton:SetPoint("LEFT", auctionFrame.ButtonJian, "RIGHT", 0, 0)
   autoButton:SetNormalFontObject(BGA.FontGold18)
   autoButton:SetDisabledFontObject(BGA.FontDis18)
   autoButton.owner = auctionFrame
   autoButton.edit = editBox
   autoButton._type = "+"
   autoButton:SetText(autoButton._type)
   autoButton:SetScript("OnMouseDown", wa.JiaJian_OnMouseDown)
   autoButton:SetScript("OnMouseUp", wa.JiaJian_OnMouseUp)
   autoButton:SetScript("OnClick", wa.JiaJian_OnClick)
   autoButton:SetScript("OnEnter", wa.JiaJian_OnEnter)
   autoButton:SetScript("OnLeave", wa.OnLeave)
   auctionFrame.ButtonJia = autoButton
   local autoButton = CreateFrame("Button", nil, editBox, "UIPanelButtonTemplate")
   autoButton:SetPoint("TOPLEFT", auctionFrame.ButtonJia, "TOPRIGHT", 0, 0)
   autoButton:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 0, -height)
   autoButton:SetText(L["出价"])
   autoButton.owner = auctionFrame
   autoButton.edit = editBox
   autoButton.itemID = itemID
   auctionFrame.ButtonSendMyMoney = autoButton
   autoButton:SetScript("OnClick", wa.SendMyMoney_OnClick)
   autoButton:SetScript("OnEnter", wa.SendMyMoney_OnEnter)
   autoButton:SetScript("OnLeave", wa.OnLeave)
   local frame = CreateFrame("Frame", nil, autoButton)
   frame:SetAllPoints()
   frame:Hide()
   frame.dis = true
   frame.owner = auctionFrame
   frame:SetScript("OnEnter", wa.SendMyMoneyDis_OnEnter)
   frame:SetScript("OnLeave", GameTooltip_Hide)
   auctionFrame.disf = frame
   autoButton.disf = frame
   wa.myMoney_OnTextChanged(auctionFrame.myMoneyEdit)
  end
  wa.anim(auctionFrame)
  wa.Auctioning(auctionFrame, duration)
  if BG and BG.HookCreateAuction then
   BG.HookCreateAuction(auctionFrame)
  end
 end
 do
  local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  frame:SetSize(wa.WIDTH, wa.HEIGHT)
  if BiaoGe and BiaoGe.options and BiaoGe.options.autoAuctionFrameLevel then
   frame:SetFrameStrata(BiaoGe.options.autoAuctionFrameLevel)
  else
   frame:SetFrameStrata("HIGH")
  end
  frame:SetClampedToScreen(true)
  frame:SetFrameLevel(100)
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:SetScale(BiaoGe and BiaoGe.options and BiaoGe.options["autoAuctionScale"] or 0.9)
  BGA.AuctionMainFrame = frame
  if BiaoGe and BiaoGe.point and BiaoGe.point.Auction then
   BiaoGe.point.Auction[2] = nil
   frame:SetPoint(unpack(BiaoGe.point.Auction))
  else
   frame:SetPoint("TOPRIGHT", -100, -200)
  end
 end
 local function getModLabel(link)
  local modLabel = ""
  return modLabel
 end
 local function eventHandler(self, event, ...)
  if event == "CHAT_MSG_ADDON" then
   local prefix, message, distribution, v, line = ...
   local opcode, auctionIDStr, itemIDStr, moneyStr, durationStr, playerStr, modStr, linkStr, resetStr, extra
   local isGen2
   if prefix == wa.AddonChannel then
    opcode, auctionIDStr, itemIDStr, moneyStr, durationStr, playerStr, modStr, linkStr = strsplit(",", message, 8)
   elseif prefix:match(wa.AddonChannel2) then
    opcode, auctionIDStr, itemIDStr, moneyStr, durationStr, playerStr, modStr, linkStr, resetStr, extra = strsplit("^", message)
    isGen2 = true
   end
   if not opcode then return end
   if opcode == "StartAuction" and distribution == "RAID" then
    local auctionID = tonumber(auctionIDStr)
    local itemID = tonumber(itemIDStr)
    local money = tonumber(moneyStr)
    local duration = tonumber(durationStr)
    local player = playerStr
    local mod = modStr
    -- 匿名拍卖已移除（决策逆转 docs/07 §3.3）：匿名 StartAuction 不创建帧，静默忽略。常规拍卖（mod=normal）不受影响。
    if mod == "anonymous" then return end
    local link = linkStr ~= "" and linkStr or nil
    local resetThreshold = isGen2 and tonumber(resetStr) or wa.REPEAT_TIME
    BG.OnItemLoad(link or itemID):ContinueOnItemLoad(function()
     wa.CreateAuction(auctionID, itemID, money, duration, player, mod, link, resetThreshold, isGen2)
     if wa.IsRaidLeader() then
      local v, link = GetItemInfo(link or itemID)
      local message = format(L["{rt1}拍卖开始{rt1} %s 起拍价：%s"], link, money)
      local modLabel = securecall(getModLabel, link)
      if modLabel then
       if strlen(message .. modLabel) < 255 then
        message = message .. modLabel
       end
      end
      SendChatMessage(message, "RAID_WARNING")
     end
    end)
   elseif opcode == "CancelAuction" and distribution == "RAID" then
    local auctionID = tonumber(auctionIDStr)
    for v, frame in pairs(BGA.Frames) do
     if frame[auctionIdKey] == auctionID and not frame.IsEnd then
      wa.SetEndState(frame, L["拍卖取消"], 1, 0, 0)
      if frame.IsSmallWindow then
       frame.currentMoneyText:SetText("|cffFF0000" .. L["拍卖取消"])
      end
      if wa.IsRaidLeader() then
       SendChatMessage(format(L["{rt7}拍卖取消{rt7} %s"], frame.link), "RAID")
      end
      if BG and BG.AuctionWAEnd then
       BG.AuctionWAEnd(3, frame.link, frame.player, frame.money)
      end
      After(wa.HIDEFRAME_TIME, function()
       wa.UpdateFrame(frame)
      end)
      return
     end
    end
   elseif opcode == "PauseAuction" and distribution == "RAID" then
    local itemID = tonumber(auctionIDStr)
    for v, frame in pairs(BGA.Frames) do
     if frame.itemID == itemID and frame.isGen2 and not frame.IsEnd then
      wa.PauseAuction(frame)
     end
    end
   elseif opcode == "ResumeAuction" and distribution == "RAID" then
    local itemID = tonumber(auctionIDStr)
    for v, frame in pairs(BGA.Frames) do
     if frame.itemID == itemID and frame.isGen2 and not frame.IsEnd then
      wa.ResumeAuction(frame)
     end
    end
   elseif opcode == "SendMyMoney" and distribution == "RAID" then
    local auctionID = tonumber(auctionIDStr)
    local money = tonumber(itemIDStr)
    for v, frame in pairs(BGA.Frames) do
     if not frame.IsEnd and not frame.isPaused and frame.mod ~= "anonymous" and frame[auctionIdKey] == auctionID then
      if frame.start and money >= frame.money or money > frame.money then
       wa.SetMoney(frame, money, line)
      end
      return
     end
    end
   elseif opcode == "VersionCheck" and distribution == "RAID" then
    C_ChatInfo.SendAddonMessage(wa.AddonChannel, "MyVer" .. "," .. wa.ver, "RAID")
   -- 匿名族三消息（AnonymousWhisperMyMoney / AnonymousSendMyMoney / AnonymousWinner）已移除。
   -- 收到外部原版发来的匿名 opcode 自然落入链尾静默丢弃（识别但忽略），不回包、不中继、不落盘。
   end
  elseif event == "GROUP_ROSTER_UPDATE" then
   local canSend = wa.canSend()
   After(0.5, function()
    wa.UpdateRaidRosterInfo(canSend)
   end)
  elseif event == "PLAYER_ENTERING_WORLD" then
   self:UnregisterEvent("PLAYER_ENTERING_WORLD")
   After(2, function()
    wa.UpdateRaidRosterInfo()
   end)
  elseif event == "MODIFIER_STATE_CHANGED" then
   local mod, type = ...
   if (mod == "LCTRL" or mod == "RCTRL") then
    if type == 1 then
     if wa.itemIsOnEnter then
      SetCursor("Interface/Cursor/Inspect")
     end
    else
     SetCursor(nil)
    end
   end
  elseif event == "CHAT_MSG_RAID_LEADER" then
   local message = ...
   if wa.IsSecret(message) then return end
   local item, buyer, price
   item, buyer, price = message:match("{rt6}拍卖成功{rt6} (.-) (.-) (.+)")
   if not (item and buyer and price) then
    item, buyer, price = message:match("{rt6}拍賣成功{rt6} (.-) (.-) (.+)")
   end
   if not (item and buyer and price) then
    item, buyer, price = message:match("{rt6}Auction Successful{rt6} (.-) (.-) (.+)")
   end
   if (item and buyer and price) then
    return
   end
   item = message:match("{rt7}流拍{rt7} (.+)")
   if not item then
    item = message:match("^{rt7}Auction Failed{rt7} (.+)$")
   end
   if item then
    return
   end
  end
 end
 BGA.Event = CreateFrame("Frame")
 BGA.Event:RegisterEvent("CHAT_MSG_ADDON")
 BGA.Event:RegisterEvent("GROUP_ROSTER_UPDATE")
 BGA.Event:RegisterEvent("PLAYER_ENTERING_WORLD")
 BGA.Event:RegisterEvent("MODIFIER_STATE_CHANGED")
 BGA.Event:RegisterEvent("CHAT_MSG_RAID_LEADER")
 BGA.Event:SetScript("OnEvent", eventHandler)
end)