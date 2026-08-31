BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {
    projectName = "BGNext",
    version = "0.2.3",
    upstreamName = "BGLite",
    upstreamVersion = "2.4.0",
    protocolVersion = "2.4.0",
    commands = { "/bgn", "/bgnext", "/bglite", "/biaoge" },
}

local publicCommands = {
    ["/bgn"] = true,
    ["/bgnext"] = true,
}

local registeredCommands = {
    ["/bgn"] = true,
    ["/bgnext"] = true,
    ["/bglite"] = true,
    ["/biaoge"] = true,
}

function M.isPublicCommand(command)
    return publicCommands[type(command) == "string" and command:lower() or ""] == true
end

function M.isRegisteredCommand(command)
    return registeredCommands[type(command) == "string" and command:lower() or ""] == true
end

BG.BGNext.Identity = M
return M
