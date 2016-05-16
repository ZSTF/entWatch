//====================================================================================================
//
// Name: entWatch
// Author: Prometheum & zaCade
// Description: Monitor entity interactions.
//
//====================================================================================================
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <clientprefs>
#include <adminmenu>
#tryinclude <morecolors>
#tryinclude <entWatch>

#define PLUGIN_VERSION "3.7.3"
#undef REQUIRE_PLUGIN

//----------------------------------------------------------------------------------------------------
// Purpose: Entity data
//----------------------------------------------------------------------------------------------------
enum entities
{
	String:ent_name[32],
	String:ent_shortname[32],
	String:ent_color[32],
	String:ent_buttonclass[32],
	String:ent_filtername[32],
	bool:ent_hasfiltername,
	bool:ent_blockpickup,
	bool:ent_allowtransfer,
	bool:ent_forcedrop,
	bool:ent_chat,
	bool:ent_hud,
	ent_hammerid,
	ent_weaponid,
	ent_buttonid,
	ent_ownerid,
	ent_mode, // 0 = No button, 1 = Spam protection only, 2 = Cooldowns, 3 = Limited uses, 4 = Limited uses with cooldowns, 5 = Cooldowns after multiple uses.
	ent_uses,
	ent_maxuses,
	ent_cooldown,
	ent_cooldowntime,
};

new entArray[512][entities];
new entArraySize = 512;
new triggerArray[512];
new triggerSize = 512;

//----------------------------------------------------------------------------------------------------
// Purpose: Color settings
//----------------------------------------------------------------------------------------------------
new String:color_tag[16]         = "E01B5D";
new String:color_name[16]        = "EDEDED";
new String:color_steamid[16]     = "B2B2B2";
new String:color_use[16]         = "67ADDF";
new String:color_pickup[16]      = "C9EF66";
new String:color_drop[16]        = "E562BA";
new String:color_disconnect[16]  = "F1B567";
new String:color_death[16]       = "F1B567";
new String:color_warning[16]     = "F16767";

//----------------------------------------------------------------------------------------------------
// Purpose: Client settings
//----------------------------------------------------------------------------------------------------
new Handle:g_hCookie_Display     = INVALID_HANDLE;
new Handle:g_hCookie_Restricted  = INVALID_HANDLE;
new Handle:g_hCookie_RestrictedLength = INVALID_HANDLE;
new Handle:g_hCookie_RestrictedIssued = INVALID_HANDLE;
new Handle:g_hCookie_RestrictedBy	  = INVALID_HANDLE;

new bool:g_bDisplay[MAXPLAYERS + 1]     = false;
new bool:g_bRestricted[MAXPLAYERS + 1]  = false;
new String:g_sRestrictedBy[MAXPLAYERS + 1][64];
new g_iRestrictedLength[MAXPLAYERS + 1];
new g_iRestrictedIssued[MAXPLAYERS + 1];
new g_iAdminMenuTarget[MAXPLAYERS + 1];

//----------------------------------------------------------------------------------------------------
// Purpose: Plugin settings
//----------------------------------------------------------------------------------------------------
new Handle:g_hCvar_DisplayEnabled    = INVALID_HANDLE;
new Handle:g_hCvar_DisplayCooldowns  = INVALID_HANDLE;
new Handle:g_hCvar_ModeTeamOnly      = INVALID_HANDLE;
new Handle:g_hCvar_ConfigColor       = INVALID_HANDLE;
new Handle:g_hAdminMenu				 = INVALID_HANDLE;
new Handle:g_hOnBanForward			 = INVALID_HANDLE;
new Handle:g_hOnUnbanForward		 = INVALID_HANDLE;

new bool:g_bRoundTransition  = false;
new bool:g_bConfigLoaded     = false;
new bool:g_bLateLoad         = false;

new Handle:g_hGetSlot;
new Handle:g_hBumpWeapon;
new Handle:g_hOnPickedUp;

//----------------------------------------------------------------------------------------------------
// Purpose: Plugin information
//----------------------------------------------------------------------------------------------------
public Plugin:myinfo =
{
	name         = "entWatch",
	author       = "Prometheum & zaCade. Edits: George & Obus & BotoX",
	description  = "Notify players about entity interactions.",
	version      = PLUGIN_VERSION,
	url          = "https://github.com/Obuss/entWatch" // Original here: "https://github.com/zaCade/entWatch"
};

