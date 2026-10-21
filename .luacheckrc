std = "lua51"
max_line_length = 160
self = false
codes = true
exclude_files = { ".luarocks", "lua_modules" }

-- WoW client globals the adapters use
local wow = {
  "ToadsLCDB", "SLASH_TOADSLC1", "SLASH_TOADSLC2", "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames",
}
local wow_read = {
  "Ambiguate", "C_AddOns", "C_ChatInfo", "C_Timer", "CanInspect", "CheckInteractDistance", "ClearInspectPlayer",
  "CreateFrame", "DEFAULT_CHAT_FRAME", "EasyMenu", "Enum", "GameTooltip", "GetAddOnMetadata", "GetInstanceInfo",
  "GetItemIcon", "GetItemInfo", "GetItemInfoInstant", "GetNumGroupMembers", "GetNumSubgroupMembers",
  "GetRealmName", "GetServerTime", "GetTalentTabInfo", "InCombatLockdown", "IsInGroup", "IsInInstance", "IsInRaid", "MenuUtil",
  "NotifyInspect", "RAID_CLASS_COLORS", "RANDOM_ROLL_RESULT", "RandomRoll", "RegisterAddonMessagePrefix",
  "SendAddonMessage", "SendChatMessage", "StaticPopup_Show", "TooltipDataProcessor", "UIParent", "UnitClass",
  "UnitIsGroupAssistant", "UnitGUID", "GetTime", "UnitIsGroupLeader", "UnitIsUnit", "UnitName", "WOW_PROJECT_BURNING_CRUSADE_CLASSIC",
  "WOW_PROJECT_ID", "ChatFontNormal", "ACCEPT", "CANCEL", "tinsert", "date", "time", "_G",
}

files["ToadsLC/adapters"] = { globals = wow, read_globals = wow_read }
files["ToadsLC/Init.lua"] = { globals = wow, read_globals = wow_read }
files["ToadsLC/core"] = { read_globals = { "date" } }
files["spec"] = { std = "+busted", max_line_length = false, globals = { "_G" } }
