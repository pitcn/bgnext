local T = { passed = 0, failed = 0 }

function T.eq(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function T.run(name, fn)
    local ok, err = pcall(fn, T)
    if ok then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        io.stderr:write(name .. ": " .. err .. "\n")
    end
end

return T
