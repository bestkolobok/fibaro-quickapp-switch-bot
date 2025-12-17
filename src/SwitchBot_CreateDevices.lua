-- ============================================
-- Child Device Classes
-- ============================================

-- Curtain device class (works for Curtain and Curtain3)
class 'CurtainDevice' (QuickAppChild)

function CurtainDevice:__init(device)
    QuickAppChild.__init(self, device)
    self.switchBotId = self:getVariable('switchBotId')
    self.deviceType = self:getVariable('deviceType') or 'Curtain'
end

function CurtainDevice:open()
    self:debug("Opening curtain...")
    self:updateProperty("value", 100)
    self.parent:sendDeviceCommand(self.switchBotId, "turnOn", "default")
    self.parent:blockDeviceAndSchedulePoll(self.switchBotId)
end

function CurtainDevice:close()
    self:debug("Closing curtain...")
    self:updateProperty("value", 0)
    self.parent:sendDeviceCommand(self.switchBotId, "turnOff", "default")
    self.parent:blockDeviceAndSchedulePoll(self.switchBotId)
end

function CurtainDevice:stop()
    self:debug("Stopping curtain...")
    -- SwitchBot doesn't have native pause, so we get current position and set it
    self.parent:getDeviceStatus(self.switchBotId, function(status)
        if status and status.slidePosition then
            local position = tonumber(status.slidePosition)
            self.parent:sendDeviceCommand(self.switchBotId, "setPosition", "0,ff," .. tostring(position))
        end
    end)
end

-- Value: 0-100 (Fibaro convention: 0=closed, 100=open)
function CurtainDevice:setValue(value)
    self:debug("Setting curtain position to: " .. tostring(value))
    -- SwitchBot uses inverted scale: 0=open, 100=closed
    local switchBotPosition = 100 - value
    self:updateProperty("value", value)
    self.parent:sendDeviceCommand(self.switchBotId, "setPosition", "0,ff," .. tostring(switchBotPosition))
    self.parent:blockDeviceAndSchedulePoll(self.switchBotId)
end

-- Alias for compatibility
function CurtainDevice:setPosition(value)
    self:setValue(value)
end


-- Bot device class
class 'BotDevice' (QuickAppChild)

function BotDevice:__init(device)
    QuickAppChild.__init(self, device)
    self.switchBotId = self:getVariable('switchBotId')
    self.deviceType = self:getVariable('deviceType') or 'Bot'
end

function BotDevice:turnOn()
    self:debug("Turning Bot ON...")
    self:updateProperty("value", true)
    self.parent:sendDeviceCommand(self.switchBotId, "turnOn", "default")
    self.parent:blockDeviceAndSchedulePoll(self.switchBotId)
end

function BotDevice:turnOff()
    self:debug("Turning Bot OFF...")
    self:updateProperty("value", false)
    self.parent:sendDeviceCommand(self.switchBotId, "turnOff", "default")
    self.parent:blockDeviceAndSchedulePoll(self.switchBotId)
end

function BotDevice:press()
    self:debug("Pressing Bot...")
    self.parent:sendDeviceCommand(self.switchBotId, "press", "default")
    self.parent:blockDeviceAndSchedulePoll(self.switchBotId)
end

-- Toggle state
function BotDevice:toggle()
    local currentValue = self.properties.value
    if currentValue then
        self:turnOff()
    else
        self:turnOn()
    end
end


-- ============================================
-- Device Creation
-- ============================================

-- Device type configuration
local DEVICE_CONFIG = {
    ["Curtain"] = {
        fibaroType = "com.fibaro.rollerShutter",
        className = "CurtainDevice",
        interfaces = {"battery"},
        properties = {
            value = 0
        }
    },
    ["Curtain3"] = {
        fibaroType = "com.fibaro.rollerShutter",
        className = "CurtainDevice",
        interfaces = {"battery"},
        properties = {
            value = 0
        }
    },
    ["Bot"] = {
        fibaroType = "com.fibaro.binarySwitch",
        className = "BotDevice",
        interfaces = {"battery"},
        properties = {
            value = false
        }
    }
}

-- Check if device is already added
function QuickApp:isDeviceAlreadyAdded(switchBotId)
    for _, device in pairs(self.childDevices) do
        if device.switchBotId == switchBotId then
            return true
        end
    end
    return false
end

-- Add new device
function QuickApp:addNewDevice(deviceInfo)
    local switchBotId = deviceInfo.deviceId
    local deviceType = deviceInfo.deviceType
    local deviceName = deviceInfo.deviceName
    
    -- Check if already exists
    if self:isDeviceAlreadyAdded(switchBotId) then
        self:debug("Device already added: " .. deviceName .. " (" .. switchBotId .. ")")
        return nil
    end
    
    -- Get device configuration
    local config = DEVICE_CONFIG[deviceType]
    if not config then
        self:warning("Unsupported device type: " .. deviceType)
        return nil
    end
    
    self:debug("Adding device: " .. deviceName .. " (type: " .. deviceType .. ")")
    
    -- Prepare variables for child device (className is added separately in createChild)
    local variables = {
        switchBotId = switchBotId,
        deviceType = deviceType
    }
    
    -- Create child device
    local child = self:createChild(
        deviceName,
        config.fibaroType,
        config.className,
        variables,
        config.properties,
        config.interfaces
    )
    
    if child then
        self:debug("✓ Device added successfully: " .. deviceName .. " [ID: " .. child.id .. "]")
        
        -- Get initial state
        self:updateDeviceState(switchBotId)
        
        return child
    else
        self:warning("✗ Failed to create device: " .. deviceName)
        return nil
    end
end

-- Create child device helper
function QuickApp:createChild(name, fibaroType, className, variables, properties, interfaces)
    properties = properties or {}
    interfaces = interfaces or {}
    
    -- Prepare quickAppVariables
    properties.quickAppVariables = properties.quickAppVariables or {}
    
    -- Add className first (important for loadChildren)
    table.insert(properties.quickAppVariables, 1, {name = "className", value = className})
    
    -- Add other variables
    for varName, varValue in pairs(variables or {}) do
        table.insert(properties.quickAppVariables, {name = varName, value = varValue})
    end
    
    -- Create child device
    local child = self:createChildDevice({
        name = name,
        type = fibaroType,
        initialProperties = properties,
        initialInterfaces = interfaces
    }, _G[className])
    
    if child then
        child.switchBotId = variables.switchBotId
    end
    
    return child
end