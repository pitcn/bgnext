local _, ns = ...
local L = ns and ns.L or setmetatable({}, {__index=function(_,key) return key end})
BG = BG or {}
BG.BGNext = BG.BGNext or {}
local M = {}

local groups = {
    {'ALL','全部部位'}, {'HEAD','头部'}, {'NECK','颈部'}, {'SHOULDER','肩部'},
    {'CHEST','胸部'}, {'WAIST','腰部'}, {'LEGS','腿部'}, {'FEET','脚部'},
    {'WRIST','腕部'}, {'HANDS','手部'}, {'FINGER','手指'}, {'TRINKET','饰品'},
    {'CLOAK','背部'}, {'WEAPON','武器'}, {'OFFHAND','副手'}, {'RANGED','远程'},
    {'OTHER','兑换物/其他'}, {'UNKNOWN','待分类'},
}
local locations = {
    INVTYPE_HEAD='HEAD', INVTYPE_NECK='NECK', INVTYPE_SHOULDER='SHOULDER',
    INVTYPE_CHEST='CHEST', INVTYPE_ROBE='CHEST', INVTYPE_WAIST='WAIST',
    INVTYPE_LEGS='LEGS', INVTYPE_FEET='FEET', INVTYPE_WRIST='WRIST', INVTYPE_HAND='HANDS',
    INVTYPE_FINGER='FINGER', INVTYPE_TRINKET='TRINKET', INVTYPE_CLOAK='CLOAK',
    INVTYPE_WEAPON='WEAPON', INVTYPE_2HWEAPON='WEAPON', INVTYPE_WEAPONMAINHAND='WEAPON',
    INVTYPE_WEAPONOFFHAND='OFFHAND', INVTYPE_SHIELD='OFFHAND', INVTYPE_HOLDABLE='OFFHAND',
    INVTYPE_RANGED='RANGED', INVTYPE_RANGEDRIGHT='RANGED', INVTYPE_THROWN='RANGED', INVTYPE_RELIC='RANGED',
}
function M.groupFor(location)
    if type(location) ~= 'string' then return 'UNKNOWN' end
    return locations[location] or 'OTHER'
end

