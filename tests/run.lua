local T = dofile("tests/testlib.lua")
local suites = {
    "tests/test_init.lua",
    "tests/test_data_lifecycle.lua",
    "tests/test_baseline_safety.lua",
}

for _, path in ipairs(suites) do
    T.run(path, dofile(path))
end

print(string.format("passed=%d failed=%d", T.passed, T.failed))
if T.failed > 0 then
    os.exit(1)
end
