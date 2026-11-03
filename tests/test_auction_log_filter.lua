return function(T)
    BG = {BGNext = {}}
    dofile('Core/BGNext/PlayerIdentity.lua')
    local Filter = dofile('Core/BGNext/AuctionLogFilter.lua')
    local success = {type = 1, maijia = 'Alice-MyRealm', jine = 100, trade = false}
    T.eq(Filter.include(success, 6, 'Alice', 'My Realm'), true,
        'full buyer identity matches the logged-in short name without a player cache')
    T.eq(Filter.include(success, 6, 'Alice-OtherRealm', 'OtherRealm'), false,
        'same short name on another realm is excluded')
    T.eq(Filter.include({type=1,maijia='Alt-MyRealm'},6,'Alice','MyRealm',{Alt={class='MAGE'}}),true,
        'retain the existing same-realm own-character purchase scope')
    T.eq(Filter.include({type=1,maijia='Alt-OtherRealm'},6,'Alice','MyRealm',{Alt={class='MAGE'}}),false,
        'a known local alt never authorizes the same name on another realm')
    T.eq(Filter.include({type=1, maijia='Alice'}, 6, 'Alice-MyRealm', 'MyRealm'), true)
    T.eq(Filter.include({type=2, maijia='Alice'}, 6, 'Alice', 'MyRealm'), false)
    T.eq(Filter.include({type=1}, 6, 'Alice', 'MyRealm'), false)
    for _, choice in ipairs({1,2,5}) do T.eq(Filter.include(success, choice, 'Bob', 'MyRealm'), true) end
    T.eq(Filter.include(success, 3, 'Alice', 'MyRealm'), false)
    T.eq(Filter.include({type=2}, 3, 'Alice', 'MyRealm'), true)
    T.eq(Filter.include({type=1,trade=true}, 5, 'Alice', 'MyRealm'), false)
    for _, choice in ipairs({4,7,99}) do T.eq(Filter.include(success, choice, 'Alice', 'MyRealm'), false) end
    T.eq(success.trade, false, 'filtering never changes payment state')
    T.eq(success.jine, 100, 'filtering never changes the amount')
end
