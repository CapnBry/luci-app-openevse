luci-app-openevse
=================

LuCI scripts for RAPI access to an [OpenEVSE charger](https://github.com/lincomatic/open_evse)

luasrc/controller - Adds "OpenEVSE" to the Admin -> Status webui

luasrc/model - Queries RAPI and builds the configuration table

luasrc/view - A custom view template to add the graph and some conditional formatting

Once installed there will also be an "openevse" executable that can be used to send commands. Examples:

~~~
# Get charging current
openevse GG
# Set the RTC to the current system date/time
openevse `date "+S1 %y %m %d %l %M %S"`
# Get current RTC time
openevse GT
~~~
