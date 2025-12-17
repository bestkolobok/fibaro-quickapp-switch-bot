--%%name:Curtain
--%%type:com.fibaro.rollerShutter
--%%var:profile_token="759a6fb194f55fb72b2f1fc52fb5b9d526fcdc8075d066ddf1eacbc8e444380fb20092857de9c9a12769148379d162cc"
--%%var:device_id="F3DE1D6C45B5"
--%%var:profile_secret="e5d2908b986a43be91219f0817242e80"
--%%project:393
--%%desktop:true

-- SwitchBot Curtain QuickApp for Fibaro HC3
-- Required variables:
-- profile_token - your API token from SwitchBot app
-- profile_secret - your Secret Key from SwitchBot app  
-- device_id - device ID (MAC address without colons)

-- Generate authorization headers for SwitchBot API
function QuickApp:getAuthHeaders()
    local token = self:getVariable("profile_token")
    local secret = self:getVariable("profile_secret")
    
    -- For API v1.0 (simpler authentication)
    if secret == "" or secret == nil then
        return {
            ["Authorization"] = token,
            ["Content-Type"] = "application/json; charset=utf8"
        }
    end
    
    -- For API v1.1 (requires signature)
    -- Note: Fibaro doesn't have native HMAC-SHA256, so we'll try without it first
    local t = tostring(os.time() * 1000)
    local nonce = ""  -- Empty nonce for now
    
    return {
        ["Authorization"] = token,
        ["Content-Type"] = "application/json; charset=utf8",
        ["sign"] = secret,  -- Using secret directly as a test
        ["t"] = t,
        ["nonce"] = nonce
    }
end

function QuickApp:open()
    self:debug("Opening curtain...")
    self:setValue(100)
end

function QuickApp:close()
    self:debug("Closing curtain...")
    self:setValue(0)
end

function QuickApp:stop()
    self:debug("Stopping curtain...")
    self:sendCommand("pause", "")
end

function QuickApp:setValue(value)
    local StateValue = 100 - value
    self:sendCommand("setPosition", "0,ff," .. tostring(StateValue))
    self:updateProperty("value", value)
end

function QuickApp:sendCommand(command, parameter)
    local devId = self:getVariable("device_id")
    if devId == "" or devId == nil then
        self:debug("[ERROR] Device ID not set!")
        return
    end

    -- Try API v1.0 first (simpler)
    local url = "https://api.switch-bot.com/v1.1/devices/" .. devId .. "/commands"
    
    local requestBody = json.encode({
        command = command,
        parameter = parameter,
        commandType = "command"
    })
    
    self:debug("Sending command: " .. command)
    self:debug("URL: " .. url)
    
    local http = net.HTTPClient()
    http:request(url, {
        options = {
            data = requestBody,
            method = 'POST',
            headers = {
                ["Authorization"] = self:getVariable("profile_token"),
                ["Content-Type"] = "application/json; charset=utf8"
            }
        },
        success = function(response)
            self:debug("Response status: " .. tostring(response.status))
            
            if response.data then
                self:debug("Response data: " .. response.data)
                
                local success, result = pcall(json.decode, response.data)
                if success and result then
                    if result.statusCode == 100 then
                        self:debug("✓ Command sent successfully")
                    else
                        self:debug("✗ Error: " .. tostring(result.message))
                    end
                end
            else
                self:debug("No response data")
            end
        end,
        error = function(err)
            self:debug('[ERROR] ' .. err)
        end
    })
end

