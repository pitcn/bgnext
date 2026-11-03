return function(T)
    BG = {BGNext = {}}
    local Browse = dofile('Core/BGNext/WishlistBrowse.lua')
    local loot = {N={boss1={100,101,102,103,100},boss2={100,104},boss1other={999}},
        H={boss1={105}},ExchangeItems={[102]={999}}}
    local info = {
        [100]={name='Helmet',equipLoc='INVTYPE_HEAD'},
        [101]={name='Robe',equipLoc='INVTYPE_ROBE'},
        [102]={name='Token',equipLoc=''},
        [104]={name='Weapon',equipLoc='INVTYPE_2HWEAPON'},
        [105]={name='Shield',equipLoc='INVTYPE_SHIELD'},
    }
    local rows,pending = Browse.collect({'N','H'},loot,2,function(id) return info[id] end)
    T.eq(#rows,6,'deduplicate direct drops across bosses without adding exchange products')
    local byId={};for _, row in ipairs(rows) do byId[row.itemId]=row end
    T.eq(#byId[100].sources,2,'retain both boss sources')
    T.eq(byId[101].group,'CHEST','robes group with chest armor')
    T.eq(byId[102].group,'OTHER','non-equippable direct tokens remain available')
    T.eq(byId[103].group,'UNKNOWN','uncached metadata is not discarded')
    T.eq(pending[103],true)
    T.eq(byId[999],nil,'exchanged finished items never become direct-drop wishes')
    T.eq(#Browse.filter(rows,'HEAD'),1)
    T.eq(#Browse.filter(rows,'ALL'),6)
    T.eq(Browse.groupFor('INVTYPE_WEAPONOFFHAND'),'OFFHAND')
    T.eq(Browse.groupFor('INVTYPE_RANGEDRIGHT'),'RANGED')
    info[103]={name='Trinket',equipLoc='INVTYPE_TRINKET'}
    local loaded=Browse.collect({'N','H'},loot,2,function(id) return info[id] end)
    T.eq(#Browse.filter(loaded,'TRINKET'),1,'loaded metadata enters its correct group')
    T.eq(#Browse.filter(loaded,'UNKNOWN'),0)
    T.eq(loot.N.boss1[1],100,'browsing never mutates the drop catalog')
    local visible,raid,reads = true,'A',0
    local tasks,rendered,added = {},nil,{}
    local controller = Browse.newController({
        visible=function() return visible end,
        context=function() return {raidId=raid,difficulties={'N'},loot=loot,bossLimit=2} end,
        readInfo=function(id) reads=reads+1;return info[id] end,
        render=function(page,total) rendered=page end,
        schedule=function(callback)
            local timer={callback=callback};function timer:Cancel() self.cancelled=true end
            tasks[#tasks+1]=timer;return timer
        end,
        add=function(id,scope) added[#added+1]={id,scope};return true end,
        remove=function() return true end,
    })
    controller:refresh()
    local first=rendered[1]
    T.eq(controller:act(first,'LeftButton'),true)
    T.eq(added[1][2],'A','add goes through the original raid scope')
    raid='B'
    T.eq(controller:act(first,'LeftButton'),false,'stale raid rows cannot write wishes')
    controller:refresh()
    info[103]=nil; controller:refresh()
    controller:onItemInfo(103,true);controller:onItemInfo(103,true)
    T.eq(#tasks,1,'cache event bursts are merged')
    visible=false;controller:hide()
    local hiddenReads=reads
    tasks[1].callback()
    controller:onItemInfo(103,true)
    T.eq(reads,hiddenReads,'hidden and cancelled cache callbacks never query or render')
    T.eq(#added,1,'cache completion never edits wishlist data')
end