public APLRes:AskPluginLoad2(Handle:hThis, bool:bLate, String:sError[], err_max)
{
	CreateNative("entWatch_IsClientBanned", Native_IsClientBanned);
	CreateNative("entWatch_BanClient", Native_BanClient);
	CreateNative("entWatch_UnbanClient", Native_UnbanClient);
	CreateNative("entWatch_IsSpecialItem", Native_IsSpecialItem);
	CreateNative("entWatch_HasSpecialItem", Native_HasSpecialItem);

	RegPluginLibrary("entWatch");

	g_bLateLoad = bLate;

	return APLRes_Success;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Plugin initialization
//----------------------------------------------------------------------------------------------------
public OnPluginStart()
{
	CreateConVar("entwatch_version", PLUGIN_VERSION, "Current version of entWatch", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_hCvar_DisplayEnabled    = CreateConVar("entwatch_display_enable", "1", "Enable/Disable the display.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvar_DisplayCooldowns  = CreateConVar("entwatch_display_cooldowns", "1", "Show/Hide the cooldowns on the display.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvar_ModeTeamOnly      = CreateConVar("entwatch_mode_teamonly", "1", "Enable/Disable team only mode.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvar_ConfigColor       = CreateConVar("entwatch_config_color", "color_classic", "The name of the color config.", FCVAR_NONE);

	g_hCookie_Display     = RegClientCookie("entwatch_display", "", CookieAccess_Private);
	g_hCookie_Restricted  = RegClientCookie("entwatch_restricted", "", CookieAccess_Private);
	g_hCookie_RestrictedLength = RegClientCookie("entwatch_restrictedlength", "", CookieAccess_Private);
	g_hCookie_RestrictedIssued = RegClientCookie("entwatch_restrictedissued", "", CookieAccess_Private);
	g_hCookie_RestrictedBy     = RegClientCookie("entwatch_restrictedby", "", CookieAccess_Private);

	new Handle:hTopMenu;

	if (LibraryExists("adminmenu") && ((hTopMenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(hTopMenu);
	}

	RegConsoleCmd("sm_hud", Command_ToggleHUD);
	RegConsoleCmd("sm_status", Command_Status);

	RegAdminCmd("sm_eban", Command_Restrict, ADMFLAG_BAN);
	RegAdminCmd("sm_ebanlist", Command_EBanlist, ADMFLAG_BAN);
	RegAdminCmd("sm_eunban", Command_Unrestrict, ADMFLAG_BAN);
	RegAdminCmd("sm_etransfer", Command_Transfer, ADMFLAG_BAN);
	RegAdminCmd("sm_setcooldown", Command_Cooldown, ADMFLAG_BAN);
	RegAdminCmd("sm_ew_reloadconfig", Command_ReloadConfig, ADMFLAG_CONFIG);
	RegAdminCmd("sm_ewdebugarray", Command_DebugArray, ADMFLAG_CONFIG);

	HookEvent("round_start", Event_RoundStart, EventHookMode_Pre);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);

	CreateTimer(1.0, Timer_DisplayHUD, _, TIMER_REPEAT);
	CreateTimer(1.0, Timer_Cooldowns, _, TIMER_REPEAT);

	LoadTranslations("entWatch.phrases");
	LoadTranslations("common.phrases");

	AutoExecConfig(true, "plugin.entWatch");

	g_hOnBanForward = CreateGlobalForward("entWatch_OnClientBanned", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_hOnUnbanForward = CreateGlobalForward("entWatch_OnClientUnbanned", ET_Ignore, Param_Cell, Param_Cell);

	if (g_bLateLoad)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
				continue;

			OnClientPutInServer(i);
			OnClientCookiesCached(i);
		}
	}

	new Handle:hGameConf = LoadGameConfigFile("plugin.entWatch");
	if(hGameConf == INVALID_HANDLE)
	{
		SetFailState("Couldn't load plugin.entWatch game config!")
		return;
	}
	if(GameConfGetOffset(hGameConf, "GetSlot") == -1)
	{
		CloseHandle(hGameConf);
		SetFailState("Couldn't get GetSlot offset from game config!");
		return;
	}
	if(GameConfGetOffset(hGameConf, "BumpWeapon") == -1)
	{
		CloseHandle(hGameConf);
		SetFailState("Couldn't get BumpWeapon offset from game config!");
		return;
	}
	if(GameConfGetOffset(hGameConf, "OnPickedUp") == -1)
	{
		CloseHandle(hGameConf);
		SetFailState("Couldn't get OnPickedUp offset from game config!");
		return;
	}

	// 320	CBaseCombatWeapon::GetSlot(void)const
	StartPrepSDKCall(SDKCall_Entity);
	if(!PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "GetSlot"))
	{
		CloseHandle(hGameConf);
		SetFailState("PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, \"GetSlot\" failed!");
		return;
	}
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hGetSlot = EndPrepSDKCall();

	// 397	CCSPlayer::BumpWeapon(CBaseCombatWeapon *)
	StartPrepSDKCall(SDKCall_Player);
	if(!PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "BumpWeapon"))
	{
		CloseHandle(hGameConf);
		SetFailState("PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, \"BumpWeapon\" failed!");
		return;
	}
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hBumpWeapon = EndPrepSDKCall();

	// 300	CBaseCombatWeapon::OnPickedUp(CBaseCombatCharacter *)
	StartPrepSDKCall(SDKCall_Entity);
	if(!PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, "OnPickedUp"))
	{
		CloseHandle(hGameConf);
		SetFailState("PrepSDKCall_SetFromConf(hGameConf, SDKConf_Virtual, \"OnPickedUp\" failed!");
		return;
	}
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hOnPickedUp = EndPrepSDKCall();

	CloseHandle(hGameConf);
	if(g_hGetSlot == INVALID_HANDLE)
	{
		SetFailState("Couldn't prepare GetSlot SDKCall!")
		return;
	}
	if(g_hGetSlot == INVALID_HANDLE)
	{
		SetFailState("Couldn't prepare BumpWeapon SDKCall!")
		return;
	}
	if(g_hOnPickedUp == INVALID_HANDLE)
	{
		SetFailState("Couldn't prepare OnPickedUp SDKCall!")
		return;
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Main ban function
//----------------------------------------------------------------------------------------------------
EBanClient(client, const String:sLength[], admin)
{
	new iBanLen = StringToInt(sLength);
	new iBanDuration = (iBanLen - GetTime()) / 60;

	if (admin == 0)
	{
		Format(g_sRestrictedBy[client], sizeof(g_sRestrictedBy[]), "Console");
		SetClientCookie(client, g_hCookie_RestrictedBy, "Console");
	}
	else
	{
		new String:sAdminSID[64];
		GetClientAuthId(admin, AuthId_Steam2, sAdminSID, sizeof(sAdminSID));
		Format(g_sRestrictedBy[client], sizeof(g_sRestrictedBy[]), "%s (%N)", sAdminSID, admin);

		SetClientCookie(client, g_hCookie_RestrictedBy, sAdminSID);
	}

	if (iBanLen == 0)
	{
		iBanDuration = 0;
		g_bRestricted[client] = true;

		LogAction(admin, client, "\"%L\" restricted \"%L\"", admin, client);
	}
	else if (iBanLen == 1)
	{
		iBanDuration = -1;
		g_iRestrictedLength[client] = 1;
		SetClientCookie(client, g_hCookie_RestrictedLength, "1");

		LogAction(admin, client, "\"%L\" restricted \"%L\" permanently", admin, client);
	}
	else
	{
		g_iRestrictedLength[client] = iBanLen;
		SetClientCookie(client, g_hCookie_RestrictedLength, sLength);

		LogAction(admin, client, "\"%L\" restricted \"%L\" for %d minutes", admin, client, iBanDuration);
	}

	new String:sIssueTime[64];
	Format(sIssueTime, sizeof(sIssueTime), "%d", GetTime());

	g_iRestrictedIssued[client] = GetTime();
	SetClientCookie(client, g_hCookie_RestrictedIssued, sIssueTime);

	CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%srestricted \x07%s%N", color_tag, color_name, admin, color_warning, color_name, client);

	Call_StartForward(g_hOnBanForward);
	Call_PushCell(admin);
	Call_PushCell(iBanDuration);
	Call_PushCell(client);
	Call_Finish();
}

//----------------------------------------------------------------------------------------------------
// Purpose: Main unban function
//----------------------------------------------------------------------------------------------------
EUnbanClient(client, admin)
{
	g_bRestricted[client] = false;
	g_iRestrictedLength[client] = 0;
	g_iRestrictedIssued[client] = 0;
	g_sRestrictedBy[client][0] = '\0'
	SetClientCookie(client, g_hCookie_RestrictedLength, "0");
	SetClientCookie(client, g_hCookie_RestrictedBy, "");
	SetClientCookie(client, g_hCookie_RestrictedIssued, "");

	CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%sunrestricted \x07%s%N", color_tag, color_name, admin, color_warning, color_name, client);
	LogAction(admin, client, "\"%L\" unrestricted \"%L\"", admin, client);

	Call_StartForward(g_hOnUnbanForward);
	Call_PushCell(admin);
	Call_PushCell(client);
	Call_Finish();
}
//----------------------------------------------------------------------------------------------------
// Purpose: Safeguard against adminmenu unloading
//----------------------------------------------------------------------------------------------------
public OnLibraryRemoved(const String:sName[])
{
	if (StrEqual(sName, "adminmenu"))
		g_hAdminMenu = INVALID_HANDLE;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Add our entries to the main admin menu
//----------------------------------------------------------------------------------------------------
public OnAdminMenuReady(Handle:hAdminMenu)
{
	if (hAdminMenu == g_hAdminMenu)
	{
		return;
	}

	g_hAdminMenu = hAdminMenu;

	new TopMenuObject:hMenuObj = AddToTopMenu(g_hAdminMenu, "entWatch_commands", TopMenuObject_Category, AdminMenu_Commands_Handler, INVALID_TOPMENUOBJECT);

	if (hMenuObj == INVALID_TOPMENUOBJECT)
	{
		return;
	}

	AddToTopMenu(g_hAdminMenu, "entWatch_banlist", TopMenuObject_Item, Handler_EBanList, hMenuObj, "sm_ebanlist", ADMFLAG_BAN);
	AddToTopMenu(g_hAdminMenu, "entWatch_ban", TopMenuObject_Item, Handler_EBan, hMenuObj, "sm_eban", ADMFLAG_BAN);
	AddToTopMenu(g_hAdminMenu, "entWatch_transfer", TopMenuObject_Item, Handler_Transfer, hMenuObj, "sm_etransfer", ADMFLAG_BAN);
	AddToTopMenu(g_hAdminMenu, "entWatch_unban", TopMenuObject_Item, Handler_EUnban, hMenuObj, "sm_eunban", ADMFLAG_BAN);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Menu Stuff
//----------------------------------------------------------------------------------------------------
public AdminMenu_Commands_Handler(Handle:hMenu, TopMenuAction:hAction, TopMenuObject:hObjID, iParam1, String:sBuffer[], iMaxlen)
{
	if (hAction == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxlen, "%s", "entWatch Commands", iParam1);
	}
	else if (hAction == TopMenuAction_DisplayTitle)
	{
		Format(sBuffer, iMaxlen, "%s", "entWatch Commands:", iParam1);
	}
}

public Handler_EBanList(Handle:hMenu, TopMenuAction:hAction, TopMenuObject:hObjID, iParam1, String:sBuffer[], iMaxlen)
{
	if (hAction == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxlen, "%s", "List Banned Clients", iParam1);
	}
	else if (hAction == TopMenuAction_SelectOption)
	{
		Menu_List(iParam1);
	}
}

public Handler_EBan(Handle:hMenu, TopMenuAction:hAction, TopMenuObject:hObjID, iParam1, String:sBuffer[], iMaxlen)
{
	if (hAction == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxlen, "%s", "Ban a Client", iParam1);
	}
	else if (hAction == TopMenuAction_SelectOption)
	{
		Menu_EBan(iParam1);
	}
}

public Handler_Transfer(Handle:hMenu, TopMenuAction:hAction, TopMenuObject:hObjID, iParam1, String:sBuffer[], iMaxlen)
{
	if (hAction == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxlen, "%s", "Transfer an item", iParam1);
	}
	else if (hAction == TopMenuAction_SelectOption)
	{
		Menu_Transfer(iParam1);
	}
}

public Handler_EUnban(Handle:hMenu, TopMenuAction:hAction, TopMenuObject:hObjID, iParam1, String:sBuffer[], iMaxlen)
{
	if (hAction == TopMenuAction_DisplayOption)
	{
		Format(sBuffer, iMaxlen, "%s", "Unban a Client", iParam1);
	}
	else if (hAction == TopMenuAction_SelectOption)
	{
		Menu_EUnban(iParam1);
	}
}

Menu_List(client)
{
	new iBannedClients;

	new Handle:hListMenu = CreateMenu(MenuHandler_Menu_List);
	SetMenuTitle(hListMenu, "[entWatch] Banned Clients:");
	SetMenuExitBackButton(hListMenu, true);

	for (new i = 1; i < MaxClients + 1; i++)
	{
		if (IsClientInGame(i) && AreClientCookiesCached(i))
		{
			decl String:sBanLen[32];
			GetClientCookie(i, g_hCookie_RestrictedLength, sBanLen, sizeof(sBanLen));
			new iBanLen = StringToInt(sBanLen);

			if ((iBanLen != 0 && iBanLen >= GetTime()) || iBanLen == 1 || g_bRestricted[i])
			{
				new iUserID = GetClientUserId(i);
				decl String:sUserID[32];
				decl String:sBuff[64];
				Format(sBuff, sizeof(sBuff), "%N (#%i)", i, iUserID);
				Format(sUserID, sizeof(sUserID), "%d", iUserID);

				AddMenuItem(hListMenu, sUserID, sBuff);
				iBannedClients++;
			}
		}
	}

	if (!iBannedClients)
		AddMenuItem(hListMenu, "", "No Banned Clients.", ITEMDRAW_DISABLED);

	DisplayMenu(hListMenu, client, MENU_TIME_FOREVER);
}

Menu_EBan(client)
{
	new Handle:hEBanMenu = CreateMenu(MenuHandler_Menu_EBan);
	SetMenuTitle(hEBanMenu, "[entWatch] Ban a Client:");
	SetMenuExitBackButton(hEBanMenu, true);
	AddTargetsToMenu2(hEBanMenu, client, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

	DisplayMenu(hEBanMenu, client, MENU_TIME_FOREVER);
}

Menu_Transfer(client)
{
	new Handle:hTransferMenu = CreateMenu(MenuHandler_Menu_Transfer);
	new String:sMenuTemp[64];
	new String:sIndexTemp[16];
	new iHeldCount = 0;
	SetMenuTitle(hTransferMenu, "[entWatch] Transfer an item:");
	SetMenuExitBackButton(hTransferMenu, true);

	for (new i = 0; i < entArraySize; i++)
	{
		if (entArray[i][ent_allowtransfer])
		{
			if (entArray[i][ent_ownerid] != -1)
			{
				IntToString(i, sIndexTemp, sizeof(sIndexTemp));
				Format(sMenuTemp, sizeof(sMenuTemp), "%s | %N (#%i)", entArray[i][ent_name], entArray[i][ent_ownerid], GetClientUserId(entArray[i][ent_ownerid]));
				AddMenuItem(hTransferMenu, sIndexTemp, sMenuTemp, ITEMDRAW_DEFAULT);
				iHeldCount++;
			}
		}
	}

	if (!iHeldCount)
		AddMenuItem(hTransferMenu, "", "No transferable items currently held.", ITEMDRAW_DISABLED);

	DisplayMenu(hTransferMenu, client, MENU_TIME_FOREVER);
}

Menu_EUnban(client)
{
	new iBannedClients;

	new Handle:hEUnbanMenu = CreateMenu(MenuHandler_Menu_EUnban);
	SetMenuTitle(hEUnbanMenu, "[entWatch] Unban a Client:");
	SetMenuExitBackButton(hEUnbanMenu, true);

	for (new i = 1; i < MaxClients + 1; i++)
	{
		if (IsClientInGame(i) && AreClientCookiesCached(i))
		{
			decl String:sBanLen[32];
			GetClientCookie(i, g_hCookie_RestrictedLength, sBanLen, sizeof(sBanLen));
			new iBanLen = StringToInt(sBanLen);

			if ((iBanLen != 0 && iBanLen >= GetTime()) || iBanLen == 1 || g_bRestricted[i])
			{
				new iUserID = GetClientUserId(i);
				decl String:sUserID[32];
				decl String:sBuff[64];
				Format(sBuff, sizeof(sBuff), "%N (#%i)", i, iUserID);
				Format(sUserID, sizeof(sUserID), "%d", iUserID);

				AddMenuItem(hEUnbanMenu, sUserID, sBuff);
				iBannedClients++;
			}
		}
	}

	if (!iBannedClients)
		AddMenuItem(hEUnbanMenu, "", "No Banned Clients.", ITEMDRAW_DISABLED);

	DisplayMenu(hEUnbanMenu, client, MENU_TIME_FOREVER);
}

public MenuHandler_Menu_List(Handle:hMenu, MenuAction:hAction, iParam1, iParam2)
{
	switch(hAction)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack && g_hAdminMenu != INVALID_HANDLE)
				DisplayTopMenu(g_hAdminMenu, iParam1, TopMenuPosition_LastCategory);
		}

		case MenuAction_Select:
		{
			decl String:sOption[32];
			GetMenuItem(hMenu, iParam2, sOption, sizeof(sOption));
			new target = GetClientOfUserId(StringToInt(sOption));

			if (target == 0)
			{
				CPrintToChat(iParam1, "\x07%s[entWatch]\x07%s Player no longer available", color_tag, color_warning);

				if (g_hAdminMenu != INVALID_HANDLE)
					DisplayTopMenu(g_hAdminMenu, iParam1, TopMenuPosition_LastCategory);
				else
					CloseHandle(hMenu);
			}
			else
			{
				Menu_ListTarget(iParam1, target);
			}
		}
	}
}

public MenuHandler_Menu_EBan(Handle:hMenu, MenuAction:hAction, iParam1, iParam2)
{
	switch(hAction)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack && g_hAdminMenu != INVALID_HANDLE)
				DisplayTopMenu(g_hAdminMenu, iParam1, TopMenuPosition_LastCategory);
		}

		case MenuAction_Select:
		{
			decl String:sOption[32];
			GetMenuItem(hMenu, iParam2, sOption, sizeof(sOption));
			new target = GetClientOfUserId(StringToInt(sOption));

			if (target == 0)
			{
				CPrintToChat(iParam1, "\x07%s[entWatch]\x07%s Player no longer available", color_tag, color_warning);

				if (g_hAdminMenu != INVALID_HANDLE)
					DisplayTopMenu(g_hAdminMenu, iParam1, TopMenuPosition_LastCategory);
				else
					CloseHandle(hMenu);
			}
			else
			{
				Menu_EBanTime(iParam1, target);
			}
		}
	}
}

