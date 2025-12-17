-- Generic API request
function QuickApp:apiRequest(path, options)
    options = options or {}
    
    local headers = self:getAuthHeaders()
    if not headers then
        if options.error then
            options.error("Authentication failed - credentials missing")
        end
        return
    end
    
    local url = self.apiUrl .. path
    local method = options.method or "GET"
    local requestBody = options.data and json.encode(options.data) or nil
    
    local http = net.HTTPClient({timeout = 10000})
    
    http:request(url, {
        options = {
            method = method,
            data = requestBody,
            headers = headers
        },
        success = function(response)
            if not response.data then
                if options.error then
                    options.error("No response data")
                end
                return
            end
            
            local success, result = pcall(json.decode, response.data)
            if not success then
                if options.error then
                    options.error("JSON parse error: " .. tostring(result))
                end
                return
            end
            
            if result.statusCode == 100 then
                if options.success then
                    options.success(result.body, response.status)
                end
            else
                local errorMsg = result.message or "Unknown error (code: " .. tostring(result.statusCode) .. ")"
                self:debug("API error: " .. errorMsg)
                if options.error then
                    options.error(errorMsg)
                end
            end
        end,
        error = function(err)
            self:debug("HTTP error: " .. tostring(err))
            if options.error then
                options.error(err)
            end
        end
    })
end

-- Send command to device
function QuickApp:sendDeviceCommand(deviceId, command, parameter)
    self:debug("Sending command: " .. command .. " to device: " .. deviceId)
    
    local path = "devices/" .. deviceId .. "/commands"
    
    self:apiRequest(path, {
        method = "POST",
        data = {
            command = command,
            parameter = parameter or "default",
            commandType = "command"
        },
        success = function(body, status)
            self:debug("✓ Command sent successfully")
        end,
        error = function(err)
            self:warning("✗ Command failed: " .. tostring(err))
        end
    })
end

-- Get device status
function QuickApp:getDeviceStatus(deviceId, callback)
    local path = "devices/" .. deviceId .. "/status"
    
    self:apiRequest(path, {
        method = "GET",
        success = function(body, status)
            if callback then
                callback(body)
            end
        end,
        error = function(err)
            self:debug("Failed to get device status: " .. tostring(err))
            if callback then
                callback(nil)
            end
        end
    })
end
