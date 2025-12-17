-- ============================================
-- Webhook Configuration & Handling
-- ============================================

--[[
SwitchBot Webhook documentation:
https://github.com/OpenWonderLabs/SwitchBotAPI#webhook

To use webhooks, your Fibaro HC3 must be accessible from the internet.
Options:
1. Port forwarding on router + DDNS
2. Cloudflare Tunnel
3. ngrok
4. Proxy server (Node.js, Cloudflare Worker, etc.)

Webhook URL format for Fibaro HC3:
POST http://<HC3_EXTERNAL_URL>/api/callAction
Body: {"deviceId": <QuickAppID>, "name": "handleWebhook", "args": [<webhook_data>]}

Or with proxy that converts SwitchBot format to Fibaro API call.
]]--

-- ============================================
-- Webhook Setup Functions
-- ============================================

-- Setup webhook in SwitchBot cloud
-- webhookUrl: URL where SwitchBot will send updates (must be accessible from internet)
function QuickApp:setupWebhook(webhookUrl)
    if not webhookUrl or webhookUrl == "" then
        webhookUrl = self:getVariable("webhookUrl")
    end
    
    if not webhookUrl or webhookUrl == "" then
        self:warning("Webhook URL not set! Set 'webhookUrl' variable first.")
        self:updateView("label_status", "text", "Status: Webhook URL missing")
        return
    end
    
    self:debug("Setting up webhook: " .. webhookUrl)
    self:updateView("label_status", "text", "Status: Setting up webhook...")
    
    self:apiRequest("webhook/setupWebhook", {
        method = "POST",
        data = {
            action = "setupWebhook",
            url = webhookUrl,
            deviceList = "ALL"
        },
        success = function(body, status)
            self:debug("✓ Webhook setup successful")
            self:setVariable("webhookUrl", webhookUrl)
            self:setVariable("webhookEnabled", "true")
            self:updateView("label_status", "text", "Status: Webhook active")
            
            -- Stop polling if webhook is active
            self:stopPolling()
        end,
        error = function(err)
            self:warning("✗ Webhook setup failed: " .. tostring(err))
            self:updateView("label_status", "text", "Status: Webhook setup failed")
        end
    })
end

-- Query current webhook configuration
function QuickApp:queryWebhook()
    self:debug("Querying webhook configuration...")
    
    self:apiRequest("webhook/queryWebhook", {
        method = "POST",
        data = {
            action = "queryUrl"
        },
        success = function(body, status)
            if body and body.urls then
                self:debug("Current webhook URLs:")
                for i, url in ipairs(body.urls) do
                    self:debug("  " .. i .. ": " .. url)
                end
                
                if #body.urls > 0 then
                    self:updateView("label_status", "text", "Status: Webhook configured")
                else
                    self:updateView("label_status", "text", "Status: No webhook configured")
                end
            else
                self:debug("No webhooks configured")
                self:updateView("label_status", "text", "Status: No webhook configured")
            end
        end,
        error = function(err)
            self:warning("Query webhook failed: " .. tostring(err))
        end
    })
end

-- Delete webhook
function QuickApp:deleteWebhook(webhookUrl)
    if not webhookUrl or webhookUrl == "" then
        webhookUrl = self:getVariable("webhookUrl")
    end
    
    if not webhookUrl or webhookUrl == "" then
        self:warning("No webhook URL to delete")
        return
    end
    
    self:debug("Deleting webhook: " .. webhookUrl)
    
    self:apiRequest("webhook/deleteWebhook", {
        method = "POST",
        data = {
            action = "deleteWebhook",
            url = webhookUrl
        },
        success = function(body, status)
            self:debug("✓ Webhook deleted")
            self:setVariable("webhookEnabled", "false")
            self:updateView("label_status", "text", "Status: Webhook removed")
            
            -- Restart polling as fallback
            self:startPolling()
        end,
        error = function(err)
            self:warning("Delete webhook failed: " .. tostring(err))
        end
    })
end

-- ============================================
-- Webhook Handler
-- ============================================

