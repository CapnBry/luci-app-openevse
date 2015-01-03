#!/usr/bin/lua

require "os"
require "nixio"
require "bit"

local SERIAL_DEVICE = "/dev/ttyUSB0"

local serialfd

local function segSplit(line)
  local retVal = {}
  local fieldstart = 1
  while true do
    local nexti = line:find(' ', fieldstart)
    if nexti then
      -- Don't add the segment name
      if fieldstart > 1 then
        retVal[#retVal+1] = line:sub(fieldstart, nexti - 1)
      end
      fieldstart = nexti + 1
    else
      if fieldstart > 1 then
        retVal[#retVal+1] = line:sub(fieldstart)
      end
      break
    end
  end

  if #retVal > 0 then
    return unpack(retVal)
  end
end

local function evseStateDesc(state)
  local STATE = {
    [0x1] = "EV not connected", [0x2] = "EV connected",
    [0x3] = "Charging", [0x4] = "Vent required", [0x5] = "Diode check failed",
    [0x6] = "GFCI fault", [0x7] = "Bad ground", [0x8] = "Stuck relay",
    [0x9] = "GFCI check failed", [0xfe] = "Waiting timer",
    [0xff] = "Disabled"
  }
  return STATE[tonumber(state)] or "Unknown"
end

local function evseChecksum(cmd)
  local csum = 0
  for i = 1, #cmd do
    csum = csum + cmd:byte(i)
  end
  return csum % 256
end

local function evseCmd(cmd)
  cmd = "$" .. cmd
  cmd = ("%s*%02X\r"):format(cmd, evseChecksum(cmd))
  serialfd:write(cmd)
  nixio.nanosleep(0, 10000000)
  local resp = serialfd:read(1024):gsub("\r", "")
  return segSplit(resp)
end

if os.execute("/usr/bin/stty -F " .. SERIAL_DEVICE .. " raw -echo 115200") ~= 0 then
    print("Can't set serial baud")
    return
end

serialfd = nixio.open(SERIAL_DEVICE, nixio.open_flags("rdwr"))
if not serialfd then
  print("Can't open serial device")
  return
end
serialfd:setblocking(true)
serialfd:write("\r")

if arg and #arg > 0 then
  print(evseCmd(table.concat(arg, ' ')))
  return
end

local config = {}
config['evse_ver'], config['rapi_ver'] = evseCmd("GV")
config['current_cur'] = evseCmd("GG")
config['current_cap_min'], config['current_cap_max'] = evseCmd("GC")
config['current_cap_cur'], config['flags'] = evseCmd("GE")
config['current_scale'], config['current_offset'] = evseCmd("GA")
config['state'], config['charge_time_elapsed'] = evseCmd("GS")
config['state_desc'] = evseStateDesc(config['state'])

local y,m,d,h,n,s = evseCmd("GT")
if not (y == "165" or m == "165" or d == "165" or h == "165" or nn == "165") then
  config['rtc'] = ("20%02d-%02d-%02d %02d:%02d:%02d"):format(y,m,d,h,n,s)
end

local function doSet(self, value, key)
  local old = self:cfgvalue()
  if old ~= value then
    evseCmd(key .. " " .. value)
    config[self.option] = value
  end
end      

local function evseFlagChanged(self, flag, value)
  if not self.evsecmd then return end

  if self.evseinvert then value = not value end
  local valstr = value and "0" or "1"
  evseCmd(self.evsecmd .. " " .. valstr)
end
local function evseFlagGet(self)
  local flag = tonumber('0x' .. self.option:sub(6))
  local val = bit.check(tonumber('0x' .. config['flags']), flag)
  if self.invert then
    val = not val
  end
  return val and "1" or "0"
end
local function evseFlagSet(self, section, value)
  local flag = tonumber('0x' .. self.option:sub(6))
  local flags = tonumber('0x' .. config['flags'])
  value = value == "1" and true or false
  if self.invert then value = not value end
  if value then
    flags = bit.set(flags, flag)
  else
    flags = bit.unset(flags, flag)
  end
  local newflags = ("%04x"):format(flags)
  if newflags ~= config['flags'] then
    evseFlagChanged(self, flag, value)
    config['flags'] = newflags
  end
end
local function evseServiceLevelGet(self)
  local manual = bit.check(tonumber('0x' .. config['flags']), 0x0020)
  local l2 = bit.check(tonumber('0x' .. config['flags']), 0x0001)
  if manual and l2 then
    return "2"
  elseif manual then
    return "1"
  else
    return "A"
  end
end
local function evseServiceLevelSet(self, section, value)
  local flags = tonumber('0x' .. config['flags'])
  if value == "1" then
    flags = bit.unset(bit.set(flags, 0x0020), 0x0001)
  elseif value == "2" then
    flags = bit.set(bit.set(flags, 0x0020), 0x0001)
  else -- "A"
    flags = bit.unset(flags, 0x0020)
  end
  config['flags'] = ("%04x"):format(flags)
  evseCmd("SL " .. value)
end

local m = SimpleForm("openevse", "OpenEVSE Status")
m.data = config

s = m:section(SimpleSection, "System")
s.template = "admin_status/openevse"
s:option(DummyValue, "evse_ver")
s:option(DummyValue, "rapi_ver")
s:option(DummyValue, "current_cur")
s:option(DummyValue, "current_cap_cur")
s:option(DummyValue, "current_cap_min")
s:option(DummyValue, "current_cap_max")
s:option(DummyValue, "flags")
s:option(DummyValue, "state")
s:option(DummyValue, "state_desc")
s:option(DummyValue, "charge_time_elapsed")
s:option(DummyValue, "rtc")
s:option(DummyValue, "current_scale", "Current scale")
s:option(DummyValue, "current_offset", "Current offset")

local o

--
-- Safety flags
--
s = m:section(SimpleSection, "Safety Checks")
o = s:option(Flag, "flag_0002", "Diode check")
  o.cfgvalue = evseFlagGet
  o.write = evseFlagSet
  o.evsecmd = "SD"
  o.rmempty = false
  o.invert = true
o = s:option(Flag, "flag_0004", "Vent check")
  o.cfgvalue = evseFlagGet
  o.write = evseFlagSet
  o.evsecmd = "SV"
  o.rmempty = false
  o.invert = true
o = s:option(Flag, "flag_0008", "Ground check")
  o.cfgvalue = evseFlagGet
  o.write = evseFlagSet
  o.evsecmd = "SG"
  o.rmempty = false
  o.invert = true
o = s:option(Flag, "flag_0010", "Stuck relay check")
  o.cfgvalue = evseFlagGet
  o.write = evseFlagSet
  o.evsecmd = "SR"
  o.rmempty = false
  o.invert = true
o = s:option(Flag, "flag_0200", "GFCI check")
  o.cfgvalue = evseFlagGet
  o.write = evseFlagSet
  o.evsecmd = "SS"
  o.rmempty = false
  o.invert = true

--
-- Options
--
s = m:section(SimpleSection, "Options")
o = s:option(ListValue, "flag_0001", "Service Level")
  o.cfgvalue = evseServiceLevelGet
  o.write = evseServiceLevelSet
  o:value("A", "Auto")
  o:value("1", "Level 1 (L1)")
  o:value("2", "Level 2 (L2)")
  o.rmempty = false
o = s:option(Value, "current_cap_cur", "Current limit")
  o.datatype = "uinteger"
  o.validate = function (self, value, section)
    if tonumber(value) < tonumber(config.current_cap_min) or 
      tonumber(value) > tonumber(config.current_cap_max) then
      return nil, ("%s Must be between %d and %d amps"):format(value, config.current_cap_min, config.current_cap_max)
    end
    return value
  end
  o.write = function (self, section, value) doSet(self, value, "SC") end

o = s:option(ListValue, "flag_0100", "LCD type")
  o.cfgvalue = evseFlagGet
  o.write = evseFlagSet
  o.evsecmd = "S0"
  o:value("0", "Color")
  o:value("1", "Monochrome")
  o.rmempty = false
o = s:option(Flag, "flag_0040", "Auto start")
  o.cfgvalue = evseFlagGet
  o.write = evseFlagSet
  o.rmempty = false
  o.invert = true

return m

