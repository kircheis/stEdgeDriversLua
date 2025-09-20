-- Copyright 2023 SmartThings
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

local zcl_clusters = require "st.zigbee.zcl.clusters"
local level = zcl_clusters.Level
local capabilities = require "st.capabilities"

local device_lib = require "st.device"
local utils = require "st.utils"
local tuya_utils = require "zigbee-garage-door-opener.src.tuya_utils"
local garage_door_opener_preset_defaults = require "st.zigbee.defaults.garageDoorOpenerPreset_defaults"

local GarageDoorOpener = zcl_clusters.GarageDoorOpener
local ep_array = {1,2,3,4,5,6}
local packet_id = 0

-- Tuya zigbee garage door operator
local TUYA_ZIGBEE_GARAGE_DOOR_FINGERPRINTS = {
  { mfr = "_TZE608_xkr8gep3", model = "TS0603"},
}

local MOVE_LESS_THAN_THRESHOLD = "_sameLevelEvent"
local FINAL_STATE_POLL_TIMER = "_finalStatePollTimer"

local GDO_CONFIG_PARAMS = {
  closeWaitPeriodSec = 1,
  activationTimeMS = 2,
  doorOpenTimeoutSec = 3,
  doorCloseTimeoutSec = 4,
  shakeSensitivity = 5,
  applicationLevelRetries = 6
}

--- Determine whether the passed device is a garage door operator
local function is_tuya_zigbee_garage_door_opener(opts, driver, device)
  for _, fingerprint in ipairs(TUYA_ZIGBEE_GARAGE_DOOR_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local function component_to_endpoint(device, component_id)
  if (CONTACTSENSOR_ENDPOINT_NAME == component_id)  then
    --contactSensor is 2
    return CONTACTSENSOR_ENDPOINT_NUMBER
  end
  -- main endpoint is garage door
  return GDO_ENDPOINT_NUMBER
end

local function endpoint_to_component(device, ep)
  if ( CONTACTSENSOR_ENDPOINT_NUMBER == ep ) then
    return CONTACTSENSOR_ENDPOINT_NAME
  end
  return GDO_ENDPOINT_NAME
end

--- Handle Device Instantiated Event
local function device_instantiated(driver, device)
  log.info_with({hub_logs=true}, "device init")
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, function(d)
    device:send(BarrierOperator:Get({}))
  end)
  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY*2, function(d)
    device:send(SensorMultilevel:Get({}))
  end)
  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY*3, function(d)
    device:send(Configuration:BulkGetV2({parameter_offset = 1, number_of_parameters = 6}) )
  end)
end

--- Handle Device Added Event
---
local function device_added(driver, device)
  device:send(BarrierOperator:Get({}))
  -- Reset contact sensor fields
  device:emit_event_for_endpoint(CONTACTSENSOR_ENDPOINT_NUMBER,
    capabilities.tamperAlert.tamper.clear())
  device:emit_event_for_endpoint(CONTACTSENSOR_ENDPOINT_NUMBER,
    capabilities.contactSensor.contact.closed())
  -- Init barrier door state
  device:emit_event_for_endpoint(GDO_ENDPOINT_NUMBER,
    capabilities.doorControl.door.closed())
end

--- Configuration Report Handler
---
local function configure_device_with_updated_config(driver, device)
  local updated_params = {}

  for param, value in pairs(device.preferences) do
    updated_params[GDO_CONFIG_PARAMS[param]] = {parameter = value}
  end

  device:send(Configuration:BulkSetV2({
                                        parameter_offset = 1,
                                        size = 2,
                                        handshake = false,
                                        default = false,
                                        parameters = updated_params
                                      }))
end

--- Notification Report Handler
---
local function notification_report_handler(driver, device, cmd)
  local notificationType = cmd.args.notification_type
  local notificationEvent = cmd.args.event
  local barrier_event = nil
  local contact_event = nil
  if ( 0 == notificationEvent ) then
    -- Clear Notifications
    -- First byte of the parameters is the notification being cleared
    -- so reuse notificationEvent variable as the event being cleared
    if (0 ~= string.len(cmd.args.event_parameter)) then
      notificationEvent = string.byte(cmd.args.event_parameter)
    end
    if (notificationType == Notification.notification_type.SYSTEM) then
      if (notificationEvent == Notification.event.system.TAMPERING_PRODUCT_COVER_REMOVED) then
        contact_event = capabilities.tamperAlert.tamper.clear()
      end
    elseif (notificationType == Notification.notification_type.ACCESS_CONTROL) then
      if (notificationEvent ==
              Notification.event.access_control.BARRIER_SENSOR_NOT_DETECTED_SUPERVISORY_ERROR) then
        barrier_event = capabilities.doorControl.door.closed()
      end
    end
  else
    -- Handle Notification events
    if (notificationType == Notification.notification_type.SYSTEM) then
      if (notificationEvent == Notification.event.system.TAMPERING_PRODUCT_COVER_REMOVED) then
        contact_event = capabilities.tamperAlert.tamper.detected()
      end
    elseif (notificationType == Notification.notification_type.ACCESS_CONTROL) then
      if (notificationEvent == Notification.event.access_control.WINDOW_DOOR_IS_OPEN) then
        barrier_event = capabilities.doorControl.door.open()
        contact_event = capabilities.contactSensor.contact.open()
      elseif (notificationEvent == Notification.event.access_control.WINDOW_DOOR_IS_CLOSED) then
        barrier_event = capabilities.doorControl.door.closed()
        contact_event = capabilities.contactSensor.contact.closed()
      elseif (
      (notificationEvent ==
        Notification.event.access_control.BARRIER_MOTOR_HAS_EXCEEDED_MANUFACTURERS_OPERATIONAL_TIME_LIMIT) or
      (notificationEvent ==
        Notification.event.access_control.BARRIER_UNABLE_TO_PERFORM_REQUESTED_OPERATION_DUE_TO_UL_REQUIREMENTS) or
      (notificationEvent ==
        Notification.event.access_control.BARRIER_FAILED_TO_PERFORM_REQUESTED_OPERATION_DEVICE_MALFUNCTION))
      then
        barrier_event = capabilities.doorControl.door.unknown()
      elseif (notificationEvent ==
              Notification.event.access_control.BARRIER_SENSOR_NOT_DETECTED_SUPERVISORY_ERROR) then
        barrier_event = capabilities.doorControl.door.closed()
      end
    end
  end

  -- If we are going to emit an event to the device, from a notification, do it.
  if (barrier_event ~= nil) then
    device:emit_event_for_endpoint(GDO_ENDPOINT_NUMBER, barrier_event)
  end

  if (contact_event ~= nil) then
    device:emit_event_for_endpoint(CONTACTSENSOR_ENDPOINT_NUMBER, contact_event)
  end

