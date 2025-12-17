-- ============================================
-- Smart Polling & State Synchronization
-- ============================================

--[[
SwitchBot API Limit: 10,000 requests/day (~7/min)

Smart Polling Strategy:
- IDLE mode: 5 min interval (normal state)  
- SLEEP mode: 15 min interval (night)
- After command: block updates for 30 sec, then single poll
- Rate limit protection with daily counter
]]--

-- Polling modes
local POLL_MODE = {
    IDLE = "idle",       -- Normal state
    SLEEP = "sleep"      -- Low activity / night
}

-- Intervals in seconds
local POLL_INTERVALS = {
    [POLL_MODE.IDLE] = 300,      -- 5 minutes
    [POLL_MODE.SLEEP] = 900      -- 15 minutes
}

-- Block duration after command (seconds)
local COMMAND_BLOCK_DURATION = 30

-- Daily request limit (with safety margin)
local DAILY_REQUEST_LIMIT = 9500  -- Keep 500 for manual actions

-- ============================================
-- Polling State Management
-- ============================================

function QuickApp:initPolling()
    self.polling = {
        active = false,
        mode = POLL_MODE.IDLE,
        timer = nil,
        
        -- Rate limiting
        requestCount = 0,
        requestCountDate = os.date("%Y-%m-%d"),
        
        -- Per-device update blocking (deviceId -> unblock timestamp)
        deviceBlockedUntil = {}
    }
    
    -- Load saved request count
    local savedCount = tonumber(self:getVariable("dailyRequestCount")) or 0
    local savedDate = self:getVariable("dailyRequestDate") or ""
    
    if savedDate == os.date("%Y-%m-%d") then
        self.polling.requestCount = savedCount
    end
end

-- Check and update rate limit
function QuickApp:checkRateLimit()
    local today = os.date("%Y-%m-%d")
    
    -- Reset counter on new day
    if self.polling.requestCountDate ~= today then
        self.polling.requestCount = 0
        self.polling.requestCountDate = today
        self:setVariable("dailyRequestDate", today)
    end
    
    -- Check if limit exceeded
    if self.polling.requestCount >= DAILY_REQUEST_LIMIT then
        self:warning("Daily API limit reached! Polling paused until tomorrow.")
        return false
    end
    
    return true
end

-- Increment request counter
function QuickApp:incrementRequestCount()
    self.polling.requestCount = self.polling.requestCount + 1
    
    -- Save every 10 requests
    if self.polling.requestCount % 10 == 0 then
        self:setVariable("dailyRequestCount", tostring(self.polling.requestCount))
    end
end

-- Get current polling mode
function QuickApp:getPollingMode()
    -- Check time for sleep mode (23:00 - 07:00)
    local hour = tonumber(os.date("%H"))
    if hour >= 23 or hour < 7 then
        return POLL_MODE.SLEEP
    end
    
    return POLL_MODE.IDLE
end

-- Check if device updates are blocked
function QuickApp:isDeviceBlocked(switchBotId)
    if not self.polling then return false end
    
    local blockedUntil = self.polling.deviceBlockedUntil[switchBotId]
    if blockedUntil and os.time() < blockedUntil then
        return true
    end
    
    return false
end

-- Block device updates and schedule delayed poll (called after sending command)
function QuickApp:blockDeviceAndSchedulePoll(switchBotId)
    if not self.polling then
        self:initPolling()
    end
    
    local now = os.time()
    self.polling.deviceBlockedUntil[switchBotId] = now + COMMAND_BLOCK_DURATION
    
    self:debug("Device " .. switchBotId .. " updates blocked for " .. COMMAND_BLOCK_DURATION .. " sec")
    
    -- Schedule single poll after block expires
    setTimeout(function()
        self:debug("Block expired, polling device: " .. switchBotId)
        self.polling.deviceBlockedUntil[switchBotId] = nil
        self:updateDeviceState(switchBotId)
    end, COMMAND_BLOCK_DURATION * 1000)
end

-- ============================================
-- Polling Control
-- ============================================

function QuickApp:startPolling()
    if not self.polling then
        self:initPolling()
    end
    
    if self.polling.active then
        self:debug("Polling already active")
        return
    end
    
    self.polling.active = true
    self:debug("Smart polling started")
    
    -- Initial poll
    self:pollAllDevices()
    
    -- Schedule next
    self:scheduleNextPoll()
end

function QuickApp:stopPolling()
    if not self.polling then return end
    
    self.polling.active = false
    
    if self.polling.timer then
        clearTimeout(self.polling.timer)
        self.polling.timer = nil
    end
    
    self:debug("Polling stopped")
end