-- Only bossN direct-drop arrays participate. Exchange rewards, encounter
-- metadata and shared miscellaneous arrays are never promoted to boss drops.
function M.collect(difficulties, loot, bossLimit, readInfo)
    local rows, byId, pending = {}, {}, {}
    bossLimit = tonumber(bossLimit) or 0
    if bossLimit < 0 or bossLimit > 100 or bossLimit % 1 ~= 0 then return rows,pending end
    for difficultyIndex, difficulty in ipairs(difficulties or {}) do
        local data = type(loot) == 'table' and loot[difficulty]
        for boss = 1,bossLimit do
            local drops = type(data) == 'table' and data['boss'..boss]
            if type(drops) == 'table' then
                local sourceSeen = {}
                for _, id in ipairs(drops) do
                    if type(id) == 'number' and id > 0 and id < 2147483648 and id % 1 == 0 and not sourceSeen[id] then
                        sourceSeen[id] = true
                        local row = byId[id]
                        if not row then
                            local ok, info = pcall(readInfo,id)
                            info = ok and type(info) == 'table' and info or {}
                            local known = type(info.name) == 'string' and info.name ~= ''
                            row = {itemId=id, name=known and info.name or ('item:'..id), link=info.link,
                                group=M.groupFor(info.equipLoc), sources={}}
                            if not known then pending[id] = true end
                            rows[#rows+1] = row; byId[id] = row
                        end
                        row.sources[#row.sources+1] = {difficultyIndex=difficultyIndex,difficulty=difficulty,bossIndex=boss}
                    end
                end
            end
        end
    end
    table.sort(rows,function(a,b)
        if a.name ~= b.name then return a.name < b.name end
        return a.itemId < b.itemId
    end)
    return rows,pending
end

function M.filter(rows,group)
    local result = {}
    for _, row in ipairs(rows or {}) do
        if group == 'ALL' or row.group == group then result[#result+1] = row end
    end
    return result
end

function M.newController(env)
    local self = {group='ALL',page=1,pageSize=15,rows={},pending={},generation=0}
    local timer
    local function cancel()
        self.generation = self.generation + 1
        if timer then timer:Cancel();timer=nil end
    end
    function self:hide()
        cancel();self.pending={};self.rows={};self.raidId=nil
    end
    function self:refresh()
        if not env.visible() then self:hide();return end
        cancel()
        local context = env.context()
        if self.raidId ~= context.raidId then self.page=1 end
        self.raidId = context.raidId
        local rows
        rows,self.pending=M.collect(context.difficulties,context.loot,context.bossLimit,env.readInfo)
        self.rows=M.filter(rows,self.group)
        local pages=math.max(1,math.ceil(#self.rows/self.pageSize))
        self.page=math.max(1,math.min(pages,self.page))
        local shown={}
        for index=(self.page-1)*self.pageSize+1,math.min(#self.rows,self.page*self.pageSize) do
            local row=self.rows[index];row.raidId=self.raidId;shown[#shown+1]=row
        end
        env.render(shown,#self.rows,self.page,pages,self.group)
    end
    function self:setGroup(group)
        for _,entry in ipairs(groups) do
            if entry[1]==group then self.group=group;self.page=1;self:refresh();return true end
        end
        return false
    end
    function self:turnPage(delta)
        self.page=self.page+delta;self:refresh()
    end
    function self:onItemInfo(id,success)
        if not env.visible() or not self.pending[id] then return end
        if success==false then self.pending[id]=nil;return end
        if env.context().raidId~=self.raidId then return end
        if timer then return end
        local generation=self.generation
        local callback=function()
            if generation~=self.generation then return end
            timer=nil;self:refresh()
        end
        if env.schedule then timer=env.schedule(callback) else callback() end
    end
    function self:act(row,button)
        if not env.visible() or type(row)~='table' or row.raidId~=self.raidId
            or env.context().raidId~=self.raidId then return false end
        local found=false
        for _,current in ipairs(self.rows) do if current==row then found=true;break end end
        if not found then return false end
        if button=='LeftButton' and env.contains and env.contains(row.itemId,self.raidId) then return false end
        local action=button=='RightButton' and env.remove or (button=='LeftButton' and env.add)
        if not action then return false end
        self.acting=true
        local okay,result=pcall(action,row.itemId,self.raidId)
        self.acting=false
        self:refresh()
        return okay and result==true
    end
    return self
end

local function itemInfo(id)
    local api=type(C_Item)=='table' and C_Item or {}
    local read=api.GetItemInfo or GetItemInfo
    local result=type(read)=='function' and {pcall(read,id)} or {}
    local location=result[1] and result[10] or nil
    if type(location)~='string' then
        local instant=api.GetItemInfoInstant or GetItemInfoInstant
        local quick=type(instant)=='function' and {pcall(instant,id)} or {}
        location=quick[1] and quick[5] or nil
    end
    return {name=result[1] and result[2] or nil,link=result[1] and result[3] or nil,equipLoc=location}
end

function M.attach(parent,options)
    local main=options.main
    local panel=CreateFrame('Frame',nil,parent)
    panel:SetAllPoints(parent);panel:Hide()
    local view={frame=panel,mode='boss'}
    local function text(parentFrame,size)
        local font=parentFrame:CreateFontString(nil,'OVERLAY')
        font:SetFont(BIAOGE_TEXT_FONT,size,'OUTLINE');font:SetJustifyH('LEFT');font:SetWordWrap(false)
        return font
    end
    local function button(parentFrame,label,width)
        local bt=BG.CreateButton(parentFrame)
        bt:SetText(label)
        local font=bt:GetFontString()
        bt:SetSize(math.max(width,font and font:GetStringWidth()+18 or width),24)
        return bt
    end
    local byBoss=button(parent,L['按Boss'],100)
    byBoss:SetPoint('LEFT',options.clearButton,'RIGHT',15,0)
    local bySlot=button(parent,L['按部位'],100)
    bySlot:SetPoint('LEFT',byBoss,'RIGHT',8,0)
    local groupButton=button(panel,L['全部部位'],170)
    groupButton:SetPoint('TOPLEFT',main,'TOPLEFT',25,-65)
    local hint=text(panel,12)
    hint:SetPoint('LEFT',groupButton,'RIGHT',12,0)
    hint:SetWidth(math.max(100,main:GetWidth()-240))
    hint:SetWordWrap(true)
    hint:SetText(L['左键加入心愿，右键取消；未缓存装备保留在待分类。'])
    local menu=CreateFrame('Frame',nil,panel,'BackdropTemplate')
    menu:SetPoint('TOPLEFT',groupButton,'BOTTOMLEFT',0,-3)
    menu:SetSize(180,#groups*23+10)
    menu:SetFrameLevel(panel:GetFrameLevel()+30)
    menu:SetBackdrop({bgFile='Interface/ChatFrame/ChatFrameBackground'})
    menu:SetBackdropColor(0.05,0.05,0.05,1);menu:Hide()
    local rows={}
    local previous=button(panel,L['上一页'],100)
    previous:SetPoint('BOTTOMLEFT',main,'BOTTOMLEFT',25,75)
    local pageText=text(panel,13)
    pageText:SetPoint('LEFT',previous,'RIGHT',15,0)
    local nextPage=button(panel,L['下一页'],100)
    nextPage:SetPoint('LEFT',pageText,'RIGHT',15,0)
    local empty=text(panel,14)
    empty:SetPoint('TOPLEFT',main,'TOPLEFT',30,-112)
    empty:SetText(L['该部位没有可添加的直接掉落。'])
    local controller
    local function active()
        return view.mode=='slots' and panel:IsVisible() and options.enabled()
    end
    local function pageSize()
        return math.max(1,math.min(20,math.floor((main:GetHeight()-200)/34)))
    end
    local requested,requestRaid={},nil
    controller=M.newController({
        visible=active, context=options.context, readInfo=options.readInfo or itemInfo,
        schedule=type(C_Timer)=='table' and type(C_Timer.NewTimer)=='function' and function(callback)
            return C_Timer.NewTimer(0.05,callback)
        end or nil,
        add=options.add,remove=options.remove,contains=options.contains,
        render=function(shown,total,page,pages,group)
            local context=options.context()
            if requestRaid~=context.raidId then requested={};requestRaid=context.raidId end
            for _,entry in ipairs(groups) do if entry[1]==group then groupButton:SetText(L[entry[2]]) end end
            pageText:SetText(string.format(L['第%d/%d页，共%d件'],page,pages,total))
            pageText:SetWidth(pageText:GetStringWidth()+8)
            previous:SetEnabled(page>1);nextPage:SetEnabled(page<pages)
            empty:SetShown(total==0)
            for index=1,20 do
                local bt=rows[index]
                if not bt then
                    bt=CreateFrame('Button',nil,panel)
                    bt:SetPoint('TOPLEFT',main,'TOPLEFT',30,-105-(index-1)*34)
                    bt:SetSize(math.max(200,main:GetWidth()-75),32)
                    bt:RegisterForClicks('LeftButtonUp','RightButtonUp')
                    bt:SetHighlightTexture('Interface/QuestFrame/UI-QuestTitleHighlight')
                    bt.label=text(bt,14);bt.label:SetPoint('TOPLEFT',bt,'TOPLEFT',0,-1)
                    bt.source=text(bt,11);bt.source:SetPoint('TOPLEFT',bt.label,'BOTTOMLEFT',0,-2)
                    bt:SetScript('OnMouseDown',function(self) self.pressed=self.entry end)
                    bt:SetScript('OnClick',function(self,mouseButton)
                        local pressed=self.pressed;self.pressed=nil
                        if pressed and pressed~=self.entry then return end
                        controller:act(self.entry,mouseButton)
                    end)
                    bt:SetScript('OnEnter',function(self)
                        if not active() or not self.entry or not GameTooltip then return end
                        GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
                        local ok=pcall(GameTooltip.SetHyperlink,GameTooltip,self.entry.link or ('item:'..self.entry.itemId))
                        if ok then GameTooltip:Show() else GameTooltip:Hide() end
                    end)
                    bt:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
                    rows[index]=bt
                end
                local entry=shown[index]
                bt:SetWidth(math.max(200,main:GetWidth()-75))
                bt.entry=entry;bt:SetShown(entry~=nil)
                if entry then
                    local selected=options.contains(entry.itemId,context.raidId)
                    bt.label:SetText((selected and '|cff00ff00'..L['已选']..'|r  ' or '')..(entry.link or entry.name))
                    bt.label:SetWidth(math.max(180,main:GetWidth()-90))
                    local sources={}
                    for _,source in ipairs(entry.sources) do
                        sources[#sources+1]=options.sourceLabel(context.raidId,source)
                    end
                    bt.source:SetText(table.concat(sources,' / '));bt.source:SetWidth(bt.label:GetWidth())
                    if controller.pending[entry.itemId] and not requested[entry.itemId] then
                        requested[entry.itemId]=true
                        if C_Item and type(C_Item.RequestLoadItemDataByID)=='function' then
                            pcall(C_Item.RequestLoadItemDataByID,entry.itemId)
                        end
                    end
                end
            end
        end,
    })
    view.controller=controller
    function view:refresh()
        controller.pageSize=pageSize();controller:refresh()
    end
    function view:setMode(mode)
        if mode~='boss' and mode~='slots' then return end
        options.closePicker();menu:Hide();self.mode=mode
        byBoss:SetEnabled(mode~='boss');bySlot:SetEnabled(mode~='slots')
        options.changed()
    end
    byBoss:SetScript('OnClick',function() view:setMode('boss') end)
    bySlot:SetScript('OnClick',function() view:setMode('slots') end)
    byBoss:Disable()
    for index,entry in ipairs(groups) do
        local group,key=entry[1],entry[2]
        local bt=button(menu,L[key],170)
        bt:SetPoint('TOPLEFT',menu,'TOPLEFT',5,-5-(index-1)*23)
        bt:SetScript('OnClick',function() menu:Hide();controller:setGroup(group) end)
    end
    groupButton:SetScript('OnClick',function() menu:SetShown(not menu:IsShown()) end)
    previous:SetScript('OnClick',function() controller:turnPage(-1) end)
    nextPage:SetScript('OnClick',function() controller:turnPage(1) end)
    panel:EnableMouseWheel(true)
    panel:SetScript('OnMouseWheel',function(_,delta) controller:turnPage(delta>0 and -1 or 1) end)
    panel:SetScript('OnShow',function()
        panel:RegisterEvent('GET_ITEM_INFO_RECEIVED')
        pcall(panel.RegisterEvent,panel,'ITEM_DATA_LOAD_RESULT')
        view:refresh()
    end)
    panel:SetScript('OnEvent',function(_,_,id,success) controller:onItemInfo(id,success) end)
    panel:SetScript('OnHide',function()
        panel:UnregisterAllEvents();menu:Hide();controller:hide();requested={};requestRaid=nil
        if GameTooltip then GameTooltip:Hide() end
    end)
    panel:SetScript('OnSizeChanged',function() if active() then view:refresh() end end)
    return view
end

BG.BGNext.WishlistBrowse = M
return M
