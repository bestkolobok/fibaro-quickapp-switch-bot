-- ============================================
-- Device Discovery
-- ============================================

-- Supported device types
local SUPPORTED_DEVICES = {
    ["Bot"] = true,
    ["Curtain"] = true,
    ["Curtain3"] = true,
    -- Add more supported devices here as needed:
    -- ["Plug"] = true,
    -- ["Plug Mini (US)"] = true,
    -- ["Plug Mini (JP)"] = true,
}

-- Get human-readable device type name
local function getDeviceTypeName(deviceType)
    local names = {
        ["Curtain"] = "Curtain",
        ["Curtain3"] = "Curtain 3",
        ["Bot"] = "Bot",
    }
    return names[deviceType] or deviceType
end

-- UI Handler: Search for devices
function QuickApp:searchDevices()
    self:debug("=== DISCOVERING DEVICES ===")
    self:updateView("label_status", "text", "Status: Searching...")
    
    -- Clear previous search results
    self.foundDevices = {}
    self.selectedDevices = {}
    
    -- Reset selector with placeholder
    self:updateView("select_devices", "options", {
        {text = "— Searching... —", type = "option", value = ""}
    })
    self:updateView("button_add", "text", "Add Selected (0)")
    
    self:apiRequest("devices", {
        method = "GET",
        success = function(body, status)
            self:processDiscoveredDevices(body)
        end,
        error = function(err)
            self:warning("Discovery failed: " .. tostring(err))
            self:updateView("label_status", "text", "Status: Discovery failed")
        end
    })
end

-- Process discovered devices
function QuickApp:processDiscoveredDevices(body)
    if not body or not body.deviceList then
        self:debug("No devices found")
        self:updateView("label_status", "text", "Status: No devices found")
        return
    end
    
    local selectorOptions = {}
    local foundCount = 0
    local alreadyAddedCount = 0
    
    for _, device in ipairs(body.deviceList) do
        local deviceType = device.deviceType
        
        -- Check if device type is supported
        if SUPPORTED_DEVICES[deviceType] then
            local deviceId = device.deviceId
            local deviceName = device.deviceName or "Unknown"
            local isAlreadyAdded = self:isDeviceAlreadyAdded(deviceId)
            
            -- Store device info for later use
            self.foundDevices[deviceId] = {
                deviceId = deviceId,
                deviceName = deviceName,
                deviceType = deviceType,
                hubDeviceId = device.hubDeviceId,
                enableCloudService = device.enableCloudService,
                isAlreadyAdded = isAlreadyAdded
            }
            
            if isAlreadyAdded then
                alreadyAddedCount = alreadyAddedCount + 1
                self:debug("  [EXISTS] " .. deviceName .. " (" .. deviceType .. ")")
            else
                foundCount = foundCount + 1
                
                -- Add to selector options
                local displayName = deviceName:sub(1, 25) .. " [" .. getDeviceTypeName(deviceType) .. "]"
                table.insert(selectorOptions, {
                    text = displayName,
                    type = "option",
                    value = deviceId
                })
                
                self:debug("  [NEW] " .. deviceName .. " (" .. deviceType .. ")")
            end
        end
    end
    
    -- Also check infrared remote devices if present
    if body.infraredRemoteList then
        for _, device in ipairs(body.infraredRemoteList) do
            self:debug("  [IR] " .. (device.deviceName or "Unknown") .. " (not supported)")
        end
    end
    
    -- Update UI
    if foundCount > 0 then
        self:updateView("select_devices", "options", selectorOptions)
        self:updateView("button_add", "text", "Add Selected (0)")
        self:updateView("label_status", "text", "Status: Found " .. foundCount .. " new device(s)")
    else
        -- Clear selector with placeholder
        self:updateView("select_devices", "options", {
            {text = "— No devices found —", type = "option", value = ""}
        })
        
        if alreadyAddedCount > 0 then
            self:updateView("label_status", "text", "Status: All " .. alreadyAddedCount .. " device(s) already added")
        else
            self:updateView("label_status", "text", "Status: No supported devices found")
        end
    end
    
    self:debug("━━━━━━━━━━━━━━━━━━━━━")
    self:debug("Discovery complete:")
    self:debug("  New devices: " .. foundCount)
    self:debug("  Already added: " .. alreadyAddedCount)
    self:debug("━━━━━━━━━━━━━━━━━━━━━")
end

-- UI Handler: Test connection / get all devices info
function QuickApp:testConnection()
    self:debug("=== CONNECTION TEST ===")
    
    local token = self:getVariable("profile_token")
    local secret = self:getVariable("profile_secret")
    
    self:debug("Token: " .. (token and token ~= "" and "✓ Set (" .. token:sub(1, 10) .. "...)" or "✗ Missing"))
    self:debug("Secret: " .. (secret and secret ~= "" and "✓ Set" or "✗ Missing"))
    
    if not token or token == "" or not secret or secret == "" then
        self:updateView("label_status", "text", "Status: Credentials missing")
        return
    end
    
    self:updateView("label_status", "text", "Status: Testing connection...")
    
    self:apiRequest("devices", {
        method = "GET",
        success = function(body, status)
            local deviceCount = body.deviceList and #body.deviceList or 0
            self:debug("✓ Connection successful! Found " .. deviceCount .. " devices in account.")
            self:updateView("label_status", "text", "Status: Connected (" .. deviceCount .. " devices)")
        end,
        error = function(err)
            self:debug("✗ Connection failed: " .. tostring(err))
            self:updateView("label_status", "text", "Status: Connection failed")
        end
    })
end