function QuickApp:scheduleNextPoll()
    if not self.polling or not self.polling.active then return end
    
    -- Clear existing timer
    if self.polling.timer then
        clearTimeout(self.polling.timer)
    end
    
    local mode = self:getPollingMode()
    local interval = POLL_INTERVALS[mode]
    
    self.polling.mode = mode
    
    self.polling.timer = setTimeout(function()
        if self.polling.active then
            self:pollAllDevices()
            self:scheduleNextPoll()
        end
    end, interval * 1000)
    
    self:trace("Next poll in " .. math.floor(interval / 60) .. " min (" .. mode .. " mode)")
end

-- ============================================
-- Device Polling
-- ============================================

function QuickApp:pollAllDevices()
    -- Check rate limit
    if not self:checkRateLimit() then
        return
    end
    
    local devicesToPoll = {}
    
    -- Collect devices to poll (skip blocked ones)
    for id, device in pairs(self.childDevices) do
        if device.switchBotId then
            if not self:isDeviceBlocked(device.switchBotId) then
                table.insert(devicesToPoll, device.switchBotId)
            else
                self:trace("Skipping blocked device: " .. device.switchBotId)
            end
        end
    end
    
    if #devicesToPoll == 0 then
        return
    end
    
    local mode = self:getPollingMode()
    self:trace("Polling " .. #devicesToPoll .. " device(s) [" .. mode .. " mode, " .. self.polling.requestCount .. " requests today]")
    
    -- Poll with small delays between requests
    for i, switchBotId in ipairs(devicesToPoll) do
        setTimeout(function()
            self:updateDeviceState(switchBotId)
        end, (i - 1) * 200)  -- 200ms between requests
    end
end

-- Update single device state
function QuickApp:updateDeviceState(switchBotId)
    local device = self:getDeviceBySwitchBotId(switchBotId)
    if not device then return end
    
    -- Double-check device is not blocked
    if self:isDeviceBlocked(switchBotId) then
        self:trace("Device " .. switchBotId .. " is blocked, skipping update")
        return
    end
    
    self:getDeviceStatus(switchBotId, function(status)
        if status then
            self:applyDeviceStatus(device, status)
        end
    end)
    
    -- Count the request
    self:incrementRequestCount()
end

-- Apply status to device based on device type
function QuickApp:applyDeviceStatus(device, status)
    local deviceType = device:getVariable('deviceType') or 'Unknown'
    
    -- Update battery level (common for all battery-powered devices)
    if status.battery ~= nil then
        local batteryLevel = tonumber(status.battery)
        if batteryLevel then
            device:updateProperty("batteryLevel", batteryLevel)
        end
    end
    
    -- Device-specific status handling
    if deviceType == "Curtain" or deviceType == "Curtain3" then
        self:applyCurtainStatus(device, status)
    elseif deviceType == "Bot" then
        self:applyBotStatus(device, status)
    else
        self:debug("Unknown device type for status update: " .. deviceType)
    end
end

-- Apply Curtain status
function QuickApp:applyCurtainStatus(device, status)
    -- slidePosition: 0 = fully open, 100 = fully closed (SwitchBot convention)
    -- Fibaro convention: 0 = closed, 100 = open
    if status.slidePosition ~= nil then
        local switchBotPosition = tonumber(status.slidePosition)
        if switchBotPosition then
            local fibaroValue = 100 - switchBotPosition
            device:updateProperty("value", fibaroValue)
        end
    end
    
    -- Moving status
    if status.moving ~= nil then
        device:updateProperty("moving", status.moving)
    end
    
    -- Calibration status
    if status.calibrate ~= nil then
        local isCalibrated = status.calibrate == true
        device:updateProperty("calibrated", isCalibrated)
    end
end

-- Apply Bot status
function QuickApp:applyBotStatus(device, status)
    -- power: "on" or "off"
    if status.power ~= nil then
        local isOn = status.power == "on"
        device:updateProperty("value", isOn)
    end
end

-- ============================================
-- Manual Controls
-- ============================================

-- Force immediate poll of all devices (ignores blocks)
function QuickApp:refreshDevices()
    self:debug("Manual refresh triggered")
    
    -- Clear all blocks
    if self.polling then
        self.polling.deviceBlockedUntil = {}
    end
    
    self:pollAllDevices()
end

-- Get polling stats
function QuickApp:getPollingStats()
    if not self.polling then
        return "Polling not initialized"
    end
    
    local mode = self:getPollingMode()
    local interval = POLL_INTERVALS[mode]
    
    return string.format(
        "Mode: %s, Interval: %ds, Requests today: %d/%d",
        mode,
        interval,
        self.polling.requestCount,
        DAILY_REQUEST_LIMIT
    )
end

-- UI: Show polling stats
function QuickApp:btnPollingStats()
    local stats = self:getPollingStats()
    self:debug(stats)
    self:updateView("label_status", "text", stats)
end