return function(T)
    local keys={'BG','CreateFrame','C_Timer','C_Item','GetItemInfo','GetItemInfoInstant','GameTooltip'}
    local old={};for _,key in ipairs(keys) do old[key]=_G[key] end
    local okay,reason=pcall(function()
        local frames,tasks={},{}
        local function widget(parent)
            local f={parent=parent,shown=true,width=1000,height=810,scripts={},children={}}
            if parent then parent.children[#parent.children+1]=f end
            frames[#frames+1]=f
            function f:IsShown() return self.shown end
            function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
            local function notify(self,event)
                if self.scripts[event] then self.scripts[event](self) end
                for _,child in ipairs(self.children) do if child.shown then notify(child,event) end end
            end
            function f:SetShown(value)
                value=value and true or false
                if self.shown~=value then self.shown=value;notify(self,value and 'OnShow' or 'OnHide') end
            end
            function f:Show() self:SetShown(true) end
            function f:Hide() self:SetShown(false) end
            function f:SetScript(event,callback) self.scripts[event]=callback end
            function f:SetAllPoints(other) self.width=other:GetWidth();self.height=other:GetHeight() end
            function f:SetPoint(...) self.point={...} end
            function f:SetSize(w,h) self.width=w;self.height=h end
            function f:SetWidth(w) self.width=w end
            function f:GetWidth() return self.width end
            function f:GetHeight() return self.height end
            function f:SetText(value) self.text=value end
            function f:GetStringWidth() return #(self.text or '')*6 end
            function f:GetFontString() return self end
            function f:GetFrameLevel() return 1 end
            function f:SetEnabled(value) self.enabled=value end
            function f:Disable() self:SetEnabled(false) end
            function f:RegisterEvent(event) self.events=self.events or {};self.events[event]=true end
            function f:UnregisterAllEvents() self.events={} end
            function f:CreateFontString() return widget(self) end
            for _,method in ipairs({'SetFont','SetJustifyH','SetWordWrap','SetFrameLevel','SetBackdrop','SetBackdropColor',
                'RegisterForClicks','SetHighlightTexture','EnableMouseWheel'}) do f[method]=function() end end
            return f
        end
        CreateFrame=function(_,_,parent) return widget(parent) end
        BG={BGNext={},CreateButton=function(parent) return widget(parent) end}
        C_Timer={NewTimer=function(_,callback)
            local timer={callback=callback};function timer:Cancel() self.cancelled=true end
            tasks[#tasks+1]=timer;return timer
        end}
        C_Item=nil;GameTooltip=nil
        local Wishlist=dofile('Core/BGNext/Wishlist.lua')
        local Browse=dofile('Core/BGNext/WishlistBrowse.lua')
        local root,raid,enabled,reads={wishlist={}},'A',true,0
        local slotLimit=1
        local info={[100]={name='Head',equipLoc='INVTYPE_HEAD'},[101]={name='Neck',equipLoc='INVTYPE_NECK'}}
        local loot={N={boss1={100,101,102},boss1other={999}}}
        local main=widget();local parent=widget(main);local clear=widget(parent)
        local view
        local function contains(id,scope) return Wishlist.contains(root,1,'Player',scope,id) end
        view=Browse.attach(parent,{
            main=main,clearButton=clear,enabled=function() return enabled end,closePicker=function() end,
            changed=function()
                local was=view.frame:IsVisible();view.frame:SetShown(view.mode=='slots')
                if was and view.mode=='slots' then view:refresh() end
            end,
            context=function() return {raidId=raid,difficulties={'N'},loot=loot,bossLimit=1} end,
            readInfo=function(id) reads=reads+1;return info[id] end,
            contains=contains,sourceLabel=function() return 'Boss 1 / Normal' end,
            add=function(id,scope)
                return Wishlist.placeItem(root,1,'Player',scope,{difficulties=1,bosses=1,slots=slotLimit},id,
                    function(value) return Wishlist.resolveDrop(value,{'N'},loot,1,function(a,b) return a==b end) end).ok
            end,
            remove=function(id,scope)
                local matches=Wishlist.findItem(root,1,'Player',scope,id)
                for _,match in ipairs(matches) do Wishlist.clearSlot(root,1,'Player',scope,match.difficultyIndex,match.bossIndex,match.slotIndex) end
                return #matches>0
            end,
        })
        T.eq(view.mode,'boss');T.eq(reads,0,'default boss view does not query the candidate catalog')
        view:setMode('slots');T.eq(view.frame:IsVisible(),true)
        T.eq(view.frame.events.GET_ITEM_INFO_RECEIVED,true,'live item-cache event is wired')
        local function row(id)
            for _,frame in ipairs(frames) do if frame.entry and frame.entry.itemId==id then return frame end end
        end
        local first=row(100);first.scripts.OnClick(first,'LeftButton')
        T.eq(contains(100,'A'),true,'real candidate click adds through original wishlist capacity rules')
        slotLimit=2;first=row(100);first.scripts.OnClick(first,'LeftButton')
        T.eq(#Wishlist.findItem(root,1,'Player','A',100),1,'repeated clicks do not consume another wish slot')
        slotLimit=1
        local second=row(101);second.scripts.OnClick(second,'LeftButton')
        T.eq(contains(101,'A'),false,'full boss remains full')
        T.eq(contains(100,'A'),true,'failed add never overwrites the existing wish')
        first=row(100);first.scripts.OnClick(first,'RightButton')
        T.eq(contains(100,'A'),false,'right click removes through the original store')
        local uncached=row(102)
        local staleEntry=uncached.entry
        info[102]={name='Trinket',equipLoc='INVTYPE_TRINKET'}
        view.frame.scripts.OnEvent(view.frame,'GET_ITEM_INFO_RECEIVED',102,true)
        view.frame.scripts.OnEvent(view.frame,'GET_ITEM_INFO_RECEIVED',102,true)
        T.eq(#tasks,1)
        parent:Hide();local hiddenReads=reads;tasks[1].callback()
        T.eq(reads,hiddenReads,'parent hide cancels a real event-driven cache refresh')
        T.eq(view.frame.events.GET_ITEM_INFO_RECEIVED,nil,'hidden view unregisters item events')
        parent:Show();view:setMode('slots')
        local pressed=row(100)
        pressed.scripts.OnMouseDown(pressed,'LeftButton')
        info[100]={name='Z-last',equipLoc='INVTYPE_HEAD'}
        view:refresh()
        T.eq(pressed.entry.itemId~=100,true,'cache refresh can rebind a pressed row')
        local reboundId=pressed.entry.itemId
        pressed.scripts.OnClick(pressed,'LeftButton')
        T.eq(contains(reboundId,'A'),false,'rebound row cannot add a different item on mouse release')
        raid='B';view:refresh()
        T.eq(view.controller:act(staleEntry,'LeftButton'),false,'stale raid click is rejected')
        T.eq(contains(102,'A'),false);T.eq(contains(102,'B'),false)
        for _,frame in ipairs(frames) do
            if frame.entry and frame:IsVisible() then
                T.eq(frame.point[5]-frame:GetHeight()>=-main:GetHeight()+100,true,'visible rows stay above footer controls')
            end
        end
        enabled=false;hiddenReads=reads;view:refresh()
        T.eq(reads,hiddenReads,'disabled feature does not collect candidate metadata')
    end)
    for _,key in ipairs(keys) do _G[key]=old[key] end
    if not okay then error(reason) end
end