public MenuHandler_Menu_Transfer(Handle:hMenu, MenuAction:hAction, iParam1, iParam2)
{
	switch(hAction)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack && g_hAdminMenu != INVALID_HANDLE)
				DisplayTopMenu(g_hAdminMenu, iParam1, TopMenuPosition_LastCategory);
		}

		case MenuAction_Select:
		{
			decl String:sOption[32];
			GetMenuItem(hMenu, iParam2, sOption, sizeof(sOption));
			new iEntityIndex = StringToInt(sOption);

			if (entArray[iEntityIndex][ent_ownerid] != -1)
			{
				Menu_TransferTarget(iParam1, iEntityIndex);
			}
			else
			{
				CPrintToChat(iParam1, "\x07%s[entWatch]\x07%s Item no longer available.", color_tag, color_warning);
			}
		}
	}
}

public MenuHandler_Menu_EUnban(Handle:hMenu, MenuAction:hAction, iParam1, iParam2)
{
	switch(hAction)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack && g_hAdminMenu != INVALID_HANDLE)
				DisplayTopMenu(g_hAdminMenu, iParam1, TopMenuPosition_LastCategory);
		}

		case MenuAction_Select:
		{
			decl String:sOption[32];
			GetMenuItem(hMenu, iParam2, sOption, sizeof(sOption));
			new target = GetClientOfUserId(StringToInt(sOption));

			if (target == 0)
			{
				CPrintToChat(iParam1, "\x07%s[entWatch]\x07%s Player no longer available", color_tag, color_warning);

				if (g_hAdminMenu != INVALID_HANDLE)
					DisplayTopMenu(g_hAdminMenu, iParam1, TopMenuPosition_LastCategory);
				else
					CloseHandle(hMenu);
			}
			else
			{
				EUnbanClient(target, iParam1);
			}
		}
	}
}

Menu_TransferTarget(client, iEntityIndex)
{
	new Handle:hTransferTarget = CreateMenu(MenuHandler_Menu_TransferTarget);
	new String:sMenuTemp[64];
	new String:sIndexTemp[32];
	SetMenuTitle(hTransferTarget, "[entWatch] Transfer target:");
	SetMenuExitBackButton(hTransferTarget, true);

	g_iAdminMenuTarget[client] = iEntityIndex;
	Format(sIndexTemp, sizeof(sIndexTemp), "%i", GetClientUserId(client));
	Format(sMenuTemp, sizeof(sMenuTemp), "%N (#%s)", client, sIndexTemp);
	AddMenuItem(hTransferTarget, sIndexTemp, sMenuTemp, ITEMDRAW_DEFAULT);

	for (new i = 1; i < MAXPLAYERS; i++)
	{
		if (!IsClientInGame(i))
			continue;

		if (IsFakeClient(i))
			continue;

		if (GetClientTeam(i) != GetClientTeam(entArray[iEntityIndex][ent_ownerid]))
			continue;

		if (i == client)
			continue;

		Format(sIndexTemp, sizeof(sIndexTemp), "%i", GetClientUserId(i));
		Format(sMenuTemp, sizeof(sMenuTemp), "%N (#%s)", i, sIndexTemp);
		AddMenuItem(hTransferTarget, sIndexTemp, sMenuTemp, ITEMDRAW_DEFAULT);
	}

	DisplayMenu(hTransferTarget, client, MENU_TIME_FOREVER);
}

public MenuHandler_Menu_TransferTarget(Handle:hMenu, MenuAction:hAction, iParam1, iParam2)
{
	switch (hAction)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack)
				Menu_Transfer(iParam1);
		}

		case MenuAction_Select:
		{
			decl String:sOption[64];
			GetMenuItem(hMenu, iParam2, sOption, sizeof(sOption));
			new iEntityIndex = g_iAdminMenuTarget[iParam1];
			new receiver = GetClientOfUserId(StringToInt(sOption));

			if (receiver == 0)
			{
				CPrintToChat(iParam1, "\x07%s[entWatch] \x07%sReceiver is not valid anymore.", color_tag, color_warning);
				return;
			}

			if (entArray[iEntityIndex][ent_allowtransfer])
			{
				if (entArray[iEntityIndex][ent_ownerid] != -1)
				{
					if (IsValidEdict(entArray[iEntityIndex][ent_weaponid]))
					{
						new iCurOwner = entArray[iEntityIndex][ent_ownerid];

						if (GetClientTeam(receiver) != GetClientTeam(iCurOwner))
						{
							CPrintToChat(iParam1, "\x07%s[entWatch] \x07%sThe receivers team differs from the targets team.", color_tag, color_warning);
							return;
						}

						new String:buffer_classname[64];
						GetEdictClassname(entArray[iEntityIndex][ent_weaponid], buffer_classname, sizeof(buffer_classname))

						CS_DropWeapon(iCurOwner, entArray[iEntityIndex][ent_weaponid], false);
						GivePlayerItem(iCurOwner, buffer_classname);

						if (entArray[iEntityIndex][ent_chat])
						{
							entArray[iEntityIndex][ent_chat] = false;
							FixedEquipPlayerWeapon(receiver, entArray[iEntityIndex][ent_weaponid]);
							entArray[iEntityIndex][ent_chat] = true;
						}
						else
						{
							FixedEquipPlayerWeapon(receiver, entArray[iEntityIndex][ent_weaponid]);
						}

						CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%stransfered all items from \x07%s%N \x07%sto \x07%s%N", color_tag, color_name, iParam1, color_warning, color_name, iCurOwner, color_warning, color_name, receiver);

						LogAction(iParam1, iCurOwner, "\"%L\" transfered all items from \"%L\" to \"%L\"", iParam1, iCurOwner, receiver);
					}
				}
				else
				{
					CPrintToChat(iParam1, "\x07%s[entWatch] \x07%sItem is not valid anymore.", color_tag, color_warning);
				}
			}
		}
	}
}

Menu_EBanTime(client, target)
{
	new Handle:hEBanMenuTime = CreateMenu(MenuHandler_Menu_EBanTime);
	SetMenuTitle(hEBanMenuTime, "[entWatch] Ban Time for %N:", target);
	SetMenuExitBackButton(hEBanMenuTime, true);

	g_iAdminMenuTarget[client] = target;
	AddMenuItem(hEBanMenuTime, "0", "Temporary");
	AddMenuItem(hEBanMenuTime, "10", "10 Minutes");
	AddMenuItem(hEBanMenuTime, "60", "1 Hour");
	AddMenuItem(hEBanMenuTime, "1440", "1 Day");
	AddMenuItem(hEBanMenuTime, "10080", "1 Week");
	AddMenuItem(hEBanMenuTime, "40320", "1 Month");
	AddMenuItem(hEBanMenuTime, "1", "Permanent");

	DisplayMenu(hEBanMenuTime, client, MENU_TIME_FOREVER);
}

public MenuHandler_Menu_EBanTime(Handle:hMenu, MenuAction:hAction, iParam1, iParam2)
{
	switch(hAction)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack)
				Menu_EBan(iParam1);
		}

		case MenuAction_Select:
		{
			decl String:sOption[64];
			GetMenuItem(hMenu, iParam2, sOption, sizeof(sOption));
			new target = g_iAdminMenuTarget[iParam1];

			if (target == 0)
			{
				CPrintToChat(iParam1, "\x07%s[entWatch]\x07%s Player no longer available", color_tag, color_warning);
				Menu_EBan(iParam1);
			}
			else
			{
				if (StrEqual(sOption, "0"))
				{
					EBanClient(target, "0", iParam1);
				}
				else if (StrEqual(sOption, "1"))
				{
					EBanClient(target, "1", iParam1);
				}
				else
				{
					new String:sBanLen[64];
					Format(sBanLen, sizeof(sBanLen), "%d", GetTime() + (StringToInt(sOption) * 60));

					EBanClient(target, sBanLen, iParam1);
				}
			}
		}
	}
}

Menu_ListTarget(client, target)
{
	new Handle:hListTargetMenu = CreateMenu(MenuHandler_Menu_ListTarget);
	SetMenuTitle(hListTargetMenu, "[entWatch] Banned Client: %N", target);
	SetMenuExitBackButton(hListTargetMenu, true);

	new String:sBanExpiryDate[64];
	new String:sBanIssuedDate[64];
	new String:sBanDuration[64];
	new String:sBannedBy[64];
	new String:sUserID[32];
	new iBanExpiryDate = g_iRestrictedLength[target];
	new iBanIssuedDate = g_iRestrictedIssued[target];
	new iBanDuration = (iBanExpiryDate - iBanIssuedDate) / 60;
	new iUserID = GetClientUserId(target);

	FormatTime(sBanExpiryDate, sizeof(sBanExpiryDate), NULL_STRING, iBanExpiryDate);
	FormatTime(sBanIssuedDate, sizeof(sBanIssuedDate), NULL_STRING, iBanIssuedDate);
	Format(sUserID, sizeof(sUserID), "%d", iUserID);

	if (!g_bRestricted[target])
	{
		if (iBanExpiryDate == 1)
		{
			Format(sBanDuration, sizeof(sBanDuration), "Duration: Permanent");
			Format(sBanExpiryDate, sizeof(sBanExpiryDate), "Expires: Never");
		}
		else
		{
			Format(sBanDuration, sizeof(sBanDuration), "Duration: %d %s", iBanDuration, SingularOrMultiple(iBanDuration)?"Minutes":"Minute");
			Format(sBanExpiryDate, sizeof(sBanExpiryDate), "Expires: %s", sBanExpiryDate);
		}
	}
	else
	{
		Format(sBanDuration, sizeof(sBanDuration), "Duration: Temporary");
		Format(sBanExpiryDate, sizeof(sBanExpiryDate), "Expires: On Map Change");
	}

	Format(sBanIssuedDate, sizeof(sBanIssuedDate), "Issued on: %s", !(iBanIssuedDate == 0)?sBanIssuedDate:"Unknown");
	Format(sBannedBy, sizeof(sBannedBy), "Admin SID: %s", g_sRestrictedBy[target][0]?g_sRestrictedBy[target]:"Unknown");

	AddMenuItem(hListTargetMenu, "", sBannedBy, ITEMDRAW_DISABLED);
	AddMenuItem(hListTargetMenu, "", sBanIssuedDate, ITEMDRAW_DISABLED);
	AddMenuItem(hListTargetMenu, "", sBanExpiryDate, ITEMDRAW_DISABLED);
	AddMenuItem(hListTargetMenu, "", sBanDuration, ITEMDRAW_DISABLED);
	AddMenuItem(hListTargetMenu, "", "", ITEMDRAW_SPACER);
	AddMenuItem(hListTargetMenu, sUserID, "Unban");

	DisplayMenu(hListTargetMenu, client, MENU_TIME_FOREVER);
}

