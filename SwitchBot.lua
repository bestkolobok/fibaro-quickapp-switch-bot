--%%name:SwitchBot
--%%type:com.fibaro.genericDevice
--%%var:profile_token="********"
--%%var:profile_secret="********"
--%%var:dailyRequestCount="10"
--%%file:./SwitchBot_Auth.lua,Auth
--%%file:./SwitchBot_SearchDevices.lua,SearchDevices
--%%file:./SwitchBot_CreateDevices.lua,CreateDevices
--%%file:./SwitchBot_Pooling.lua,Pooling
--%%file:./SwitchBot_Http.lua,Http
--%%file:./SwitchBot_Webhook.lua,Webhook
--%%u:{label="label_status",text="Status: Ready"}
--%%u:{{button="button_test",text="Test Connection",visible=true,onLongPressDown="testConnection",onLongPressReleased="",onReleased="testConnection"},{button="button_search",text="Search devices",visible=true,onLongPressDown="searchDevices",onLongPressReleased="",onReleased="searchDevices"}}
--%%u:{multi="select_devices",text="Found supported devices:",visible=true,onToggled="selectDevices",options={}}
--%%u:{button="button_add",text="Add Selected (0)",visible=true,onLongPressDown="addSelectedDevices",onLongPressReleased="",onReleased="addSelectedDevices"}
--%%u:{label="label_ID_9",text="________________________________________"}
--%%u:{label="label_ID_8",text="Manually forcing pooling"}
--%%u:{button="button_refresh",text="Refresh All",visible=true,onLongPressDown="refreshDevices",onLongPressReleased="",onReleased="refreshDevices"}
--%%u:{label="label_ID_7",text="________________________________________"}
--%%u:{label="label_ID_6",text="Webhooks setup (experimental)"}
--%%u:{{button="button_wh_setup",text="Setup",visible=true,onLongPressDown="btnSetupWebhook",onLongPressReleased="",onReleased="btnSetupWebhook"},{button="button_wh_query",text="Query",visible=true,onLongPressDown="btnQueryWebhook",onLongPressReleased="",onReleased="btnQueryWebhook"},{button="button_wh_delete",text="Delete",visible=true,onLongPressDown="btnDeleteWebhook",onLongPressReleased="",onReleased="btnDeleteWebhook"}}

-- SwitchBot QuickApp for Fibaro HC3
-- Supports: Curtain, Curtain3, Bot
-- API: https://github.com/OpenWonderLabs/SwitchBotAPI

--[[
QUICK APP VARIABLES (Parent):
- profile_token [string] {REQUIRED} - API token from SwitchBot app
- profile_secret [string] {REQUIRED} - Secret key from SwitchBot app
- webhookUrl [string] - http://<your-domain>:<port>/api/callAction
- webhookEnabled [string] ("true" | "false")

CHILD DEVICE PROPERTIES:
- Curtain/Curtain3:
  - value [number] (0-100) - current position (0=closed, 100=open)
  - batteryLevel [number] (0-100)
  
- Bot:
  - value [boolean] - current state (on/off)
  - batteryLevel [number] (0-100)
]]--

local API_HOST = "https://api.switch-bot.com"
local API_VERSION = "v1.1"

function QuickApp:onInit()
    self:debug("=== SwitchBot QuickApp Initializing ===")
    
    -- Initialize API URL
    self.apiUrl = API_HOST .. "/" .. API_VERSION .. "/"
    
    -- Found devices during search (temporary)
    self.foundDevices = {}
    
    -- Selected devices from UI selector
    self.selectedDevices = {}
    
    -- Initialize smart polling
    self:initPolling()
    
    -- Check credentials
    local token = self:getVariable("profile_token")
    local secret = self:getVariable("profile_secret")
    
    if not token or token == "" or not secret or secret == "" then
        self:warning("⚠ API credentials not set!")
        self:updateView("label_status", "text", "Status: Credentials missing")
        self:debug("Set profile_token and profile_secret in QuickApp variables")
        return
    end
    
    -- Load existing child devices
    local childCount = self:loadChildren()
    self:debug("Loaded " .. childCount .. " child devices")
    
    -- Print all child devices
    if childCount > 0 then
        self:debug("Child devices:")
        for id, device in pairs(self.childDevices) do
            self:debug("  [" .. id .. "] " .. device.name .. " (type: " .. device.type .. ", switchBotId: " .. tostring(device.switchBotId) .. ")")
        end
        
        -- Check if webhook is enabled, otherwise use polling
        local webhookEnabled = self:getVariable("webhookEnabled")
        if webhookEnabled == "true" then
            self:debug("Webhook mode enabled - polling disabled")
        else
            self:debug("Starting smart polling...")
            self:startPolling()
        end
    end
    
    self:updateView("label_status", "text", "Status: Ready")
end

-- Get child device by SwitchBot ID (simple iteration)
function QuickApp:getDeviceBySwitchBotId(switchBotId)
    for _, device in pairs(self.childDevices) do
        if device.switchBotId == switchBotId then
            return device
        end
    end
    return nil
end

-- Load existing child devices
function QuickApp:loadChildren()
    local cdevs = api.get("/devices?parentId=" .. self.id) or {}
    local count = 0
    
    -- Prevent Fibaro from calling initChildDevices after onInit
    function self:initChildDevices() end
    
    for _, child in ipairs(cdevs) do
        local className = "QuickAppChild"
        local switchBotId = nil
        
        -- Find className and switchBotId from quickAppVariables
        for _, v in ipairs(child.properties.quickAppVariables or {}) do
            if v.name == "className" then
                className = v.value
            elseif v.name == "switchBotId" then
                switchBotId = v.value
            end
        end
        
        -- Create child object with appropriate class
        local childClass = _G[className] or QuickAppChild
        local childObject = childClass(child)
        childObject.switchBotId = switchBotId
        childObject.parent = self
        
        self.childDevices[child.id] = childObject
        count = count + 1
    end
    
    return count
end

-- UI Handler: Select devices from dropdown
function QuickApp:selectDevices(event)
    -- event.values[1] contains array of selected device IDs
    self.selectedDevices = {}
    
    if event.values and event.values[1] then
        for _, deviceId in ipairs(event.values[1]) do
            -- Ignore empty placeholder values
            if deviceId and deviceId ~= "" then
                table.insert(self.selectedDevices, deviceId)
                self:debug("Selected device: " .. tostring(deviceId))
            end
        end
    end
    
    local count = #self.selectedDevices
    self:updateView("button_add", "text", "Add Selected (" .. count .. ")")
end

-- UI Handler: Add selected devices
function QuickApp:addSelectedDevices()
    if #self.selectedDevices == 0 then
        self:debug("No devices selected")
        return
    end
    
    self:debug("Adding " .. #self.selectedDevices .. " devices...")
    
    for _, deviceId in ipairs(self.selectedDevices) do
        local deviceInfo = self.foundDevices[deviceId]
        if deviceInfo then
            self:addNewDevice(deviceInfo)
        else
            self:debug("Device info not found for: " .. deviceId)
        end
    end
    
    -- Clear selection
    self.selectedDevices = {}
    self:updateView("button_add", "text", "Add Selected (0)")
    
    -- Start polling if not already running
    self:startPolling()
end

-- UI Handler: Remove all child devices (for debugging)
function QuickApp:removeAllChildren()
    self:debug("Removing all child devices...")
    
    for id, _ in pairs(self.childDevices) do
        self:removeChildDevice(id)
    end
    
    self:debug("All child devices removed")
end