local AddonName, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- In-game trade-result announcements. This wires the "交易通报" settings that
-- were left visible but disconnected when the legacy TradeHistory module was
-- quarantined. It is an independent, memory-only implementation: it does not
-- reload or read the old history.
--
-- A result is announced only on reliable evidence — ERR_TRADE_COMPLETE for a
-- finished trade, or an explicit cancel / bag-full error for a failure. Merely
-- closing the trade window announces nothing. Each trade window announces at
-- most once, so a repeated completion message or a rapid succession of trades
-- can never double-send or cross-contaminate. The message carries only the
-- trade target's name and the result; no items, gold or other-player data are
-- broadcast, and nothing is stored or archived.
local M = {}

-- Resolves the configured channel preference into the concrete chat channel
-- for the current group, or nil when there is nowhere to send. The settings UI
-- accepts only WHISPER and RAID.
function M.resolveChannel(preference, inRaid, inGroup)
    if preference == "WHISPER" then
        return "WHISPER"
    end
    if preference ~= "RAID" then
        return nil
    end
    if inRaid then
        return "RAID"
    end
    if inGroup then
        return "PARTY"
    end
    return nil
end

-- Decides whether one trade result is announced and, when it is, the channel
-- and the exact whisper target. Returns nil when the master switch, the result
-- sub-switch, the target or the channel makes a send impossible or dishonest.
function M.decide(options, result)
    if type(options) ~= "table" or not options.master then
        return nil
    end
    if type(result) ~= "table" then
        return nil
    end
    local kind = result.kind
    if kind == "success" then
        if not options.success then
            return nil
        end
    elseif kind == "fail" then
        if not options.fail then
            return nil
        end
    else
        return nil
    end
    local target = result.target
    if type(target) ~= "string" or not target:find("%S") then
        return nil
    end
    local channel = M.resolveChannel(options.channel, options.inRaid, options.inGroup)
    if not channel then
        return nil
    end
    return {
        kind = kind,
        target = target,
        channel = channel,
    }
end

local FALLBACK_L = setmetatable({}, {
    __index = function(_, key)
        return tostring(key)
    end,
})

-- Renders the localized announcement text. The message reuses the strings the
-- settings already localize; the trailing detail slot stays empty so no item
-- or gold detail is broadcast.
function M.render(decision, L)
    L = L or FALLBACK_L
    if type(decision) ~= "table" then
        return nil
    end
    if decision.kind == "success" then
        return string.format(L["与<%s>交易成功！%s"], decision.target, "")
    end
    return string.format(L["与<%s>交易失败！"], decision.target)
end

if BG.Init then
    BG.Init(function()
        local L = ns and ns.L

        -- Memory-only, per-trade-window guard: one announcement per result, and
        -- the trade partner visible when the window opened. The partner is
        -- captured here because the live Trade.lua handler resets BG.trade (and
        -- clears target) immediately after TRADE_SHOW; reading BG.trade.target
        -- again at result time would either be nil or a later trade's partner.
        local announced = false
        local tradeTarget = nil

        local function announce(kind)
            local target = tradeTarget
            local options = BiaoGe and BiaoGe.options or {}
            local decision = M.decide({
                master = options.tradeMSG == 1,
                success = options.tradeMSG_success == 1,
                fail = options.tradeMSG_false == 1,
                channel = options.tradeMSG_channel,
                inRaid = IsInRaid and IsInRaid(1) and true or false,
                inGroup = IsInGroup and IsInGroup(1) and true or false,
            }, {
                kind = kind,
                target = target,
            })
            if not decision then
                return
            end
            SendChatMessage(M.render(decision, L), decision.channel, nil,
                decision.channel == "WHISPER" and decision.target or nil)
        end

        BG.RegisterEvent("TRADE_SHOW", function()
            announced = false
            local trade = BG.trade
            tradeTarget = type(trade) == "table" and trade.target or nil
        end)

        BG.RegisterEvent("UI_INFO_MESSAGE", function(_, _, _, text)
            if text == ERR_TRADE_COMPLETE then
                if announced then
                    return
                end
                announced = true
                announce("success")
            elseif text == ERR_TRADE_CANCELLED
                or text == ERR_TRADE_BAG_FULL
                or text == ERR_TRADE_TARGET_BAG_FULL then
                if announced then
                    return
                end
                announced = true
                announce("fail")
            end
        end)
    end)
end

BG.BGNext.TradeAnnouncement = M
return M