public MenuHandler_Menu_ListTarget(Handle:hMenu, MenuAction:hAction, iParam1, iParam2)
{
	switch(hAction)
	{
		case MenuAction_End:
			CloseHandle(hMenu);

		case MenuAction_Cancel:
		{
			if (iParam2 == MenuCancel_ExitBack)
				Menu_List(iParam1);
		}

		case MenuAction_Select:
		{
			decl String:sOption[32];
			GetMenuItem(hMenu, iParam2, sOption, sizeof(sOption));
			new target = GetClientOfUserId(StringToInt(sOption));

			if (target == 0)
			{
				CPrintToChat(iParam1, "\x07%s[entWatch]\x07%s Player no longer available", color_tag, color_warning);
				Menu_List(iParam1);
			}
			else
			{
				EUnbanClient(target, iParam1);
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Set variables
//----------------------------------------------------------------------------------------------------
public OnMapStart()
{
	CleanData();
	LoadColors();
	LoadConfig();
}

//----------------------------------------------------------------------------------------------------
// Purpose: Hook RoundStart event
//----------------------------------------------------------------------------------------------------
public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_bConfigLoaded && g_bRoundTransition)
	{
		CPrintToChatAll("\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "welcome");
	}

	g_bRoundTransition = false;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Hook RoundEnd event
//----------------------------------------------------------------------------------------------------
public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_bConfigLoaded && !g_bRoundTransition)
	{
		for (new index = 0; index < entArraySize; index++)
		{
			SDKUnhook(entArray[index][ent_buttonid], SDKHook_Use, OnButtonUse);
			entArray[index][ent_weaponid]       = -1;
			entArray[index][ent_buttonid]       = -1;
			entArray[index][ent_ownerid]        = -1;
			entArray[index][ent_cooldowntime]   = -1;
			entArray[index][ent_uses]           = 0;
		}
	}

	g_bRoundTransition = true;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Set client cookies once cached
//----------------------------------------------------------------------------------------------------
public OnClientCookiesCached(client)
{
	new String:buffer_cookie[32];
	GetClientCookie(client, g_hCookie_Display, buffer_cookie, sizeof(buffer_cookie));
	g_bDisplay[client] = bool:StringToInt(buffer_cookie);

	//GetClientCookie(client, g_hCookie_Restricted, buffer_cookie, sizeof(buffer_cookie));
	//g_bRestricted[client] = bool:StringToInt(buffer_cookie);

	GetClientCookie(client, g_hCookie_RestrictedLength, buffer_cookie, sizeof(buffer_cookie));

	if (StringToInt(buffer_cookie) != 1 && StringToInt(buffer_cookie) <= GetTime())
	{
		g_iRestrictedLength[client] = 0;
		SetClientCookie(client, g_hCookie_RestrictedLength, "0");
	}
	else
	{
		g_iRestrictedLength[client] = StringToInt(buffer_cookie);
	}

	GetClientCookie(client, g_hCookie_RestrictedIssued, buffer_cookie, sizeof(buffer_cookie));
	g_iRestrictedIssued[client] = StringToInt(buffer_cookie);

	GetClientCookie(client, g_hCookie_RestrictedBy, buffer_cookie, sizeof(buffer_cookie));
	Format(g_sRestrictedBy[client], sizeof(g_sRestrictedBy[]), "%s", buffer_cookie);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Hook weapons and update banned clients to new method
//----------------------------------------------------------------------------------------------------
public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);

	g_bRestricted[client] = false;

	if (!AreClientCookiesCached(client))
	{
		g_bDisplay[client] = false;
		//g_bRestricted[client] = false;
		g_iRestrictedLength[client] = 0;
	}
	else
	{
		decl String:restricted[32];
		GetClientCookie(client, g_hCookie_Restricted, restricted, sizeof(restricted));

		if (StringToInt(restricted) == 1)
		{
			SetClientCookie(client, g_hCookie_RestrictedLength, "1");
			SetClientCookie(client, g_hCookie_Restricted, "0");
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Notify of Disconnect if they had a special weapon and unhook weapons
//----------------------------------------------------------------------------------------------------
public OnClientDisconnect(client)
{
	if (g_bConfigLoaded && !g_bRoundTransition)
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_ownerid] != -1 && entArray[index][ent_ownerid] == client)
			{
				entArray[index][ent_ownerid] = -1;

				if (entArray[index][ent_forcedrop] && IsValidEdict(entArray[index][ent_weaponid]))
					CS_DropWeapon(client, entArray[index][ent_weaponid], false);

				if (entArray[index][ent_chat])
				{
					new String:buffer_steamid[32];
					GetClientAuthId(client, AuthId_Steam2, buffer_steamid, sizeof(buffer_steamid));
					ReplaceString(buffer_steamid, sizeof(buffer_steamid), "STEAM_", "", true);

					for (new ply = 1; ply <= MaxClients; ply++)
					{
						if (IsClientConnected(ply) && IsClientInGame(ply))
						{
							if (!GetConVarBool(g_hCvar_ModeTeamOnly) || (GetConVarBool(g_hCvar_ModeTeamOnly) && GetClientTeam(ply) == GetClientTeam(client) || !IsPlayerAlive(ply) || CheckCommandAccess(ply, "entWatch_chat", ADMFLAG_CHAT)))
							{
								CPrintToChat(ply, "\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, client, color_disconnect, color_steamid, buffer_steamid, color_disconnect, color_disconnect, "disconnect", entArray[index][ent_color], entArray[index][ent_name]);
							}
						}
					}
				}
			}
		}
	}

	SDKUnhook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
	SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	SDKUnhook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);

	g_bDisplay[client] = false;
	g_bRestricted[client] = false;
	g_iRestrictedLength[client] = 0;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Notify of Death if they had a special weapon
//----------------------------------------------------------------------------------------------------
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (g_bConfigLoaded && !g_bRoundTransition)
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_ownerid] != -1 && entArray[index][ent_ownerid] == client)
			{
				entArray[index][ent_ownerid] = -1;

				if (entArray[index][ent_forcedrop] && IsValidEdict(entArray[index][ent_weaponid]))
					CS_DropWeapon(client, entArray[index][ent_weaponid], false);

				if (entArray[index][ent_chat])
				{
					new String:buffer_steamid[32];
					GetClientAuthId(client, AuthId_Steam2, buffer_steamid, sizeof(buffer_steamid));
					ReplaceString(buffer_steamid, sizeof(buffer_steamid), "STEAM_", "", true);

					for (new ply = 1; ply <= MaxClients; ply++)
					{
						if (IsClientConnected(ply) && IsClientInGame(ply))
						{
							if (!GetConVarBool(g_hCvar_ModeTeamOnly) || (GetConVarBool(g_hCvar_ModeTeamOnly) && GetClientTeam(ply) == GetClientTeam(client) || !IsPlayerAlive(ply) || CheckCommandAccess(ply, "entWatch_chat", ADMFLAG_CHAT)))
							{
								CPrintToChat(ply, "\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, client, color_death, color_steamid, buffer_steamid, color_death, color_death, "death", entArray[index][ent_color], entArray[index][ent_name]);
							}
						}
					}
				}
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Notify when they pick up a special weapon
//----------------------------------------------------------------------------------------------------
public Action:OnWeaponEquip(client, weapon)
{
	if (g_bConfigLoaded && !g_bRoundTransition && IsValidEdict(weapon))
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_hammerid] == Entity_GetHammerID(weapon))
			{
				if (entArray[index][ent_weaponid] != -1 && entArray[index][ent_weaponid] == weapon)
				{
					entArray[index][ent_ownerid] = client;

					if (entArray[index][ent_chat])
					{
						new String:buffer_steamid[32];
						GetClientAuthId(client, AuthId_Steam2, buffer_steamid, sizeof(buffer_steamid));
						ReplaceString(buffer_steamid, sizeof(buffer_steamid), "STEAM_", "", true);

						for (new ply = 1; ply <= MaxClients; ply++)
						{
							if (IsClientConnected(ply) && IsClientInGame(ply))
							{
								if (!GetConVarBool(g_hCvar_ModeTeamOnly) || (GetConVarBool(g_hCvar_ModeTeamOnly) && GetClientTeam(ply) == GetClientTeam(client) || !IsPlayerAlive(ply) || CheckCommandAccess(ply, "entWatch_chat", ADMFLAG_CHAT)))
								{
									CPrintToChat(ply, "\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, client, color_pickup, color_steamid, buffer_steamid, color_pickup, color_pickup, "pickup", entArray[index][ent_color], entArray[index][ent_name]);
								}
							}
						}
					}

					break;
				}
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Notify when they drop a special weapon
//----------------------------------------------------------------------------------------------------
public Action:OnWeaponDrop(client, weapon)
{
	if (g_bConfigLoaded && !g_bRoundTransition && IsValidEdict(weapon))
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_hammerid] == Entity_GetHammerID(weapon))
			{
				if (entArray[index][ent_weaponid] != -1 && entArray[index][ent_weaponid] == weapon)
				{
					entArray[index][ent_ownerid] = -1;

					if (entArray[index][ent_chat])
					{
						new String:buffer_steamid[32];
						GetClientAuthId(client, AuthId_Steam2, buffer_steamid, sizeof(buffer_steamid));
						ReplaceString(buffer_steamid, sizeof(buffer_steamid), "STEAM_", "", true);

						for (new ply = 1; ply <= MaxClients; ply++)
						{
							if (IsClientConnected(ply) && IsClientInGame(ply))
							{
								if (!GetConVarBool(g_hCvar_ModeTeamOnly) || (GetConVarBool(g_hCvar_ModeTeamOnly) && GetClientTeam(ply) == GetClientTeam(client) || !IsPlayerAlive(ply) || CheckCommandAccess(ply, "entWatch_chat", ADMFLAG_CHAT)))
								{
									CPrintToChat(ply, "\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, client, color_drop, color_steamid, buffer_steamid, color_drop, color_drop, "drop", entArray[index][ent_color], entArray[index][ent_name]);
								}
							}
						}
					}

					break;
				}
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Prevent banned players from picking up special weapons
//----------------------------------------------------------------------------------------------------
public Action:OnWeaponCanUse(client, weapon)
{
	if (g_bConfigLoaded && !g_bRoundTransition && IsValidEdict(weapon))
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_hammerid] == Entity_GetHammerID(weapon))
			{
				if (entArray[index][ent_weaponid] == -1)
				{
					entArray[index][ent_weaponid] = weapon;

					if (entArray[index][ent_buttonid] == -1 && entArray[index][ent_mode] != 0)
					{
						new String:buffer_targetname[32];
						Entity_GetTargetName(weapon, buffer_targetname, sizeof(buffer_targetname));

						new button = -1;
						while ((button = FindEntityByClassname(button, entArray[index][ent_buttonclass])) != -1)
						{
							if (IsValidEdict(button))
							{
								new String:buffer_parentname[32];
								Entity_GetParentName(button, buffer_parentname, sizeof(buffer_parentname));

								if (StrEqual(buffer_targetname, buffer_parentname))
								{
									SDKHook(button, SDKHook_Use, OnButtonUse);
									entArray[index][ent_buttonid] = button;
									break;
								}
							}
						}
					}
				}

				if (entArray[index][ent_weaponid] == weapon)
				{
					if (entArray[index][ent_blockpickup])
					{
						return Plugin_Handled;
					}

					if (g_bRestricted[client])
					{
						return Plugin_Handled;
					}

					if (g_iRestrictedLength[client] != 1 && g_iRestrictedLength[client] != 0 && g_iRestrictedLength[client] <= GetTime())
					{
						//g_bRestricted[client] = false;
						g_iRestrictedLength[client] = 0;

						SetClientCookie(client, g_hCookie_RestrictedLength, "0");
						//SetClientCookie(client, g_hCookie_Restricted, "0");

						return Plugin_Continue;
					}

					if (g_iRestrictedLength[client] > GetTime() || g_iRestrictedLength[client] == 1)
					{
						return Plugin_Handled;
					}

					return Plugin_Continue;
				}
			}
		}
	}

	return Plugin_Continue;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Notify when they use a special weapon
//----------------------------------------------------------------------------------------------------
public Action:OnButtonUse(button, activator, caller, UseType:type, Float:value)
{
	if (g_bConfigLoaded && !g_bRoundTransition && IsValidEdict(button))
	{
		int iOffset = FindDataMapInfo(button, "m_bLocked");
		if (iOffset != -1 && GetEntData(button, iOffset, 1))
			return Plugin_Handled;

		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_buttonid] != -1 && entArray[index][ent_buttonid] == button)
			{
				if (entArray[index][ent_ownerid] != activator && entArray[index][ent_ownerid] != caller)
					return Plugin_Handled;

				if (entArray[index][ent_hasfiltername])
					DispatchKeyValue(activator, "targetname", entArray[index][ent_filtername]);

				new String:buffer_steamid[32];
				GetClientAuthId(activator, AuthId_Steam2, buffer_steamid, sizeof(buffer_steamid));
				ReplaceString(buffer_steamid, sizeof(buffer_steamid), "STEAM_", "", true);

				if (entArray[index][ent_mode] == 1)
				{
					return Plugin_Changed;
				}
				else if (entArray[index][ent_mode] == 2 && entArray[index][ent_cooldowntime] <= -1)
				{
					for (new ply = 1; ply <= MaxClients; ply++)
					{
						if (IsClientConnected(ply) && IsClientInGame(ply))
						{
							if (!GetConVarBool(g_hCvar_ModeTeamOnly) || (GetConVarBool(g_hCvar_ModeTeamOnly) && GetClientTeam(ply) == GetClientTeam(activator) || !IsPlayerAlive(ply) || CheckCommandAccess(ply, "entWatch_chat", ADMFLAG_CHAT)))
							{
								CPrintToChat(ply, "\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, activator, color_use, color_steamid, buffer_steamid, color_use, color_use, "use", entArray[index][ent_color], entArray[index][ent_name]);
							}
						}
					}

					entArray[index][ent_cooldowntime] = entArray[index][ent_cooldown];
					return Plugin_Changed;
				}
				else if (entArray[index][ent_mode] == 3 && entArray[index][ent_uses] < entArray[index][ent_maxuses])
				{
					for (new ply = 1; ply <= MaxClients; ply++)
					{
						if (IsClientConnected(ply) && IsClientInGame(ply))
						{
							if (!GetConVarBool(g_hCvar_ModeTeamOnly) || (GetConVarBool(g_hCvar_ModeTeamOnly) && GetClientTeam(ply) == GetClientTeam(activator) || !IsPlayerAlive(ply) || CheckCommandAccess(ply, "entWatch_chat", ADMFLAG_CHAT)))
							{
								CPrintToChat(ply, "\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, activator, color_use, color_steamid, buffer_steamid, color_use, color_use, "use", entArray[index][ent_color], entArray[index][ent_name]);
							}
						}
					}

					entArray[index][ent_uses]++;
					return Plugin_Changed;
				}
				else if (entArray[index][ent_mode] == 4 && entArray[index][ent_uses] < entArray[index][ent_maxuses] && entArray[index][ent_cooldowntime] <= -1)
				{
					for (new ply = 1; ply <= MaxClients; ply++)
					{
						if (IsClientConnected(ply) && IsClientInGame(ply))
						{
							if (!GetConVarBool(g_hCvar_ModeTeamOnly) || (GetConVarBool(g_hCvar_ModeTeamOnly) && GetClientTeam(ply) == GetClientTeam(activator) || !IsPlayerAlive(ply) || CheckCommandAccess(ply, "entWatch_chat", ADMFLAG_CHAT)))
							{
								CPrintToChat(ply, "\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, activator, color_use, color_steamid, buffer_steamid, color_use, color_use, "use", entArray[index][ent_color], entArray[index][ent_name]);
							}
						}
					}

					entArray[index][ent_cooldowntime] = entArray[index][ent_cooldown];
					entArray[index][ent_uses]++;
					return Plugin_Changed;
				}
				else if (entArray[index][ent_mode] == 5 && entArray[index][ent_cooldowntime] <= -1)
				{
					for (new ply = 1; ply <= MaxClients; ply++)
					{
						if (IsClientConnected(ply) && IsClientInGame(ply))
						{
							if (!GetConVarBool(g_hCvar_ModeTeamOnly) || (GetConVarBool(g_hCvar_ModeTeamOnly) && GetClientTeam(ply) == GetClientTeam(activator) || !IsPlayerAlive(ply) || CheckCommandAccess(ply, "entWatch_chat", ADMFLAG_CHAT)))
							{
								CPrintToChat(ply, "\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, activator, color_use, color_steamid, buffer_steamid, color_use, color_use, "use", entArray[index][ent_color], entArray[index][ent_name]);
							}
						}
					}

					entArray[index][ent_uses]++;
					if (entArray[index][ent_uses] >= entArray[index][ent_maxuses])
					{
						entArray[index][ent_cooldowntime] = entArray[index][ent_cooldown];
						entArray[index][ent_uses] = 0;
					}

					return Plugin_Changed;
				}

				return Plugin_Handled;
			}
		}
	}

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Display current special weapon holders
//----------------------------------------------------------------------------------------------------
public Action:Timer_DisplayHUD(Handle:timer)
{
	if (GetConVarBool(g_hCvar_DisplayEnabled))
	{
		if (g_bConfigLoaded && !g_bRoundTransition)
		{
			new String:buffer_teamtext[5][250];

			for (new index = 0; index < entArraySize; index++)
			{
				if (entArray[index][ent_hud] && entArray[index][ent_ownerid] != -1)
				{
					new String:buffer_temp[128];

					if (GetConVarBool(g_hCvar_DisplayCooldowns))
					{
						if (entArray[index][ent_mode] == 2)
						{
							if (entArray[index][ent_cooldowntime] > 0)
							{
								Format(buffer_temp, sizeof(buffer_temp), "%s[%d]: %N\n", entArray[index][ent_shortname], entArray[index][ent_cooldowntime], entArray[index][ent_ownerid]);
							}
							else
							{
								Format(buffer_temp, sizeof(buffer_temp), "%s[%s]: %N\n", entArray[index][ent_shortname], "R", entArray[index][ent_ownerid]);
							}
						}
						else if (entArray[index][ent_mode] == 3)
						{
							if (entArray[index][ent_uses] < entArray[index][ent_maxuses])
							{
								Format(buffer_temp, sizeof(buffer_temp), "%s[%d/%d]: %N\n", entArray[index][ent_shortname], entArray[index][ent_uses], entArray[index][ent_maxuses], entArray[index][ent_ownerid]);
							}
							else
							{
								Format(buffer_temp, sizeof(buffer_temp), "%s[%s]: %N\n", entArray[index][ent_shortname], "D", entArray[index][ent_ownerid]);
							}
						}
						else if (entArray[index][ent_mode] == 4)
						{
							if (entArray[index][ent_cooldowntime] > 0)
							{
								Format(buffer_temp, sizeof(buffer_temp), "%s[%d]: %N\n", entArray[index][ent_shortname], entArray[index][ent_cooldowntime], entArray[index][ent_ownerid]);
							}
							else
							{
								if (entArray[index][ent_uses] < entArray[index][ent_maxuses])
								{
									Format(buffer_temp, sizeof(buffer_temp), "%s[%d/%d]: %N\n", entArray[index][ent_shortname], entArray[index][ent_uses], entArray[index][ent_maxuses], entArray[index][ent_ownerid]);
								}
								else
								{
									Format(buffer_temp, sizeof(buffer_temp), "%s[%s]: %N\n", entArray[index][ent_shortname], "D", entArray[index][ent_ownerid]);
								}
							}
						}
						else if (entArray[index][ent_mode] == 5)
						{
							if (entArray[index][ent_cooldowntime] > 0)
							{
								Format(buffer_temp, sizeof(buffer_temp), "%s[%d]: %N\n", entArray[index][ent_shortname], entArray[index][ent_cooldowntime], entArray[index][ent_ownerid]);
							}
							else
							{
								Format(buffer_temp, sizeof(buffer_temp), "%s[%d/%d]: %N\n", entArray[index][ent_shortname], entArray[index][ent_uses], entArray[index][ent_maxuses], entArray[index][ent_ownerid]);
							}
						}
						else
						{
							Format(buffer_temp, sizeof(buffer_temp), "%s[%s]: %N\n", entArray[index][ent_shortname], "N/A", entArray[index][ent_ownerid]);
						}
					}
					else
					{
						Format(buffer_temp, sizeof(buffer_temp), "%s: %N\n", entArray[index][ent_shortname], entArray[index][ent_ownerid]);
					}

					if (strlen(buffer_temp) + strlen(buffer_teamtext[GetClientTeam(entArray[index][ent_ownerid])]) <= sizeof(buffer_teamtext[]))
					{
						StrCat(buffer_teamtext[GetClientTeam(entArray[index][ent_ownerid])], sizeof(buffer_teamtext[]), buffer_temp);
					}
				}
			}

			for (new ply = 1; ply <= MaxClients; ply++)
			{
				if (IsClientConnected(ply) && IsClientInGame(ply))
				{
					if (g_bDisplay[ply])
					{
						new String:buffer_text[250];

						for (new teamid = 0; teamid < sizeof(buffer_teamtext); teamid++)
						{
							if (!GetConVarBool(g_hCvar_ModeTeamOnly) || (GetConVarBool(g_hCvar_ModeTeamOnly) && GetClientTeam(ply) == teamid || !IsPlayerAlive(ply) || CheckCommandAccess(ply, "entWatch_chat", ADMFLAG_CHAT)))
							{
								if (strlen(buffer_teamtext[teamid]) + strlen(buffer_text) <= sizeof(buffer_text))
								{
									StrCat(buffer_text, sizeof(buffer_text), buffer_teamtext[teamid]);
								}
							}
						}

						new Handle:hBuffer = StartMessageOne("KeyHintText", ply);
						BfWriteByte(hBuffer, 1);
						BfWriteString(hBuffer, buffer_text);
						EndMessage();
					}
				}
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Calculate cooldown time
//----------------------------------------------------------------------------------------------------
public Action:Timer_Cooldowns(Handle:timer)
{
	if (g_bConfigLoaded && !g_bRoundTransition)
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_cooldowntime] >= 0)
			{
				entArray[index][ent_cooldowntime]--;
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Toggle HUD
//----------------------------------------------------------------------------------------------------
public Action:Command_ToggleHUD(client, args)
{
	if (AreClientCookiesCached(client))
	{
		if (g_bDisplay[client])
		{
			CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "display disabled");
			SetClientCookie(client, g_hCookie_Display, "0");
			g_bDisplay[client] = false;
		}
		else
		{
			CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "display enabled");
			SetClientCookie(client, g_hCookie_Display, "1");
			g_bDisplay[client] = true;
		}
	}
	else
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "cookies loading");
	}

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Check status
//----------------------------------------------------------------------------------------------------
public Action:Command_Status(client, args)
{
	if (args > 0 && CheckCommandAccess(client, "", ADMFLAG_BAN, true))
	{
		decl String:Arguments[64];
		decl String:CStatus[64];
		new target = -1;
		GetCmdArg(1, Arguments, sizeof(Arguments));
		target = FindTarget(client, Arguments);

		if (target == -1)
		{
			return Plugin_Handled;
		}

		if (AreClientCookiesCached(target))
		{
			GetClientCookie(target, g_hCookie_RestrictedLength, CStatus, sizeof(CStatus));

			if (g_bRestricted[target])
			{
				CReplyToCommand(client, "\x07%s[entWatch]\x07%s \x07%s%N\x07%s is temporarily restricted.", color_tag, color_warning, color_name, target, color_warning);

				return Plugin_Handled;
			}

			if (StringToInt(CStatus) == 0)
			{
				CReplyToCommand(client, "\x07%s[entWatch]\x07%s \x07%s%N\x07%s is not restricted.", color_tag, color_warning, color_name, target, color_warning);

				return Plugin_Handled;
			}
			else if (StringToInt(CStatus) == 1)
			{
				CReplyToCommand(client, "\x07%s[entWatch]\x07%s \x07%s%N\x07%s is permanently restricted.", color_tag, color_warning, color_name, target, color_warning);

				return Plugin_Handled;
			}
			else if (StringToInt(CStatus) <= GetTime())
			{
				CReplyToCommand(client, "\x07%s[entWatch]\x07%s \x07%s%N\x07%s is not restricted.", color_tag, color_warning, color_name, target, color_warning);
				g_iRestrictedLength[target] = 0;
				SetClientCookie(target, g_hCookie_RestrictedLength, "0");

				return Plugin_Handled;
			}

			decl String:RemainingTime[128];
			decl String:FRemainingTime[128];
			GetClientCookie(target, g_hCookie_RestrictedLength, RemainingTime, sizeof(RemainingTime));
			new tstamp = (StringToInt(RemainingTime) - GetTime());

			new days = (tstamp / 86400);
			new hours = ((tstamp / 3600) % 24);
			new minutes = ((tstamp / 60) % 60);
			new seconds = (tstamp % 60);

			if (tstamp > 86400)
				Format(FRemainingTime, sizeof(FRemainingTime), "%d %s, %d %s, %d %s, %d %s", days, SingularOrMultiple(days)?"Days":"Day", hours, SingularOrMultiple(hours)?"Hours":"Hour", minutes, SingularOrMultiple(minutes)?"Minutes":"Minute", seconds, SingularOrMultiple(seconds)?"Seconds":"Second");
			else if (tstamp > 3600)
				Format(FRemainingTime, sizeof(FRemainingTime), "%d %s, %d %s, %d %s", hours, SingularOrMultiple(hours)?"Hours":"Hour", minutes, SingularOrMultiple(minutes)?"Minutes":"Minute", seconds, SingularOrMultiple(seconds)?"Seconds":"Second");
			else if (tstamp > 60)
				Format(FRemainingTime, sizeof(FRemainingTime), "%d %s, %d %s", minutes, SingularOrMultiple(minutes)?"Minutes":"Minute", seconds, SingularOrMultiple(seconds)?"Seconds":"Second");
			else
				Format(FRemainingTime, sizeof(FRemainingTime), "%d %s", seconds, SingularOrMultiple(seconds)?"Seconds":"Second");

			CReplyToCommand(client, "\x07%s[entWatch]\x07%s \x07%s%N\x07%s is restricted for another: \x04%s", color_tag, color_warning, color_name, target, color_warning, FRemainingTime);

			return Plugin_Handled;
		}
		else
		{
			CReplyToCommand(client, "\x07%s[entWatch]\x07%s \x07%s%N\x07%s's cookies haven't loaded yet.", color_tag, color_warning, color_name, target, color_warning);
			return Plugin_Handled;
		}
	}

	if (g_bRestricted[client])
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "status restricted");

		return Plugin_Handled;
	}

	if (AreClientCookiesCached(client))
	{
		if (g_iRestrictedLength[client] >= 1)
		{
			if (g_iRestrictedLength[client] != 1 && g_iRestrictedLength[client] != 0 && g_iRestrictedLength[client] <= GetTime())
			{
				g_iRestrictedLength[client] = 0;
				SetClientCookie(client, g_hCookie_RestrictedLength, "0");

				CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "status unrestricted");
				return Plugin_Handled;
			}

			if (g_iRestrictedLength[client] == 1)
			{
				CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t \x04(permanent)", color_tag, color_warning, "status restricted");

				return Plugin_Handled;
			}
			else if (g_iRestrictedLength[client] > 1)
			{
				decl String:RemainingTime[128];
				decl String:FRemainingTime[128];
				GetClientCookie(client, g_hCookie_RestrictedLength, RemainingTime, sizeof(RemainingTime));
				new tstamp = (StringToInt(RemainingTime) - GetTime());

				new days = (tstamp / 86400);
				new hours = ((tstamp / 3600) % 24);
				new minutes = ((tstamp / 60) % 60);
				new seconds = (tstamp % 60);

				if (tstamp > 86400)
					Format(FRemainingTime, sizeof(FRemainingTime), "%d %s, %d %s, %d %s, %d %s", days, SingularOrMultiple(days)?"Days":"Day", hours, SingularOrMultiple(hours)?"Hours":"Hour", minutes, SingularOrMultiple(minutes)?"Minutes":"Minute", seconds, SingularOrMultiple(seconds)?"Seconds":"Second");
				else if (tstamp > 3600)
					Format(FRemainingTime, sizeof(FRemainingTime), "%d %s, %d %s, %d %s", hours, SingularOrMultiple(hours)?"Hours":"Hour", minutes, SingularOrMultiple(minutes)?"Minutes":"Minute", seconds, SingularOrMultiple(seconds)?"Seconds":"Second");
				else if (tstamp > 60)
					Format(FRemainingTime, sizeof(FRemainingTime), "%d %s, %d %s", minutes, SingularOrMultiple(minutes)?"Minutes":"Minute", seconds, SingularOrMultiple(seconds)?"Seconds":"Second");
				else
					Format(FRemainingTime, sizeof(FRemainingTime), "%d %s", seconds, SingularOrMultiple(seconds)?"Seconds":"Second");

				CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t \x04(%s)", color_tag, color_warning, "status restricted", FRemainingTime);

				return Plugin_Handled;
			}

			CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "status restricted");
		}
		else
		{
			CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "status unrestricted");
		}
	}
	else
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "cookies loading");
	}

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Ban a client
//----------------------------------------------------------------------------------------------------
public Action:Command_Restrict(client, args)
{
	if (GetCmdArgs() < 1)
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%sUsage: sm_eban <target>", color_tag, color_warning);
		return Plugin_Handled;
	}

	new String:target_argument[64];
	GetCmdArg(1, target_argument, sizeof(target_argument));

	new target = -1;
	if ((target = FindTarget(client, target_argument, true)) == -1)
	{
		return Plugin_Handled;
	}

	if (GetCmdArgs() > 1)
	{
		decl String:sLen[64];
		decl String:Flength[64];
		GetCmdArg(2, sLen, sizeof(sLen));

		Format(Flength, sizeof(Flength), "%d", GetTime() + (StringToInt(sLen) * 60));

		if (StringToInt(sLen) == 0)
		{
			EBanClient(target, "1", client);

			return Plugin_Handled;
		}
		else if (StringToInt(sLen) > 0)
		{
			EBanClient(target, Flength, client);
		}

		return Plugin_Handled;
	}

	EBanClient(target, "0", client);

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Lists the clients that are currently on the server and banned
//----------------------------------------------------------------------------------------------------
public Action:Command_EBanlist(client, args)
{
	decl String:sBuff[4096];
	new bool:bFirst = true;
	Format(sBuff, sizeof(sBuff), "No players found.");

	for (new i = 1; i < MaxClients + 1; i++)
	{
		if (!IsClientInGame(i))
			continue;

		if (AreClientCookiesCached(i))
		{
			decl String:sBanLen[32];
			GetClientCookie(i, g_hCookie_RestrictedLength, sBanLen, sizeof(sBanLen));
			new iBanLen = StringToInt(sBanLen);

			if ((iBanLen != 0 && iBanLen >= GetTime()) || iBanLen == 1)
			{
				if (bFirst)
				{
					bFirst = false;
					Format(sBuff, sizeof(sBuff), "");
				}
				else
				{
					Format(sBuff, sizeof(sBuff), "%s, ", sBuff);
				}

				new iUserID = GetClientUserId(i);
				Format(sBuff, sizeof(sBuff), "%s%N (#%i)", sBuff, i, iUserID);
			}
		}
		else if (g_bRestricted[i])
		{
			if (bFirst)
			{
				bFirst = false;
				Format(sBuff, sizeof(sBuff), "");
			}
			else
			{
				Format(sBuff, sizeof(sBuff), "%s, ", sBuff);
			}

			new iUserID = GetClientUserId(i);
			Format(sBuff, sizeof(sBuff), "%s%N (#%i)", sBuff, i, iUserID);
		}
	}

	CReplyToCommand(client, "\x07%s[entWatch]\x07%s Currently e-banned: \x07%s%s", color_tag, color_warning, color_name, sBuff);
	Format(sBuff, sizeof(sBuff), "");

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Unban a client
//----------------------------------------------------------------------------------------------------
public Action:Command_Unrestrict(client, args)
{
	if (GetCmdArgs() < 1)
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%sUsage: sm_eunban <target>", color_tag, color_warning);
		return Plugin_Handled;
	}

	new String:target_argument[64];
	GetCmdArg(1, target_argument, sizeof(target_argument));

	new target = -1;
	if ((target = FindTarget(client, target_argument, true)) == -1)
	{
		return Plugin_Handled;
	}

	EUnbanClient(target, client);

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Transfer a special weapon from a client to another
//----------------------------------------------------------------------------------------------------
public Action:Command_Transfer(client, args)
{
	if (GetCmdArgs() < 2)
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%sUsage: sm_etransfer <owner> <receiver>", color_tag, color_warning);

		return Plugin_Handled;
	}

	new bool:bFoundWeapon = false;
	new iEntityIndex = -1
	new iWeaponCount = 0;
	new target = -1;
	new receiver = -1;

	new String:target_argument[64];
	GetCmdArg(1, target_argument, sizeof(target_argument));

	new String:receiver_argument[64];
	GetCmdArg(2, receiver_argument, sizeof(receiver_argument));

	if ((receiver = FindTarget(client, receiver_argument, false)) == -1)
		return Plugin_Handled;

	if (g_bConfigLoaded && !g_bRoundTransition)
	{
		if (target_argument[0] == '$')
		{
			strcopy(target_argument, sizeof(target_argument), target_argument[1]);

			for (new i = 0; i < entArraySize; i++)
			{
				if (StrEqual(target_argument, entArray[i][ent_name], false) || StrEqual(target_argument, entArray[i][ent_shortname], false))
				{

					iWeaponCount++;
					bFoundWeapon = true;
					iEntityIndex = i;
				}
			}
		}
		else
		{
			target = FindTarget(client, target_argument, false)

			if (target != -1)
			{
				if (GetClientTeam(target) != GetClientTeam(receiver))
				{
					CPrintToChat(client, "\x07%s[entWatch] \x07%sThe receivers team differs from the targets team.", color_tag, color_warning);
					return Plugin_Handled;
				}

				for (new index = 0; index < entArraySize; index++)
				{
					if (entArray[index][ent_ownerid] != -1)
					{
						if (entArray[index][ent_ownerid] == target)
						{
							if (entArray[index][ent_allowtransfer])
							{
								if (IsValidEdict(entArray[index][ent_weaponid]))
								{
									new String:buffer_classname[64];
									GetEdictClassname(entArray[index][ent_weaponid], buffer_classname, sizeof(buffer_classname));

									CS_DropWeapon(target, entArray[index][ent_weaponid], false);
									GivePlayerItem(target, buffer_classname);

									if (entArray[index][ent_chat])
									{
										entArray[index][ent_chat] = false;
										FixedEquipPlayerWeapon(receiver, entArray[index][ent_weaponid]);
										entArray[index][ent_chat] = true;
									}
									else
									{
										FixedEquipPlayerWeapon(receiver, entArray[index][ent_weaponid]);
									}

									CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%stransfered all items from \x07%s%N \x07%sto \x07%s%N", color_tag, color_name, client, color_warning, color_name, target, color_warning, color_name, receiver);

									LogAction(client, target, "\"%L\" transfered all items from \"%L\" to \"%L\"", client, target, receiver);

									return Plugin_Handled;
								}
							}
						}
					}
				}
			}
			else
			{
				return Plugin_Handled;
			}
		}
	}

	if (iWeaponCount > 1)
	{
		new Handle:hEdictMenu = CreateMenu(EdictMenu_Handler);
		new String:sMenuTemp[64];
		new String:sIndexTemp[16];
		new iHeldCount = 0;
		SetMenuTitle(hEdictMenu, "[entWatch] Edict targets:");

		for (new i = 0; i < entArraySize; i++)
		{
			if (StrEqual(target_argument, entArray[i][ent_name], false) || StrEqual(target_argument, entArray[i][ent_shortname], false))
			{
				if (entArray[i][ent_allowtransfer])
				{
					if (entArray[i][ent_ownerid] != -1)
					{
						IntToString(i, sIndexTemp, sizeof(sIndexTemp));
						Format(sMenuTemp, sizeof(sMenuTemp), "%s | %N (#%i)", entArray[i][ent_name], entArray[i][ent_ownerid], GetClientUserId(entArray[i][ent_ownerid]));
						AddMenuItem(hEdictMenu, sIndexTemp, sMenuTemp, ITEMDRAW_DEFAULT);
						iHeldCount++;
					}
					/*else //not a good idea
					{
						IntToString(i, sIndexTemp, sizeof(sIndexTemp));
						Format(sMenuTemp, sizeof(sMenuTemp), "%s", entArray[i][ent_name]);
						AddMenuItem(hEdictMenu, sIndexTemp, sMenuTemp, ITEMDRAW_DEFAULT);
					}*/
				}
			}
		}

		if (iHeldCount == 1)
		{
			iEntityIndex = StringToInt(sIndexTemp);

			if (entArray[iEntityIndex][ent_allowtransfer])
			{
				if (entArray[iEntityIndex][ent_ownerid] != -1)
				{
					if (IsValidEdict(entArray[iEntityIndex][ent_weaponid]))
					{
						new iCurOwner = entArray[iEntityIndex][ent_ownerid];

						if (GetClientTeam(receiver) != GetClientTeam(iCurOwner))
						{
							CPrintToChat(client, "\x07%s[entWatch] \x07%sThe receivers team differs from the targets team.", color_tag, color_warning);
							CloseHandle(hEdictMenu);
							return Plugin_Handled;
						}

						new String:buffer_classname[64];
						GetEdictClassname(entArray[iEntityIndex][ent_weaponid], buffer_classname, sizeof(buffer_classname))

						CS_DropWeapon(iCurOwner, entArray[iEntityIndex][ent_weaponid], false);
						GivePlayerItem(iCurOwner, buffer_classname);

						if (entArray[iEntityIndex][ent_chat])
						{
							entArray[iEntityIndex][ent_chat] = false;
							FixedEquipPlayerWeapon(receiver, entArray[iEntityIndex][ent_weaponid]);
							entArray[iEntityIndex][ent_chat] = true;
						}
						else
						{
							FixedEquipPlayerWeapon(receiver, entArray[iEntityIndex][ent_weaponid]);
						}

						CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%stransfered all items from \x07%s%N \x07%sto \x07%s%N", color_tag, color_name, client, color_warning, color_name, iCurOwner, color_warning, color_name, receiver);

						LogAction(client, iCurOwner, "\"%L\" transfered all items from \"%L\" to \"%L\"", client, iCurOwner, receiver);
					}
				}
				else
				{
					CPrintToChat(client, "\x07%s[entWatch] \x07%sTarget is not valid.", color_tag, color_warning);
				}
			}

			CloseHandle(hEdictMenu);
		}
		else if (iHeldCount >= 2)
		{
			g_iAdminMenuTarget[client] = receiver;
			DisplayMenu(hEdictMenu, client, MENU_TIME_FOREVER);
		}
		else
		{
			CPrintToChat(client, "\x07%s[entWatch] \x07%sNo one is currently holding that item.", color_tag, color_warning);
			CloseHandle(hEdictMenu);
		}
	}
	else
	{
		if (entArray[iEntityIndex][ent_allowtransfer])
		{
			if (entArray[iEntityIndex][ent_ownerid] != -1)
			{
				if (IsValidEdict(entArray[iEntityIndex][ent_weaponid]))
				{
					new iCurOwner = entArray[iEntityIndex][ent_ownerid];

					new String:buffer_classname[64];
					GetEdictClassname(entArray[iEntityIndex][ent_weaponid], buffer_classname, sizeof(buffer_classname))

					CS_DropWeapon(iCurOwner, entArray[iEntityIndex][ent_weaponid], false);
					GivePlayerItem(iCurOwner, buffer_classname);

					if (entArray[iEntityIndex][ent_chat])
					{
						entArray[iEntityIndex][ent_chat] = false;
						FixedEquipPlayerWeapon(receiver, entArray[iEntityIndex][ent_weaponid]);
						entArray[iEntityIndex][ent_chat] = true;
					}
					else
					{
						FixedEquipPlayerWeapon(receiver, entArray[iEntityIndex][ent_weaponid]);
					}

					bFoundWeapon = true;

					CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%stransfered all items from \x07%s%N \x07%sto \x07%s%N", color_tag, color_name, client, color_warning, color_name, iCurOwner, color_warning, color_name, receiver);

					LogAction(client, iCurOwner, "\"%L\" transfered all items from \"%L\" to \"%L\"", client, iCurOwner, receiver);
				}
			}
			else
			{
				new entity = Entity_GetEntityFromHammerID(entArray[iEntityIndex][ent_hammerid]);

				if (entArray[iEntityIndex][ent_chat])
				{
					entArray[iEntityIndex][ent_chat] = false;
					FixedEquipPlayerWeapon(receiver, entity);
					entArray[iEntityIndex][ent_chat] = true;
				}
				else
				{
					FixedEquipPlayerWeapon(receiver, entity);
				}

				bFoundWeapon = true;

				CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%stransfered \x07%s%s \x07%sto \x07%s%N", color_tag, color_name, client, color_warning, entArray[iEntityIndex][ent_color], entArray[iEntityIndex][ent_name], color_warning, color_name, receiver);

				LogAction(client, -1, "\"%L\" transfered \"%s\" to \"%L\"", client, entArray[iEntityIndex][ent_name], receiver);
			}
		}
	}

	if (!bFoundWeapon)
		CPrintToChat(client, "\x07%s[entWatch] \x07%sInvalid item name.", color_tag, color_warning);

	return Plugin_Handled;
}

