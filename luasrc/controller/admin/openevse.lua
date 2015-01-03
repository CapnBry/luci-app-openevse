module("luci.controller.admin.openevse", package.seeall)

function index()
  entry({"admin", "status", "openevse"}, cbi("admin_status/openevse"), "OpenEVSE", 15)
end

