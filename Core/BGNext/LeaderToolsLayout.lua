BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {
    WIDTH = 720,
    HEIGHT = 500,
    SCREEN_MARGIN = 16,
    MIN_SCALE = 0.70,
    HEADER_HEIGHT = 72,
    BOTTOM_INSET = 14,
    CONTENT_HEIGHT = 414,
    TEMPLATES = { editorLeft = 205, bodyBottom = 112, statusBottom = 86, primaryBottom = 50, secondaryBottom = 16 },
    HISTORY = { bodyBottom = 62 },
    AUCTIONS = { hintTop = 47, scrollTop = 76, scrollBottom = 12, childWidth = 640, rowWidth = 620, rowHeight = 30, maxRows = 20 },
    SETTLEMENT = { textBottom = 72 },
}

local FOOTERS = {
    templates = 82,
    history = 52,
    auctions = 12,
    settlement = 62,
}

function M.scaleFor(parentWidth, parentHeight)
    if type(parentWidth) ~= "number" or type(parentHeight) ~= "number"
        or parentWidth <= 0 or parentHeight <= 0 then
        return 1
    end
    local margin = M.SCREEN_MARGIN * 2
    local scale = math.min(1, (parentWidth - margin) / M.WIDTH, (parentHeight - margin) / M.HEIGHT)
    return math.max(M.MIN_SCALE, scale)
end

function M.pageRegion(page)
    local footer = FOOTERS[page] or 0
    return { top = 0, footerTop = M.CONTENT_HEIGHT - footer, bottom = M.CONTENT_HEIGHT }
end

function M.auctionVisibleRows(contentHeight)
    local available = math.max(30, (tonumber(contentHeight) or M.CONTENT_HEIGHT) - 82)
    return math.max(1, math.min(M.AUCTIONS.maxRows, math.floor(available / M.AUCTIONS.rowHeight)))
end

BG.BGNext.LeaderToolsLayout = M
return M