public EdictMenu_Handler(Handle:hEdictMenu, MenuAction:hAction, iParam1, iParam2)
{
	switch (hAction)
	{
		case MenuAction_End:
			CloseHandle(hEdictMenu);

		case MenuAction_Select:
		{
			new String:sSelected[32];
			GetMenuItem(hEdictMenu, iParam2, sSelected, sizeof(sSelected));
			new iEntityIndex = StringToInt(sSelected);
			new receiver = g_iAdminMenuTarget[iParam1];

			if (receiver == 0)
			{
				CPrintToChat(iParam1, "\x07%s[entWatch] \x07%sReceiver is not valid anymore.", color_tag, color_warning);
				return;
			}

			if (entArray[iEntityIndex][ent_allowtransfer])
			{
				if (entArray[iEntityIndex][ent_ownerid] != -1)
				{
					if (IsValidEdict(entArray[iEntityIndex][ent_weaponid]))
					{
						new iCurOwner = entArray[iEntityIndex][ent_ownerid];

						if (GetClientTeam(receiver) != GetClientTeam(iCurOwner))
						{
							CPrintToChat(iParam1, "\x07%s[entWatch] \x07%sThe receivers team differs from the targets team.", color_tag, color_warning);
							return;
						}

						new String:buffer_classname[64];
						GetEdictClassname(entArray[iEntityIndex][ent_weaponid], buffer_classname, sizeof(buffer_classname))

						CS_DropWeapon(iCurOwner, entArray[iEntityIndex][ent_weaponid], false);
						GivePlayerItem(iCurOwner, buffer_classname);

						if (entArray[iEntityIndex][ent_chat])
						{
							entArray[iEntityIndex][ent_chat] = false;
							FixedEquipPlayerWeapon(receiver, entArray[iEntityIndex][ent_weaponid]);
							entArray[iEntityIndex][ent_chat] = true;
						}
						else
						{
							FixedEquipPlayerWeapon(receiver, entArray[iEntityIndex][ent_weaponid]);
						}

						CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%stransfered all items from \x07%s%N \x07%sto \x07%s%N", color_tag, color_name, iParam1, color_warning, color_name, iCurOwner, color_warning, color_name, receiver);

						LogAction(iParam1, iCurOwner, "\"%L\" transfered all items from \"%L\" to \"%L\"", iParam1, iCurOwner, receiver);
					}
				}
				else
				{
					CPrintToChat(iParam1, "\x07%s[entWatch] \x07%sItem is not valid anymore.", color_tag, color_warning);
				}
			}
		}
	}
}