function QuickApp:getStateFromCloud()
    local devId = self:getVariable("device_id")
    if devId == "" or devId == nil then
        self:debug("[INFO] Device ID not set")
        return
    end
    
    -- Try API v1.0 first
    local url = "https://api.switch-bot.com/v1.0/devices/" .. devId .. "/status"
    
    self:debug("Getting status from: " .. url)
    
    local http = net.HTTPClient()
    http:request(url, {
        options = {
            method = 'GET',
            headers = {
                ["Authorization"] = self:getVariable("profile_token")
            }
        },
        success = function(response)
            self:debug("Status response code: " .. tostring(response.status))
            
            if not response.data then
                self:debug("[ERROR] No response data")
                return
            end
            
            self:debug("Response data: " .. response.data)
            
            local success, result = pcall(json.decode, response.data)
            if not success then
                self:debug("[ERROR] JSON decode failed: " .. tostring(result))
                return
            end
            
            if not result then
                self:debug("[ERROR] Decoded result is nil")
                return
            end
            
            self:debug("Status code: " .. tostring(result.statusCode))
            
            if result.statusCode == 100 and result.body then
                if result.body.slidePosition ~= nil then
                    local slidePosition = tonumber(result.body.slidePosition)
                    local fibaroValue = 100 - slidePosition
                    self:updateProperty("value", fibaroValue)
                    self:debug("Current position: " .. tostring(fibaroValue) .. "%")
                else
                    self:debug("No slidePosition in response")
                end
            else
                self:debug("Error: " .. tostring(result.message or "Unknown error"))
            end
        end,
        error = function(err)
            self:debug('[ERROR] HTTP request failed: ' .. err)
        end
    })
end

function QuickApp:getAllDevices()
    self:debug("=== DISCOVERING DEVICES ===")
    
    -- Try v1.0 API
    local url = "https://api.switch-bot.com/v1.0/devices"
    
    local http = net.HTTPClient()
    http:request(url, {
        options = {
            method = 'GET',
            headers = {
                ["Authorization"] = self:getVariable("profile_token")
            }
        },
        success = function(response)
            if not response.data then
                self:debug("[ERROR] No response data")
                return
            end
            
            self:debug("Discovery response: " .. response.data:sub(1, 200) .. "...")
            
            local success, result = pcall(json.decode, response.data)
            if not success or not result then
                self:debug("[ERROR] Failed to parse devices")
                return
            end
            
            if result.statusCode == 100 and result.body then
                local foundCurtain = false
                
                if result.body.deviceList then
                    for _, device in ipairs(result.body.deviceList) do
                        if device.deviceType == "Curtain" or device.deviceType == "Curtain3" then
                            foundCurtain = true
                            self:debug("━━━━━━━━━━━━━━━━━━━━━")
                            self:debug("✓ CURTAIN FOUND!")
                            self:debug("  Name: " .. tostring(device.deviceName))
                            self:debug("  ID: " .. device.deviceId)
                            self:debug("  Type: " .. device.deviceType)
                            self:debug("━━━━━━━━━━━━━━━━━━━━━")
                            self:debug("→ Use this ID for device_id variable:")
                            self:debug("  " .. device.deviceId)
                        end
                    end
                end
                
                if not foundCurtain then
                    self:debug("No Curtain device found")
                end
            else
                self:debug("Error: " .. tostring(result.message or "Unknown"))
            end
        end,
        error = function(err)
            self:debug('[ERROR] Discovery failed: ' .. err)
        end
    })
end

function QuickApp:testConnection()
    self:debug("=== CONNECTION TEST ===")
    self:debug("Token: " .. (self:getVariable("profile_token") ~= "" and "✓ Set" or "✗ Missing"))
    self:debug("Secret: " .. (self:getVariable("profile_secret") ~= "" and "✓ Set" or "✗ Missing"))
    self:debug("Device ID: " .. (self:getVariable("device_id") or "Not set"))
    self:getAllDevices()
end

function QuickApp:onInit()
    self:debug("=== SwitchBot Curtain QuickApp ===")
    
    local token = self:getVariable("profile_token")
    local secret = self:getVariable("profile_secret")
    local devId = self:getVariable("device_id")
    
    if token == "" or token == nil then
        self:debug("✗ ERROR: profile_token not set!")
        self:debug("Get it from SwitchBot app → Profile → Preferences")
        return
    end
    
    self:debug("Token: " .. token:sub(1, 10) .. "...")
    
    if secret ~= "" and secret ~= nil then
        self:debug("Secret: " .. secret:sub(1, 10) .. "...")
    end
    
    if devId == "" or devId == nil then
        self:debug("Device ID not set, discovering...")
        self:getAllDevices()
    else
        self:debug("Device ID: " .. devId)
        -- Small delay before getting state
        fibaro.setTimeout(1000, function()
            self:getStateFromCloud()
        end)
    end
end