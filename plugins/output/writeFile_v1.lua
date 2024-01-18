-- Marking: lua,output,writeFile,1

output = {
    category = "aggregator",
    name = "converge",
    version = "1",
    indicator = "writeFile"
}

function description()
    u:Set("lua", "output", "writeFile", "1")
    print("lua, output, writeFile, 1")
end

function writeToFile(filePath, jsonString)
    print("output: file path: ", filePath)
    file = io.open(filePath, "a")
    file:write(jsonString)
    file:close()
end

function write(startTime, endTime, dataBox)
    reportUseData, err = dataBox:GetFields(
        output.category,
        output.name,
        output.version,
        output.indicator,
        startTime,
        endTime)

    local reportJson = ""
    dataLen = reportUseData:Len()
    print("output: reportUseData len", dataLen)
    for i=1, dataLen do
        field = reportUseData:GetField(i-1)
        -- print("field:", type(field), field)
        -- print("Loop fieldList: index,", i)
        -- print("field", field:Len())
        fieldLen = field:Len()
        for j=1, fieldLen do
            unit = field:GetUnit(j-1)
            unitKey = unit:GetKey()
            unitValue = unit:GetValue()
            -- print("output: Unit Key", unitKey)
            -- print("output: Unit Value", unitValue)
            reportJson = unitValue
        end
    end

    print("output: Json string: ", reportJson)
    writeToFile("/mnt/d/code/myself/build_test/project_lua/json_string.json", reportJson)
end