public Action:Command_DebugArray(client, args)
{
	if (g_bConfigLoaded && !g_bRoundTransition)
	{
		for (new i = 0; i < entArraySize; i++)
		{
			CPrintToChat(client, "\x07%s[entWatch] \x07%sInfo at \x07%sindex \x04%i\x07%s: \x07%sWeaponID \x04%i\x07%s | \x07%sOwnerID \x04%i\x07%s | \x07%sHammerID \x04%i\x07%s | \x07%sName\x07%s \"\x04%s\x07%s\" | \x07%sShortName\x07%s \"\x04%s\x07%s\"", color_tag, color_warning, color_pickup, i, color_warning, color_pickup, entArray[i][ent_weaponid], color_warning, color_pickup, entArray[i][ent_ownerid], color_warning, color_pickup, entArray[i][ent_hammerid], color_warning, color_pickup, color_warning, entArray[i][ent_name], color_warning, color_pickup, color_warning, entArray[i][ent_shortname], color_warning);
		}
	}
	else
	{
		CPrintToChat(client, "\x07%s[entWatch] \x07%sConfig file has not yet loaded or the round is transitioning.", color_tag, color_warning);
	}

	return Plugin_Handled;
}


CleanData()
{
	for (new index = 0; index < entArraySize; index++)
	{
		Format(entArray[index][ent_name],         32, "");
		Format(entArray[index][ent_shortname],    32, "");
		Format(entArray[index][ent_color],        32, "");
		Format(entArray[index][ent_buttonclass],  32, "");
		Format(entArray[index][ent_filtername],   32, "");
		entArray[index][ent_hasfiltername]  = false;
		entArray[index][ent_blockpickup]    = false;
		entArray[index][ent_allowtransfer]  = false;
		entArray[index][ent_forcedrop]      = false;
		entArray[index][ent_chat]           = false;
		entArray[index][ent_hud]            = false;
		entArray[index][ent_hammerid]       = -1;
		entArray[index][ent_weaponid]       = -1;
		entArray[index][ent_buttonid]       = -1;
		entArray[index][ent_ownerid]        = -1;
		entArray[index][ent_mode]           = 0;
		entArray[index][ent_uses]           = 0;
		entArray[index][ent_maxuses]        = 0;
		entArray[index][ent_cooldown]       = 0;
		entArray[index][ent_cooldowntime]   = -1;
	}

	for (new index = 0; index < triggerSize; index++)
	{
		triggerArray[index] = 0;
	}

	entArraySize = 0;
	triggerSize = 0;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Load color settings
//----------------------------------------------------------------------------------------------------
stock LoadColors()
{
	new Handle:hKeyValues = CreateKeyValues("colors");
	new String:buffer_config[128];
	new String:buffer_path[PLATFORM_MAX_PATH];
	new String:buffer_temp[16];

	GetConVarString(g_hCvar_ConfigColor, buffer_config, sizeof(buffer_config));
	Format(buffer_path, sizeof(buffer_path), "cfg/sourcemod/entwatch/colors/%s.cfg", buffer_config);
	FileToKeyValues(hKeyValues, buffer_path);

	KvRewind(hKeyValues);

	KvGetString(hKeyValues, "color_tag", buffer_temp, sizeof(buffer_temp));
	Format(color_tag, sizeof(color_tag), "%s", buffer_temp);

	KvGetString(hKeyValues, "color_name", buffer_temp, sizeof(buffer_temp));
	Format(color_name, sizeof(color_name), "%s", buffer_temp);

	KvGetString(hKeyValues, "color_steamid", buffer_temp, sizeof(buffer_temp));
	Format(color_steamid, sizeof(color_steamid), "%s", buffer_temp);

	KvGetString(hKeyValues, "color_use", buffer_temp, sizeof(buffer_temp));
	Format(color_use, sizeof(color_use), "%s", buffer_temp);

	KvGetString(hKeyValues, "color_pickup", buffer_temp, sizeof(buffer_temp));
	Format(color_pickup, sizeof(color_pickup), "%s", buffer_temp);

	KvGetString(hKeyValues, "color_drop", buffer_temp, sizeof(buffer_temp));
	Format(color_drop, sizeof(color_drop), "%s", buffer_temp);

	KvGetString(hKeyValues, "color_disconnect", buffer_temp, sizeof(buffer_temp));
	Format(color_disconnect, sizeof(color_disconnect), "%s", buffer_temp);

	KvGetString(hKeyValues, "color_death", buffer_temp, sizeof(buffer_temp));
	Format(color_death, sizeof(color_death), "%s", buffer_temp);

	KvGetString(hKeyValues, "color_warning", buffer_temp, sizeof(buffer_temp));
	Format(color_warning, sizeof(color_warning), "%s", buffer_temp);

	CloseHandle(hKeyValues);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Load configurations
//----------------------------------------------------------------------------------------------------
stock LoadConfig()
{
	new Handle:hKeyValues = CreateKeyValues("entities");
	new String:buffer_map[128];
	new String:buffer_path[PLATFORM_MAX_PATH];
	new String:buffer_path_override[PLATFORM_MAX_PATH];
	new String:buffer_temp[32];
	new buffer_amount;

	GetCurrentMap(buffer_map, sizeof(buffer_map));
	Format(buffer_path, sizeof(buffer_path), "cfg/sourcemod/entwatch/maps/%s.cfg", buffer_map);
	Format(buffer_path_override, sizeof(buffer_path_override), "cfg/sourcemod/entwatch/maps/%s_override.cfg", buffer_map);
	if (FileExists(buffer_path_override))
	{
		FileToKeyValues(hKeyValues, buffer_path_override);
		LogMessage("Loading %s", buffer_path_override);
	}
	else
	{
		FileToKeyValues(hKeyValues, buffer_path);
		LogMessage("Loading %s", buffer_path);
	}

	KvRewind(hKeyValues);
	if (KvGotoFirstSubKey(hKeyValues))
	{
		g_bConfigLoaded = true;
		entArraySize = 0;
		triggerSize = 0;

		do
		{
			KvGetString(hKeyValues, "maxamount", buffer_temp, sizeof(buffer_temp));
			buffer_amount = StringToInt(buffer_temp);

			for (new i = 0; i < buffer_amount; i++)
			{
				KvGetString(hKeyValues, "name", buffer_temp, sizeof(buffer_temp));
				Format(entArray[entArraySize][ent_name], 32, "%s", buffer_temp);

				KvGetString(hKeyValues, "shortname", buffer_temp, sizeof(buffer_temp));
				Format(entArray[entArraySize][ent_shortname], 32, "%s", buffer_temp);

				KvGetString(hKeyValues, "color", buffer_temp, sizeof(buffer_temp));
				Format(entArray[entArraySize][ent_color], 32, "%s", buffer_temp);

				KvGetString(hKeyValues, "buttonclass", buffer_temp, sizeof(buffer_temp));
				Format(entArray[entArraySize][ent_buttonclass], 32, "%s", buffer_temp);

				KvGetString(hKeyValues, "filtername", buffer_temp, sizeof(buffer_temp));
				Format(entArray[entArraySize][ent_filtername], 32, "%s", buffer_temp);

				KvGetString(hKeyValues, "hasfiltername", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_hasfiltername] = StrEqual(buffer_temp, "true", false);

				KvGetString(hKeyValues, "blockpickup", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_blockpickup] = StrEqual(buffer_temp, "true", false);

				KvGetString(hKeyValues, "allowtransfer", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_allowtransfer] = StrEqual(buffer_temp, "true", false);

				KvGetString(hKeyValues, "forcedrop", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_forcedrop] = StrEqual(buffer_temp, "true", false);

				KvGetString(hKeyValues, "chat", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_chat] = StrEqual(buffer_temp, "true", false);

				KvGetString(hKeyValues, "hud", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_hud] = StrEqual(buffer_temp, "true", false);

				KvGetString(hKeyValues, "hammerid", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_hammerid] = StringToInt(buffer_temp);

				KvGetString(hKeyValues, "mode", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_mode] = StringToInt(buffer_temp);

				KvGetString(hKeyValues, "maxuses", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_maxuses] = StringToInt(buffer_temp);

				KvGetString(hKeyValues, "cooldown", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_cooldown] = StringToInt(buffer_temp);

				KvGetString(hKeyValues, "trigger", buffer_temp, sizeof(buffer_temp));

				new tindex = StringToInt(buffer_temp);
				if(tindex)
				{
					triggerArray[triggerSize] = tindex;
					triggerSize++;
				}

				entArraySize++;
			}
		}
		while (KvGotoNextKey(hKeyValues));
	}
	else
	{
		g_bConfigLoaded = false;

		LogMessage("Could not load %s", buffer_path);
	}

	CloseHandle(hKeyValues);
}

public Action:Command_ReloadConfig(client,args)
{
	CleanData();
	LoadColors();
	LoadConfig();

	return Plugin_Handled;
}

public OnEntityCreated(entity, const String:classname[])
{
    if (triggerSize > 0 && StrContains(classname, "trigger_", false) != -1 && IsValidEntity(entity))
	{
		SDKHook(entity, SDKHook_Spawn, OnEntitySpawned);
	}
}

public OnEntitySpawned(entity)
{
	decl String:classname[32];
	if(Entity_GetClassName(entity, classname, 32))
	{
		if (IsValidEntity(entity) && StrContains(classname, "trigger_", false) != -1)
		{
			new hid = Entity_GetHammerID(entity);
			for (new index = 0; index < triggerSize; index++)
			{
				if(hid == triggerArray[index])
				{
					SDKHook(entity, SDKHook_Touch, OnTrigger);
					SDKHook(entity, SDKHook_EndTouch, OnTrigger);
					SDKHook(entity, SDKHook_StartTouch, OnTrigger);
				}
			}
		}
	}
}

public Action:Command_Cooldown(client, args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_setcooldown <hammerid> <cooldown>");
		return Plugin_Handled;
	}

	new String:hid[32],String:cooldown[10]

	GetCmdArg(1, hid, sizeof(hid));
	GetCmdArg(2, cooldown, sizeof(cooldown));

	new hammerid = StringToInt(hid);

	for (new index = 0; index < entArraySize; index++)
	{
		if (entArray[index][ent_hammerid] == hammerid)
		{
			entArray[index][ent_cooldown] = StringToInt(cooldown);
		}
	}

	return Plugin_Handled;
}

public Action:OnTrigger(entity, other)
{
    if (MaxClients >= other && 0 < other) {
        if (IsClientConnected(other)) {
			if (g_bRestricted[other]) {
				return Plugin_Handled;
			}

			if (g_iRestrictedLength[other] != 1 && g_iRestrictedLength[other] != 0 && g_iRestrictedLength[other] <= GetTime())
			{
				g_iRestrictedLength[other] = 0;
				SetClientCookie(other, g_hCookie_RestrictedLength, "0");

				return Plugin_Continue;
			}

			if (g_iRestrictedLength[other] > GetTime() || g_iRestrictedLength[other] == 1)
			{
				return Plugin_Handled;
			}
        }
    }

    return Plugin_Continue;
}

bool:SingularOrMultiple(int num)
{
	if (num > 1 || num == 0)
	{
		return true;
	}

	return false;
}

public Native_IsClientBanned(Handle:hPlugin, iArgC)
{
	new client = GetNativeCell(1);

	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !AreClientCookiesCached(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client/client is not in game or client cookies are not yet loaded");
		return false;
	}

	new String:sBuff[64];
	GetClientCookie(client, g_hCookie_RestrictedLength, sBuff, sizeof(sBuff));
	new iBanLen = StringToInt(sBuff);

	if ((iBanLen != 0 && iBanLen >= GetTime()) || iBanLen == 1)
	{
		SetNativeCellRef(2, iBanLen);
		return true;
	}

	return true;
}

public Native_BanClient(Handle:hPlugin, iArgC)
{
	new client = GetNativeCell(1);
	new bool:bIsTemporary = GetNativeCell(2);
	new iBanLen = GetNativeCell(3);

	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !AreClientCookiesCached(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client/client is not in game or client cookies are not yet loaded");
		return false;
	}

	if (bIsTemporary)
	{
		EBanClient(client, "0", 0);

		return true;
	}

	if (iBanLen == 0)
	{
		EBanClient(client, "1", 0);

		return true;
	}
	else
	{
		iBanLen = GetTime() + (iBanLen * 60);

		if (iBanLen <= GetTime())
		{
			ThrowNativeError(SP_ERROR_PARAM, "Invalid ban length given");
			return false;
		}
	}

	new String:sBanLen[64];
	Format(sBanLen, sizeof(sBanLen), "%d", iBanLen);

	EBanClient(client, sBanLen, 0);

	return true;
}

public Native_UnbanClient(Handle:hPlugin, iArgC)
{
	new client = GetNativeCell(1);

	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !AreClientCookiesCached(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client/client is not in game or client cookies are not yet loaded");
		return false;
	}

	EUnbanClient(client, 0);

	return true;
}

public Native_IsSpecialItem(Handle:hPlugin, iArgC)
{
	if (!g_bConfigLoaded)
	{
		return false;
	}

	new entity = GetNativeCell(1);
	if (entity < MaxClients || !IsValidEdict(entity) || !IsValidEntity(entity))
	{
		return false;
	}

	for (new index = 0; index < entArraySize; index++)
	{
		if (entArray[index][ent_buttonid] == entity)
		{
			return true;
		}
	}

	return false;
}

public Native_HasSpecialItem(Handle:hPlugin, iArgC)
{
	if (!g_bConfigLoaded)
	{
		return false;
	}

	new client = GetNativeCell(1);

	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client/client is not in game");
		return false;
	}

	for (new index = 0; index < entArraySize; index++)
	{
		if (entArray[index][ent_ownerid] == client)
		{
			return true;
		}
	}

	return false;
}

stock FixedEquipPlayerWeapon(client, weapon)
{
	new iWeaponSlot = SDKCall(g_hGetSlot, weapon);
	new WeaponInSlot = GetPlayerWeaponSlot(client, iWeaponSlot);
	if(WeaponInSlot	!= -1)
		CS_DropWeapon(client, WeaponInSlot, false);

	if(SDKCall(g_hBumpWeapon, client, weapon))
		SDKCall(g_hOnPickedUp, weapon, client);
}