--[[
SwitchBot webhook payload format:
{
    "eventType": "changeReport",
    "eventVersion": "1",
    "context": {
        "deviceType": "Curtain3",
        "deviceMac": "F3DE1D6C45B5",
        "timeOfSample": 1698765432,
        "slidePosition": 50,
        "battery": 85,
        ...
    }
}

To call this from external service:
POST http://<HC3_IP>/api/callAction
Headers: 
  Authorization: Basic <base64(admin:password)>
  Content-Type: application/json
Body:
{
    "deviceId": <QuickAppID>,
    "name": "handleWebhook",
    "args": [<webhook_payload_as_string_or_object>]
}
]]--

-- Handle incoming webhook from SwitchBot (called via Fibaro API)
function QuickApp:handleWebhook(payload)
    self:debug("Webhook received!")
    
    -- Parse payload if it's a string
    local data = payload
    if type(payload) == "string" then
        local success, parsed = pcall(json.decode, payload)
        if success then
            data = parsed
        else
            self:warning("Failed to parse webhook payload")
            return
        end
    end
    
    -- Validate payload
    if not data or type(data) ~= "table" then
        self:warning("Invalid webhook payload")
        return
    end
    
    self:trace("Webhook data: " .. json.encode(data))
    
    -- Handle different event types
    local eventType = data.eventType
    
    if eventType == "changeReport" then
        self:handleChangeReport(data.context)
    else
        self:debug("Unknown event type: " .. tostring(eventType))
    end
end

-- Handle changeReport event
function QuickApp:handleChangeReport(context)
    if not context then
        self:warning("No context in changeReport")
        return
    end
    
    local deviceMac = context.deviceMac
    local deviceType = context.deviceType
    
    if not deviceMac then
        self:warning("No deviceMac in webhook context")
        return
    end
    
    self:debug("Change report for device: " .. deviceMac .. " (" .. tostring(deviceType) .. ")")
    
    -- Find device by MAC (SwitchBot deviceId is MAC without colons)
    local device = self:getDeviceBySwitchBotId(deviceMac)
    
    if not device then
        self:debug("Device not found for MAC: " .. deviceMac)
        return
    end
    
    -- Apply status based on device type
    if deviceType == "Curtain" or deviceType == "Curtain3" or deviceType == "WoCurtain" then
        self:applyWebhookCurtainStatus(device, context)
    elseif deviceType == "Bot" or deviceType == "WoHand" then
        self:applyWebhookBotStatus(device, context)
    else
        self:debug("Unhandled device type in webhook: " .. tostring(deviceType))
    end
end

-- Apply Curtain status from webhook
function QuickApp:applyWebhookCurtainStatus(device, context)
    -- slidePosition: 0 = open, 100 = closed (SwitchBot)
    -- Fibaro: 0 = closed, 100 = open
    if context.slidePosition ~= nil then
        local switchBotPosition = tonumber(context.slidePosition)
        if switchBotPosition then
            local fibaroValue = 100 - switchBotPosition
            device:updateProperty("value", fibaroValue)
            self:debug("Updated curtain position: " .. fibaroValue .. "%")
        end
    end
    
    -- Battery
    if context.battery ~= nil then
        local battery = tonumber(context.battery)
        if battery then
            device:updateProperty("batteryLevel", battery)
        end
    end
    
    -- Calibration
    if context.calibrate ~= nil then
        device:updateProperty("calibrated", context.calibrate)
    end
end

-- Apply Bot status from webhook
function QuickApp:applyWebhookBotStatus(device, context)
    -- power: "on" or "off"
    if context.power ~= nil then
        local isOn = context.power == "on"
        device:updateProperty("value", isOn)
        self:debug("Updated bot state: " .. tostring(isOn))
    end
    
    -- Battery
    if context.battery ~= nil then
        local battery = tonumber(context.battery)
        if battery then
            device:updateProperty("batteryLevel", battery)
        end
    end
end

-- ============================================
-- UI Handlers for Webhook
-- ============================================

-- UI: Setup webhook button
function QuickApp:btnSetupWebhook()
    local url = self:getVariable("webhookUrl")
    if url and url ~= "" then
        self:setupWebhook(url)
    else
        self:warning("Set 'webhookUrl' variable in QuickApp settings first")
        self:updateView("label_status", "text", "Status: Set webhookUrl variable")
    end
end

-- UI: Query webhook button  
function QuickApp:btnQueryWebhook()
    self:queryWebhook()
end

-- UI: Delete webhook button
function QuickApp:btnDeleteWebhook()
    self:deleteWebhook()
end