return function(test)
    local f = assert(io.open("Core/Module/Auction.lua", "rb")); local source = f:read("*a"); f:close()
    local block = assert(source:match("%-%- 默认起拍价\n(.-)%-%- 默认起拍价结束"), "default price block present")

    local function run(flags, money)
        local bg = { Once = function() end }
        for k, v in pairs(flags) do bg[k] = v end
        local saved = { Auction = { money = money } }
        local fn = assert(loadstring(block)); setfenv(fn, { BG = bg, BiaoGe = saved, tonumber = tonumber }); fn()
        return saved.Auction.money, saved.Auction.fastMoney
    end

    local forever = { verLess2 = true, IsVanilla = true, IsForever = true }
    test.eq(run(forever, nil), 10, "new Forever user starts at 10")
    test.eq(run(forever, ""), 10, "Forever empty saved value is invalid and becomes 10")
    test.eq(run(forever, "abc"), 10, "Forever non-numeric saved value becomes 10")
    test.eq(run(forever, 100), 100, "Forever saved 100 is kept, no migration")
    test.eq(run(forever, 50), 50, "Forever saved 50 is kept")
    test.eq(run(forever, "50"), "50", "Forever saved text 50 is kept untouched")
    test.eq(run(forever, 0), 0, "Forever saved 0 is kept")
    local _, fast = run(forever, nil)
    test.eq(table.concat(fast, ","), "100,300,500,1000,2000", "Forever quick buttons unchanged")

    local vanilla = { verLess2 = true, IsVanilla = true }
    test.eq(run(vanilla, nil), 100, "non-Forever vanilla keeps 100")
    test.eq(run(vanilla, 50), 50, "vanilla saved value kept")
    test.eq(run({ verLess2 = true, IsTBC = true }, nil), 100, "tbc keeps 100")
    test.eq(run({ IsTitan = true }, nil), 100, "titan keeps 100")
    test.eq(run({ IsWLK = true }, nil), 1000, "wrath keeps 1000")
    test.eq(run({ IsMOP = true }, nil), 10000, "mop keeps 10000")
    test.eq(run({ IsCTM = true }, nil), 100000, "cata keeps 100000")
    test.eq(run({ IsRetail = true }, nil), 100000, "retail keeps 100000")
    test.eq(run({ IsRetail = true }, ""), "", "non-Forever keeps the legacy nil-only fallback")
end