end

--- Handle Door control
local set_doorControl_factory = function(doorControl_attribute)
  return function(driver, device, cmd)
      device:send(BarrierOperator:Set({ target_value = doorControl_attribute }))
      device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, function(d)
        device:send(BarrierOperator:Get({}))end)
  end
end

--- Multilevel Sensor Report Handler
---
local function sensor_multilevel_report_handler(driver, device, cmd)
  -- Handle Temperature Report
  if (SensorMultilevel.sensor_type.TEMPERATURE == cmd.args.sensor_type) then
    local scale = 'C'
    if (SensorMultilevel.scale.temperature.FAHRENHEIT == cmd.args.scale) then
      scale = 'F'
    end

    local event = capabilities.temperatureMeasurement.temperature(
                                          {value = cmd.args.sensor_value, unit = scale})
    device:emit_event(event)
  end

end

local function do_refresh(driver, device)
  -- State of garage door
  device:send_to_component(BarrierOperator:Get({}))

  -- State of tilt sensor
  device:send_to_component(Notification:Get({
                                        v1_alarm_type = 0,
                                        notification_type = Notification.notification_type.SYSTEM,
                                        event = 0}))
  device:send_to_component(Notification:Get({
                                        v1_alarm_type = 0,
                                        notification_type = Notification.notification_type.ACCESS_CONTROL,
                                        event = 0}))

  -- State of Temperature Sensor
  device:send_to_component(SensorMultilevel:Get({}))
end

local ecolink_garage_door_operator = {
  NAME = "Ecolink Garage Door Controller",
  capability_handlers = {
    [capabilities.doorControl.ID] = {
      [capabilities.doorControl.commands.open.NAME] = set_doorControl_factory(BarrierOperator.state.OPEN),
      [capabilities.doorControl.commands.close.NAME] = set_doorControl_factory(BarrierOperator.state.CLOSED)
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  lifecycle_handlers = {
    init = device_instantiated,
    added = device_added,
    doConfigure = configure_device_with_updated_config,
    infoChanged = configure_device_with_updated_config
  },
  can_handle = can_handle_ecolink_garage_door
}


local function create_child_devices(driver, device)
  for ep in ipairs(ep_array) do
    if ep ~= device.fingerprinted_endpoint_id then
      if find_child(device, ep) == nil then
        local metadata = {
          type = "EDGE_CHILD",
          parent_assigned_child_key = string.format("%02X", ep),
          label = device.label..' '..ep,
          profile = "basic-switch",
          parent_device_id = device.id
        }
        driver:try_create_device(metadata)
      end
    end
  end
end

local function tuya_cluster_handler(driver, device, zb_rx)
  local raw = zb_rx.body.zcl_body.body_bytes
  local dp = string.byte(raw:sub(3,3))
  local dp_data_len = string.unpack(">I2", raw:sub(5,6))
  local dp_data = string.unpack(">I"..dp_data_len, raw:sub(7))
  if dp == device.fingerprinted_endpoint_id or find_child(device, dp) ~= nil then
    device:emit_event_for_endpoint(dp, capabilities.switch.switch(dp_data == 0 and "off" or "on"))
  end
end

local function switch_on_handler(driver, device)
  local dp = (device.network_type == device_lib.NETWORK_TYPE_CHILD) and string.char(device:get_endpoint()) or "\x01"
  tuya_utils.send_tuya_command(device, dp, tuya_utils.DP_TYPE_BOOL, "\x01", packet_id)
  packet_id = (packet_id + 1) % 65536
end

local function switch_off_handler(driver, device)
  local dp = (device.network_type == device_lib.NETWORK_TYPE_CHILD) and string.char(device:get_endpoint()) or "\x01"
  tuya_utils.send_tuya_command(device, dp, tuya_utils.DP_TYPE_BOOL, "\x00", packet_id)
  packet_id = (packet_id + 1) % 65536
end

local function device_added(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    create_child_devices(driver, device)
  end
end

local function device_init(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then return end
  device:set_find_child(find_child)
end

local tuya_multi_switch_driver = {
  NAME = "tuya multi switch",
  supported_capabilities = {
    capabilities.switch
  },
  zigbee_handlers = {
    cluster = {
      [tuya_utils.TUYA_PRIVATE_CLUSTER] = {
        [tuya_utils.TUYA_PRIVATE_CMD_RESPONSE] = tuya_cluster_handler,
        [tuya_utils.TUYA_PRIVATE_CMD_REPORT] = tuya_cluster_handler,
      }
    },
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler,
    },
  },
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
  },
  can_handle = is_tuya_zigbee_garage_door_opener
}

return tuya_multi_switch_driver


