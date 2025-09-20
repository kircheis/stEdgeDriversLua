-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

local function added_handler(self, device)
  device:emit_event(capabilities.doorControl.supportedDoorControlCommands({"open", "close", "pause"}, { visibility = { displayed = false }}))
end

local driver_template = {
  supported_capabilities = {
    capabilities.button,
    capabilities.switch,
    capabilities.doorControl,
    capabilities.powerMeter,
    capabilities.firmwareUpdate,
    capabilities.contactSensor,
  },
  sub_drivers = {    
    require("tuya-zb-gdo")
  },
  lifecycle_handlers = {
    added = added_handler
  },
  health_check = false,
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
local zigbee_garage_door_opener = ZigbeeDriver(driver_template)
zigbee_garage_door_opener:run()