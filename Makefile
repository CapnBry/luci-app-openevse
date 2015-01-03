include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-openevse
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk
PKG_INSTALL:=1

define Package/luci-app-openevse
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  MAINTAINER:=Bryan Mayland <capnbry@gmail.com>
  TITLE:=OpenEVSE status information
  DEPENDS:=luci coreutils-stty
  PKGARCH:=all
endef

define Package/luci-app-openevse/description
  Quick status and control script for OpenEVSE RAPI
  Appears in Admin Status -> OpenEVSE
endef

define Build/Compile
endef

define Build/Install
endef

define Package/luci-app-openevse/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci
	$(CP) ./luasrc/* $(1)/usr/lib/lua/luci

	$(INSTALL_DIR) $(1)/usr/bin
	$(LN) ../../usr/lib/lua/luci/model/cbi/admin_status/openevse.lua $(1)/usr/bin/openevse
endef

$(eval $(call BuildPackage,luci-app-openevse))
