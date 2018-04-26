/*
 * +===================================================================================+
 * | MotdMod SourceMod Plugin                                                          |
 * |===================================================================================|
 * | Authors & Contributors: lake393, thomasjosif, dgibbs, nosoop                      |
 * | Copyright © 2017 - 2018 MOTDs Network (www.motdmod.com)                           |
 * |===================================================================================|
 * | This program is free software: you can redistribute it and/or modify              |
 * | it under the terms of the GNU General Public License as published by              |
 * | the Free Software Foundation, version 3.                                          |
 * |                                                                                   |
 * | This program is distributed in the hope that it will be useful, but               |
 * | WITHOUT ANY WARRANTY; without even the implied warranty of                        |
 * | MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU                  |
 * | General Public License for more details.                                          |
 * |                                                                                   |
 * | You should have received a copy of the GNU General Public License                 |
 * | along with this program. If not, see <http://www.gnu.org/licenses/>.              |
 * +===================================================================================+
 */

#include <sourcemod>
#include <sdktools>
#include <EasyHTTP>
#include <EasyJSON>
#include <regex>
#include <md5stocks>

#include <stocksoup/datapack>
#include "vgui_cache_buster/usermessage.sp"

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "1.2.2"

// Messages
#define MSG_TAG "[MotdMod SM]"
#define MSG_ERROR_NOT_COMPATIBLE "This game is unfortunately not supported by MotdMod! Have a suggestion? Message us at https://motdmod.com/"
#define MSG_ERROR_FAILED_UPDATE "Error updating! You must manually update at https://download.motdmod.com"

#define MOTDMOD "http://motdmod.com"
#define MOTDMOD_API_URL "http://api1.motdmod.com/v1/"
#define MOTDMOD_API_MOTD "getMotd"
#define MOTDMOD_API_VERSION "updater"

#define OS_WINDOWS 1
#define OS_LINUX 2

// info stringtable key
#define INFO_PANEL_STRING "__motdmod_loading"
#define INFO_PANEL_TEXT_STRING "__motdmod_text"

/*
+==================================================================================+
| Engine_Version             Game Name                                             |
+==================================================================================+
| Engine_Unknown             Could not determine the engine version                |
| Engine_Original            Original Source Engine (used by The Ship)             |
| Engine_SourceSDK2006       Episode 1 Source Engine (second major SDK)            |
| Engine_SourceSDK2007       Orange Box Source Engine (third major SDK)            |
| Engine_Left4Dead           Left 4 Dead                                           |
| Engine_DarkMessiah         Dark Messiah Multiplayer (based on original engine)   |
| Engine_Left4Dead2          Left 4 Dead 2                                         |
| Engine_AlienSwarm          Alien Swarm (and Alien Swarm SDK)                     |
| Engine_BloodyGoodTime      Bloody Good Time                                      |
| Engine_EYE                 E.Y.E Divine Cybermancy                               |
| Engine_Portal2             Portal 2                                              |
| Engine_CSGO                Counter-Strike: Global Offensive                      |
| Engine_CSS                 Counter-Strike: Source                                |
| Engine_DOTA                Dota 2                                                |
| Engine_HL2DM               Half-Life 2  Deathmatch                               |
| Engine_DODS                Day of Defeat: Source                                 |
| Engine_TF2                 Team Fortress 2                                       |
| Engine_NuclearDawn         Nuclear Dawn                                          |
| Engine_SDK2013             Source SDK 2013                                       |
| Engine_Blade               Blade Symphony                                        |
| Engine_Insurgency          Insurgency (2013 Retail version)                      |
| Engine_Contagion           Contagion                                             |
| Engine_BlackMesa           Black Mesa Multiplayer                                |
+==================================================================================+
*/
EngineVersion g_GameEngine;

enum PluginMode
{
    PluginMode_Disabled = 0,
    PluginMode_Active, // This plugin is currently operating as the highest tier MotdMod plugin.
    PluginMode_Standby // This plugin has been superseded by a higher tier MotdMod plugin.
}

PluginMode g_PluginMode = PluginMode_Disabled;

// Booleans
bool g_bPluginUpdating, g_bPluginInitInProcess;

// Chars
char g_sAPIKey[512];
char g_sHostIP[64];
char g_sMotdUrl[512];
char g_sNoHTML[2048];
char g_sPluginMD5[256];
char g_sServerName[256];
char g_sServerOS[10];

float g_flNextAllowInfoPanelTime[MAXPLAYERS + 1];

bool g_bIsViewingMOTD[MAXPLAYERS + 1];

// Char arrays
char g_sIncompatiblePlugins[][] = {
    "m3motd.smx",
    "dynamic_motd.smx",
    "motdgd_adverts.smx",
    "popup.smx",
    "motd_text_http.smx",
    "nomotd.smx",
    "vpp_adverts.smx",
    "blockmotd.smx",
    "pinion_adverts.smx"
};

// Integers
int g_iAppID, g_iHostPort;

// Integer arrays
EngineVersion g_SupportedGames[] = {
    Engine_CSGO, Engine_CSS, Engine_TF2, Engine_DODS
};

static int g_LocalIPRanges[] =
{
    (010 << 24),                   // 10.0.0.0/8
    (127 << 24),                   // 127.0.0.0/8 (lo*)
    (172 << 24) | (016 << 16),     // 172.16.0.0/12
    (192 << 24) | (168 << 16)      // 192.168.0.0/16
};

// ConVars
ConVar g_cvMotdDisable, g_cvVerbose;

public Plugin myinfo = 
{
    name = "MotdMod",
    author = "MOTDs Network",
    description = "MotdMod SourceMod Plugin",
    version = PLUGIN_VERSION,
    url = "https://motdmod.com/"
};

// ####################################################################################
// #################################### FORWARDS ######################################
// ####################################################################################

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errormax)
{
    EasyHTTP_MarkNatives();
    
    return APLRes_Success;
}

public void OnPluginStart() 
{
    // Init
    g_GameEngine = GetEngineVersion();
    ValidateSupportedEngine();
    GetPluginMode();
    GetPluginMD5();
    
    // Load different settings / hooks
    LoadAPIKey();
    LoadVGUI();
    
    // ConVar stuff
    g_cvVerbose = CreateConVar("sm_motdmod_debug", "0.0", "1 = Enables verbose logging | 0 = disabled (default)", _, true, 0.0);
    g_cvMotdDisable = FindConVar("sv_disable_motd");
    if (g_cvMotdDisable != null)
        g_cvMotdDisable.AddChangeHook(Disable_ConVarChanged);

    // Commands
    RegServerCmd("sm_motdmod_version", Command_Version, "Displays the current version in console.");
    RegServerCmd("sm_motdmod_refresh", Command_Refresh, "Refreshes the MotdMod URL.");
    RegServerCmd("sm_motdmod_status", Command_Status, "Displays the current plugin status.");
    RegServerCmd("sm_motdmod_force_update", Command_ForceUpdate, "Forces an update check");
    
    CreateTimer(1.0, MotdMod_Init); // timer is needed for games that hibernate
    
    // Good to go!
    FinishLoad();
}

public void OnAllPluginsLoaded()
{
    CheckBadPlugins();
}

public void OnConfigsExecuted()
{
    g_cvMotdDisable = FindConVar("sv_disable_motd");
    
    // Force enable MOTDs and hook changes if available
    if(g_cvMotdDisable)
    {
        g_cvMotdDisable.AddChangeHook(Disable_ConVarChanged);
        g_cvMotdDisable.IntValue = 0;
    }
}

public Action MotdMod_Init(Handle timer)
{
    if(!g_bPluginInitInProcess)
    {
        g_bPluginInitInProcess = true;
        
        // Load server info and plugin state
        LoadServerInfo();
        MotdMod_GetPluginStatus();
    
        SetInfoPanelData(INFO_PANEL_STRING, "<!DOCTYPE html><html><body style='background:black'></body></html>");
    }
}

public void OnMapStart()
{
    CreateTimer(0.1, MotdMod_Init);
}

public void OnClientConnected(int client)
{
    g_flNextAllowInfoPanelTime[client] = GetGameTime() - (0.5 * 2);
    g_bIsViewingMOTD[client] = false;
}

// ####################################################################################
// #################################### FUNCTIONS #####################################
// ####################################################################################

/**
 * Called when the disable motd convar is changed. Re-enable.
 *
 * @param convar          Handle to the convar that was changed.
 * @param oldValue        String containing the value of the convar before it was changed.
 * @param newValue        String containing the new value of the convar.
 * @noreturn
 */
public void Disable_ConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (StringToInt(newValue) != 0)
    {
        g_cvMotdDisable.IntValue = 0;
    }
}

/**
 * Returns the version number. Eg. 1.0.0.0
 * also returns the MD5 hash of the file. Eg. 821fd877e3d5ad309abdfb902f3c93de 
 *
 * @param args          Arguments.
 * @noreturn
 */
public Action Command_Version(int args)
{
    PrintToServer(PLUGIN_VERSION);
    PrintToServer(g_sPluginMD5);
    return Plugin_Handled;
}

/**
 * Refreshes the MotdMod URL. (Contacts the web API and gets the new link based on the server.)
 *
 * @param client        Client index.
 * @param args          Arguments.
 * @noreturn
 */
public Action Command_Refresh(int args)
{
    LoadMotdUrl();
    PrintToServer("%s Refreshing the motd url....", MSG_TAG);
    
    return Plugin_Handled;
}

/**
 * Returns the status. Can only be "active", "standby" or "default"
 *
 * @param client        Client index.
 * @param args          Arguments.
 * @noreturn
 */
public Action Command_Status(int args)
{
    switch(g_PluginMode)
    {
        case PluginMode_Active:
            PrintToServer("active");
        case PluginMode_Standby:
            PrintToServer("standby");
        case PluginMode_Disabled:
            PrintToServer("disabled");
        default:
            PrintToServer("disabled");
    }
    return Plugin_Handled;
}

/**
 * Forces the plugin to check for updates
 *
 * @param client        Client index.
 * @param args          Arguments.
 * @noreturn
 */
public Action Command_ForceUpdate(int args)
{
    PrintToServer("%s Forcing plugin update check...", MSG_TAG);
    UpdateCheck();
    return Plugin_Handled;
}

/**
 * Fix player join on some games
 *
 * @param client        Client index.
 * @param command       Command name.
 * @param args          Arguments.
 * @noreturn
 */
public Action Command_OnMOTDClosed(int client, char[] command, int args)
{
    DebugMessage("OnMOTDClosed() :: init");
    if(client <= 0 || !IsClientConnected(client) || !IsClientInGame(client))
        return Plugin_Handled;
    
    if(!g_bIsViewingMOTD[client])
        return Plugin_Continue;
    
    switch(g_GameEngine)
    {
        case Engine_CSS:
            FakeClientCommand(client, "joingame");
        case Engine_DODS, Engine_NuclearDawn:
            ClientCommand(client, "changeteam");
    }
    g_bIsViewingMOTD[client] = false;
    return Plugin_Handled;
}

/**
 * Validates that the plugin will work on the specified game. If not we'll stop the plugin.
 *
 * @noreturn
 */
void ValidateSupportedEngine()
{
    bool found = false;
    for(int i = 0; i < sizeof(g_SupportedGames); i++)
        if (g_GameEngine == g_SupportedGames[i])
            found = true;
    if(!found)
        SetFailState(MSG_ERROR_NOT_COMPATIBLE);
}

/**
 * Gets the plugin mode. (Standby or Active)
 *
 * @noreturn
 */
void GetPluginMode()
{
    DebugMessage("GetPluginMode() :: init");
    
    if(FileExists("./addons/motdmod.vdf"))
    {
        g_PluginMode = PluginMode_Standby;
        DebugMessage("GetPluginMode() :: The plugin has been superseded by the motdmod vsp plugin! Going into standby mode.");
    }
    else
    {
        g_PluginMode = PluginMode_Active;
        DebugMessage("GetPluginMode() :: The plugin is currently running in sourcemod mode for managing the MOTD displays.");
    }
}

/**
 * Gets the plugin MD5.
 *
 * @noreturn
 */
void GetPluginMD5()
{
    char path[PLATFORM_MAX_PATH], pluginname[PLATFORM_MAX_PATH], md5[256];
    
    // Just incase somebody renamed the plugin :/
    GetPluginFilename(INVALID_HANDLE, pluginname, sizeof(pluginname));
    BuildPath(Path_SM, path, sizeof(path), "plugins/%s", pluginname);
    
    if(MD5_File(path, md5, sizeof(md5)))
        strcopy(g_sPluginMD5, sizeof(g_sPluginMD5), md5);
    else
    {
        Format(g_sPluginMD5, sizeof(g_sPluginMD5), "ERROR");
        LogError("Failed to get file MD5. Will not be able to update properly.");
        DebugMessage("GetPluginMD5() :: Cannot get file MD5.");
    }
}

/**
 * Checks for incompatible pluigins. If found we error out.
 *
 * @noreturn
 */
void CheckBadPlugins()
{
    // We don't play nice with other plugins that mess with MOTD's. 
    // So lets not cause any issues if we find one of them to be loaded.
    for(int i = 0; i < sizeof(g_sIncompatiblePlugins); i++)
        if (FindPluginByFile(g_sIncompatiblePlugins[i]) != null)
            SetFailState("Incompatible plugin: %s (This plugin won't work properly with it loaded.)", g_sIncompatiblePlugins[i]);
}

/**
 * Loads the API key found in /addons/sourcemod/configs/motdmod.conf into memory.
 *
 * @noreturn
 */
void LoadAPIKey()
{
    DebugMessage("LoadAPIKey() :: init");
    
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/motdmod.conf");
    
    if(!FileExists(path))
        SetFailState("Config file not found! Please re-download at https://download.motdmod.com");

    KeyValues kv = CreateKeyValues("Motdmod");
    kv.ImportFromFile(path);
    kv.GetString("API_KEY", g_sAPIKey, sizeof(g_sAPIKey), "ERROR");
    
    Format(g_sAPIKey, sizeof(g_sAPIKey), "Bearer %s", g_sAPIKey);
    DebugMessage("LoadAPIKey() :: API Key: %s", g_sAPIKey);
    
    delete kv;
    
    DebugMessage("LoadAPIKey() :: complete");
}

/**
 * Loads the VGUI Hooks and checks to see if we are using Protobuf or BitBuffer
 *
 * @noreturn
 */
void LoadVGUI()
{
    DebugMessage("LoadVGUI() :: init");
    
    // Protobuf is on newer games. But if not we must use the old bitbuffer. (Older Games)
    if(GetUserMessageType_Compat() == UM_Protobuf)
        DebugMessage("LoadVGUI() :: This engine supports Protobuf! Enabling functionality.");
    else
        DebugMessage("LoadVGUI() :: This engine does not support Protobuf! Functionality disabled.");
    
    // Make sure we can load the MOTD Panel.
    UserMsg VGUIMenu = GetUserMessageId("VGUIMenu");
    if(VGUIMenu == INVALID_MESSAGE_ID)
        SetFailState(MSG_ERROR_NOT_COMPATIBLE);
    HookUserMessage(VGUIMenu, OnVGUIMenu, true);
    if (g_GameEngine == Engine_CSS || g_GameEngine == Engine_DODS || g_GameEngine == Engine_NuclearDawn ) {
        AddCommandListener(Command_OnMOTDClosed, "closed_htmlpage");
    }
    
    DebugMessage("LoadVGUI() :: complete");
}

/**
 * Gets the server info and stores it in memory.
 *
 * @noreturn
 */
void LoadServerInfo()
{
    DebugMessage("LoadServerInfo() :: init");
    
    char buffer[256];
    
    // Get the server os
    int os = GetServerOS();
    switch(os)
    {
        case OS_WINDOWS:
            strcopy(g_sServerOS, sizeof(g_sServerOS), "win");
        case OS_LINUX:
            strcopy(g_sServerOS, sizeof(g_sServerOS), "linux");
        default: 
            strcopy(g_sServerOS, sizeof(g_sServerOS), "win");
    }
    
    // Get the Application ID: https://developer.valvesoftware.com/wiki/Steam_Application_IDs
    g_iAppID = GetAppID();
    DebugMessage("LoadServerInfo() :: App id: %d", g_iAppID);

    // Get the HostName (Server Name)
    GetConVarString(FindConVar("hostname"), g_sServerName, sizeof(g_sServerName));
    DebugMessage("LoadServerInfo() :: Hostname: %s", g_sServerName);
    
    // Get the IP. (Try a couple of times if the first method doesn't work)
    int ip = GetConVarInt(FindConVar("hostip"));
    
    // Get the Port.
    g_iHostPort = GetConVarInt(FindConVar("hostport"));
    
    bool bPendingCallback;
    
    if(!IsIPLocal(ip))
    {
        LongToIP(ip, g_sHostIP, sizeof(g_sHostIP));
        DebugMessage("LoadServerInfo() :: IP: %s", g_sHostIP);
    }
    else
    {
        DebugMessage("LoadServerInfo() :: Could not get IP from first method. Trying second.");
        
        GetConVarString(FindConVar("ip"), buffer, sizeof(buffer));
        if(StrEqual(buffer, "0", false) || IsIPLocal(IPToLong(buffer)) || StrEqual(buffer, "localhost", false))
        {
            DebugMessage("LoadServerInfo() :: Could not get IP from second method. Trying third and final.");
            if(!EasyHTTP("http://api.ipify.org/?format=txt", GET, INVALID_HANDLE, WebCallback_IPFromExternal, _))
            {
                DebugMessage("LoadServerInfo() :: ERROR: Could not call the final attempt to get IP address for the webscript! Defaulting to 127.0.0.1");
                LogError("Could not call the final attempt to get IP address for the webscript! Defaulting to 127.0.0.1");
                Format(g_sHostIP, sizeof(g_sHostIP), "127.0.0.1");
                g_bPluginInitInProcess = false;
            } else {
                bPendingCallback = true;
            }
        }
        else
        {
            strcopy(g_sHostIP, sizeof(g_sHostIP), buffer);
            DebugMessage("LoadServerInfo() :: IP: %s", g_sHostIP);
        }
    }
    
    if (!bPendingCallback) {
        OnLoadServerInfoComplete();
    }
    
    DebugMessage("LoadServerInfo() :: Port: %d", g_iHostPort);
    DebugMessage("LoadServerInfo() :: complete");
}

/**
 * Triggered when we complete the get server info process.
 *
 * @noreturn
 */
public void OnLoadServerInfoComplete() {
    LoadMotdUrl();
}

/**
 * Gets the MOTD URL from the MotdMod web API.
 *
 * @noreturn
 */
void LoadMotdUrl()
{
    DebugMessage("LoadMotdUrl() :: init");
    
    if (!strlen(g_sHostIP))
    {
        DebugMessage("LoadMotdUrl() :: External IP isn't available yet, cancelling");
        return;
    }
    
    char encodedjson[4096];
    Handle json = CreateJSON();
    
    JSONSetInteger(json, "gameType", g_iAppID);
    JSONSetString(json, "ip", g_sHostIP);
    JSONSetString(json, "name", g_sServerName);
    JSONSetInteger(json, "port", g_iHostPort);
    JSONSetString(json, "version", PLUGIN_VERSION);
    
    EncodeJSON(json, encodedjson, sizeof(encodedjson), false);
    DebugMessage("LoadMotdUrl() :: JSON: %s", encodedjson);
    
    DataPack pack = CreateDataPack();
    pack.WriteString("application/json");
    pack.WriteString(g_sAPIKey);
    
    DataPack pack2 = CreateDataPack();
    pack2.WriteString(encodedjson);
    
    char url[512];
    Format(url, sizeof(url), "%s%s", MOTDMOD_API_URL, MOTDMOD_API_MOTD);
    if(!EasyHTTP(url, POST, pack2, WebCallback_LoadMotdUrl, 0, "", pack))
    {
        SetFailState("Failed to get MOTD URL from motdmod!");
        delete pack;
        delete pack2;
        g_bPluginInitInProcess = false;
    }

    DebugMessage("LoadMotdUrl() :: complete");
}

/**
 * Prints the welcome / loaded message.
 *
 * @noreturn
 */
void FinishLoad()
{
    PrintToServer("+--------------------------------------------------------------------------");
    PrintToServer("| MotdMod - Sourcemod Plugin v%s Loaded successfully!", PLUGIN_VERSION);
    PrintToServer("+--------------------------------------------------------------------------");
}

/**
 * Gets the steam application ID from steam.inf
 * @note Can't remember who wrote this. Think it was from AdminStealth.
 *
 * @noreturn
 */
int GetAppID()
{
    char buffer[64];
    File f = OpenFile("./steam.inf", "r");
    
    do
    {
        if(!f.ReadLine(buffer, sizeof(buffer)))
            LogError("Failed to get proper APP ID.");
        TrimString(buffer);
    }
    while(StrContains(buffer, "appID=", false) < 0);
    delete f;

    ReplaceString(buffer, sizeof(buffer), "appID=", "", false);
    return StringToInt(buffer);
}

/**
 * Called on map change to check for updates, and other things.
 *
 * @noreturn
 */
void MotdMod_GetPluginStatus()
{
    CheckBadPlugins();
    GetPluginMode();
    if (StrContains(PLUGIN_VERSION, "-dev", false) < 0)
        UpdateCheck();
}

/**
 * Called to check for updates.
 *
 * @noreturn
 */
void UpdateCheck()
{
    DebugMessage("UpdateCheck() :: init");
    if(!g_bPluginUpdating)
    {
        PrintToServer("%s Checking for updates...", MSG_TAG);
        DebugMessage("UpdateCheck() :: Starting to check for updates");
        
        char encodedjson[4096];
        Handle json = CreateJSON();
        
        JSONSetInteger(json, "gameType", g_iAppID);
        JSONSetString(json, "platform", g_sServerOS);
        JSONSetString(json, "pluginType", "sourcemod");
        JSONSetString(json, "pluginChecksum", g_sPluginMD5);
        EncodeJSON(json, encodedjson, sizeof(encodedjson), false);
        
        DebugMessage("UpdateCheck() :: JSON: %s", encodedjson);
        
        DataPack pack = CreateDataPack();
        pack.WriteString("application/json");
        pack.WriteString("");
        
        DataPack pack2 = CreateDataPack();
        pack2.WriteString(encodedjson);
        
        char url[512];
        Format(url, sizeof(url), "%s%s", MOTDMOD_API_URL, MOTDMOD_API_VERSION);
        if(!EasyHTTP(url, POST, pack2, WebCallback_UpdateCheck, 0, "", pack))
        {
            LogError(MSG_ERROR_FAILED_UPDATE);
            delete pack;
            delete pack2;
        }
        DebugMessage("UpdateCheck() :: EasyHTTP sent");
    }
    else
        DebugMessage("UpdateCheck() :: Not checking for updates as we are currently updating already!");
}

// ####################################################################################
// #################################### CALLBACKS #####################################
// ####################################################################################

/**
 * Called when a VGUIPanel is displayed to a client.
 * @note Ref: https://sm.alliedmods.net/new-api/usermessages/MsgHook 
 * @note Only difference is we must define the msg variable as a Handle, as we will be using both BitBuffer and Protobuf.
 *
 * @param msg_id       Message index.
 * @param msg          Handle to the input bit buffer / protobuf.
 * @param players      Array containing player indexes.
 * @param playersNum   Number of players in the array.
 * @param reliable     True if message is reliable, false otherwise.
 * @param init         True if message is an initmsg, false otherwise.
 *
 * @return Plugin_Handled when blocking the server's MOTD message, Plugin_Continue otherwise.
 */
public Action OnVGUIMenu(UserMsg msg_id, Handle msg, const int[] players, int playersNum, bool reliable, bool init)
{
    DebugMessage("OnVGUIMenu() :: init");
    if(g_PluginMode != PluginMode_Active)
    {
        DebugMessage("OnVGUIMenu() :: PluginMode is not Active!");
        return Plugin_Continue;
    }

    bool show;
    int nSubKeys;
    KeyValues kv = ExtractVGUIPanelKeyValues(msg, show, nSubKeys);
    
    char panelMsg[64];
    kv.GetString("msg", panelMsg, sizeof(panelMsg));

    if (kv.GetNum("type") == MOTDPANEL_TYPE_INDEX && StrEqual(panelMsg, "motd"))
    {
        int client = players[0];

        if (g_flNextAllowInfoPanelTime[client] > GetGameTime())
            return Plugin_Handled;
        
        DebugMessage("OnVGUIMenu() :: Overwriting MOTD");
        
        QueryClientConVar(client, "cl_disablehtmlmotd", MotdMod_QueryCookie);
        
        delete kv;
        return Plugin_Handled;
    }

    delete kv;
    DebugMessage("OnVGUIMenu() :: COMPLETE");
    return Plugin_Continue;
}

public void OnDisplayHiddenInvalidMOTD(DataPack data)
{
    int clients[MAXPLAYERS];
    
    data.Reset();
    int nClients = ReadPackClientList(data, clients, sizeof(clients));
    
    delete data;
    
    if (nClients)
        DisplayHiddenInvalidMOTD(clients, nClients);
}

/**
 * Displays a hidden MOTD that busts the cache with a temporary HTML page.
 * 
 * @noreturn
 */
void DisplayHiddenInvalidMOTD(const int[] players, int nPlayers)
{
    static KeyValues invalidPageInfo;
    
    if (!invalidPageInfo)
    {
        invalidPageInfo = new KeyValues("data");
        invalidPageInfo.SetString("title", "");
        invalidPageInfo.SetNum("type", MOTDPANEL_TYPE_INDEX);
        invalidPageInfo.SetString("msg", INFO_PANEL_STRING);
    }
    
    ShowInfoPanelBlockHooks(players, nPlayers, invalidPageInfo, false);
}

/**
 * Sends the MotdMod url to the client in a VGUIPanel after getting their cl_disablehtmlmotd value
 *
 * @param cookie        QueryCookie handle.
 * @param client        Client index.
 * @param result        ConVarQueryResult: https://sm.alliedmods.net/new-api/convars/ConVarQueryResult
 * @param cvarName      ConVar name (If you were to use more than 1 cvar).
 * @param cvarValue     ConVar value.
 * @noreturn
 */
public void MotdMod_QueryCookie(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
    DebugMessage("MotdMod_QueryCookie() :: init");
    
    if (result != ConVarQuery_Okay)
        return;
    
    if (g_flNextAllowInfoPanelTime[client] > GetGameTime())
        return;
    
    int bDisabled = StringToFloat(cvarValue) != 0.0;
    
    char url[1024], steamid[32], community[64];
    char language[64];
    
    GetLanguageInfo(GetClientLanguage(client), _, _, language, sizeof(language));
    
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
    if(GetCommunityID(steamid, community, sizeof(community)))
    {
        Format(url, sizeof(url), "%s&lang=%s&steam=%s", g_sMotdUrl, language, community);
    }
    else
    {
        Format(url, sizeof(url), "%s&lang=%s", g_sMotdUrl, language);
    }
    
    KeyValues info = new KeyValues("info");
    
    // TODO make sure these are the right commands
    switch (g_GameEngine)
    {
        case Engine_Left4Dead, Engine_Left4Dead2:
        {
            info.SetString("cmd", "closed_htmlpage");
        }
        case Engine_CSGO:
        {
            info.SetString("cmd", "1");
        }
        default:
        {
            // TEXTWINDOW_CMD_CLOSED_HTMLPAGE @ vguitextwindow.cpp
            info.SetNum("cmd", 5);
        }
    }
    
    if (bDisabled)
    {
        // text only
        info.SetNum("type", MOTDPANEL_TYPE_INDEX);
        info.SetString("msg", INFO_PANEL_TEXT_STRING);
    }
    else
    {
        // HTML
        info.SetNum("type", MOTDPANEL_TYPE_URL);
        info.SetString("msg", url);
    }
    
    int clients[1];
    clients[0] = client;
    
    if (g_GameEngine == Engine_CSGO)
    {
        DebugMessage("MotdMod_QueryCookie() :: displaying MOTD");
        ShowInfoPanelBlockHooks(clients, 1, info, true);
        
        g_bIsViewingMOTD[client] = true;
    }
    else
    {
        // cache busting logic
        DataPack data = new DataPack();
        WritePackClientList(data, clients, 1);

        // TODO check if we can remove this RequestFrame call and use the function directly
        RequestFrame(OnDisplayHiddenInvalidMOTD, data);

        DataPack kvData = new DataPack();
        kvData.WriteCell(GetClientUserId(client));
        kvData.WriteCell(CloneHandle(info));
    
        DebugMessage("MotdMod_QueryCookie() :: invoking cache busting (url %s)", url);
        CreateTimer(0.75, MotdMod_BustCache, kvData);
        g_flNextAllowInfoPanelTime[client] = GetGameTime() + 0.75;
    }
    
    delete info;
    DebugMessage("MotdMod_QueryCookie() :: complete");
}

public Action MotdMod_BustCache(Handle timer, DataPack data)
{
    DebugMessage("MotdMod_BustCache() :: init");
    data.Reset();
    
    int client = GetClientOfUserId(data.ReadCell());
    KeyValues info = data.ReadCell();
    
    if (client)
    {
        int clients[1];
        clients[0] = client;
        
        DebugMessage("MotdMod_BustCache() :: displaying MOTD");
        ShowInfoPanelBlockHooks(clients, 1, info, true);
        
        g_bIsViewingMOTD[client] = true;
    }
    
    delete info;
    delete data;
    DebugMessage("MotdMod_BustCache() :: complete");
}

/**
 * Called when we get a response from the MotdMod update API.
 *
 * @param discarded       Ignored.
 * @param buffer          Raw web resposne.
 * @param success         If the response was successful.
 * @noreturn
 */
public int WebCallback_UpdateCheck(any discarded, const char[] buffer, bool success)
{
    DebugMessage("WebCallback_UpdateCheck() :: init");
    DebugMessage(buffer);
    
    if (!success)
    {
        DebugMessage("WebCallback_UpdateCheck() :: Failed update check");
        LogError(MSG_ERROR_FAILED_UPDATE);
        return;
    }
    else
    {
        char statuscode[32], pluginbinpath[PLATFORM_MAX_PATH], pluginchecksum[256], latestversion[32], updaterequired[32];
        
        KeyValues kv = CreateKeyValues("Motdmod");
        if(!kv.ImportFromString(buffer))
        {
            DebugMessage("WebCallback_UpdateCheck() :: Response is not KV!");
            LogError(MSG_ERROR_FAILED_UPDATE);
            return;
        }
        kv.JumpToKey("results");
        
        kv.GetString("statusCode", statuscode, sizeof(statuscode));
        kv.GetString("pluginBinPath", pluginbinpath, sizeof(pluginbinpath));
        kv.GetString("pluginChecksum", pluginchecksum, sizeof(pluginchecksum));
        kv.GetString("pluginLatestVersion", latestversion, sizeof(latestversion));
        kv.GetString("pluginUpdateRequired", updaterequired, sizeof(updaterequired));
        
        if(!StrEqual(statuscode, "200"))
        {
            DebugMessage("WebCallback_UpdateCheck() :: Failed update check. Response is not 200(OK) CODE: %s", statuscode);
            LogError(MSG_ERROR_FAILED_UPDATE);
            return;
        }
        if(!strlen(updaterequired))
        {
            DebugMessage("WebCallback_UpdateCheck() :: Failed update check. Missing update required key.");
            LogError(MSG_ERROR_FAILED_UPDATE);
            return;
        }
        if(StrEqual(updaterequired, "false"))
            LogMessage("%s Plugin up to date.", MSG_TAG);
        else
        {
            LogMessage("%s Plugin is out of date. Current version is: %s(%s), Latest available is: %s(%s)", MSG_TAG, PLUGIN_VERSION, g_sPluginMD5, latestversion, pluginchecksum);
            g_bPluginUpdating = true;
            
            char url[1024], path[PLATFORM_MAX_PATH], filename[PLATFORM_MAX_PATH];
            GetPluginFilename(INVALID_HANDLE, filename, sizeof(filename));
            
            // Build path to plugins folder (incase somebody changed the file name)
            BuildPath(Path_SM, path, sizeof(path), "plugins/%s.tmp", filename);
            
            // Format url to account for dl path.
            Format(url, sizeof(url), "%s%s", MOTDMOD, pluginbinpath);
            
            // Store data for later
            DataPack pack = CreateDataPack();
            pack.WriteString(path);
            pack.WriteString(filename);
            pack.WriteString(pluginchecksum);
            pack.WriteString(latestversion);
            pack.Reset();
            
            // Ready to downlaod.
            if (!EasyHTTP(url, GET, INVALID_HANDLE, WebCallback_DownloadedUpdate, pack, path))
            {
                DebugMessage(MSG_ERROR_FAILED_UPDATE);
                LogError(MSG_ERROR_FAILED_UPDATE);
                g_bPluginUpdating = false;
                delete pack;
            }
        }
    
        delete kv;
    }
    
    DebugMessage("WebCallback_UpdateCheck() :: complete");
}

/**
 * Called when we downlaod the newest motdmod version.
 *
 * @param pack            Datapack.
 * @param buffer          Raw web resposne.
 * @param success         If the response was successful.
 * @noreturn
 */
public int WebCallback_DownloadedUpdate(DataPack pack, const char[] buffer, bool success)
{
    DebugMessage("WebCallback_DownloadedUpdate() :: init");
    
    if (!success)
    {
        DebugMessage("WebCallback_DownloadedUpdate() :: Failed download");
        LogError(MSG_ERROR_FAILED_UPDATE);
        g_bPluginUpdating = false;
    }
    else
    {
        char path[PLATFORM_MAX_PATH], filename[PLATFORM_MAX_PATH], pluginchecksum[256], latestversion[32], downloadedchecksum[256];
        
        pack.Reset();
        pack.ReadString(path, sizeof(path));
        pack.ReadString(filename, sizeof(filename));
        pack.ReadString(pluginchecksum, sizeof(pluginchecksum));
        pack.ReadString(latestversion, sizeof(latestversion));
        
        if(MD5_File(path, downloadedchecksum, sizeof(downloadedchecksum)))
        {
            if(StrEqual(pluginchecksum, downloadedchecksum))
            {
                char pathfinal[PLATFORM_MAX_PATH];
                
                // Remove .tmp and delete old file.
                strcopy(pathfinal, sizeof(pathfinal), path);
                ReplaceString(pathfinal, sizeof(pathfinal), ".tmp", "", false);
                DeleteFile(pathfinal);
                RenameFile(pathfinal, path);
                
                // Announce the reload and do it!
                LogMessage("%s Downladed version %s(%s) successfully. Reloading the plugin now.", MSG_TAG, latestversion, pluginchecksum);
                g_bPluginUpdating = false;
                
                ServerCommand("sm plugins reload %s", filename);
            }
        }
        else
        {
            DebugMessage("WebCallback_DownloadedUpdate() :: Failed update because the MD5 function couldn't find the file!");
            LogError(MSG_ERROR_FAILED_UPDATE);
            g_bPluginUpdating = false;
        }
    }
    delete pack;
    
    DebugMessage("WebCallback_DownloadedUpdate() :: complete");
}


/**
 * Called when we get a response from the MotdMod web API.
 *
 * @param discarded       Ignored.
 * @param buffer          Raw web resposne.
 * @param success         If the response was successful.
 * @noreturn
 */
public int WebCallback_LoadMotdUrl(any discarded, const char[] buffer, bool success)
{
    DebugMessage("WebCallback_LoadMotdUrl() :: init");
    DebugMessage(buffer);
    
    if (!success)
    {
        g_bPluginInitInProcess = false;
        SetFailState("Failed to get MOTD URL from motdmod api!");
    }
    else
    {
        KeyValues kv = CreateKeyValues("Motdmod");
        if(!kv.ImportFromString(buffer))
            SetFailState("Failed to get MOTD URL from motdmod api! (Response is not KV)");
        kv.JumpToKey("results");
        kv.GetString("motdUrl", g_sMotdUrl, sizeof(g_sMotdUrl));
        kv.GetString("noHtmlText", g_sNoHTML, sizeof(g_sNoHTML));
        
        delete kv;
        
        if(!strlen(g_sMotdUrl))
        {
            g_bPluginInitInProcess = false;
            LogError("Failed to get MOTD URL from motdmod api! (can't find URL)");
        }
        
        SetInfoPanelData(INFO_PANEL_TEXT_STRING, g_sNoHTML);
        
        DebugMessage(g_sMotdUrl);
        DebugMessage(g_sNoHTML);
    }
    
    g_bPluginInitInProcess = false;
    DebugMessage("WebCallback_LoadMotdUrl() :: complete");
}

/**
 * Called when we fallback to the last possible attempt to get the server IP.
 *
 * @param discarded       Ignored.
 * @param buffer          Raw web resposne.
 * @param success         If the response was successful.
 * @noreturn
 */
public int WebCallback_IPFromExternal(any discarded, const char[] buffer, bool success)
{
    DebugMessage("WebCallback_IPFromExternal() :: init");
    
    if (!success)
    {
        DebugMessage("WebCallback_IPFromExternal() :: ERROR: Unknown error! Defaulting to 127.0.0.1");
        LogError("Error in WebCallback_IPFromExternal :: Unknown error! Defaulting to 127.0.0.1");
        Format(g_sHostIP, sizeof(g_sHostIP), "127.0.0.1");
    }
    else if(IsIPLocal(IPToLong(buffer)))
    {
        DebugMessage("WebCallback_IPFromExternal() :: ERROR: Received a local IP address from the external IP checker! Defaulting to 127.0.0.1");
        LogError("Received a local IP address from the external IP checker! Defaulting to 127.0.0.1");
        Format(g_sHostIP, sizeof(g_sHostIP), "127.0.0.1");
    }
    else
        strcopy(g_sHostIP, sizeof(g_sHostIP), buffer);

    DebugMessage("WebCallback_IPFromExternal() :: complete");
    OnLoadServerInfoComplete();
}

// ####################################################################################
// #################################### STOCKS ########################################
// ####################################################################################

/**
 * GetCommunityID
 * @note Credit: https://forums.alliedmods.net/showthread.php?t=183443
 *
 * @param AuthID    Steamid2
 * @param FriendID  Steamid 64 buffer.
 * @param size      Size of the buffer.
 * @noreturn
 */
stock bool GetCommunityID(char[] AuthID, char[] FriendID, int size)
{
    if(strlen(AuthID) < 11 || AuthID[0]!='S' || AuthID[6]=='I')
    {
        FriendID[0] = 0;
        return false;
    }
    int iUpper = 765611979;
    int iFriendID = StringToInt(AuthID[10])*2 + 60265728 + AuthID[8]-48;
    int iDiv = iFriendID/100000000;
    int iIdx = 9-(iDiv?iDiv/10+1:0);
    iUpper += iDiv;
    IntToString(iFriendID, FriendID[iIdx], size-iIdx);
    iIdx = FriendID[9];
    IntToString(iUpper, FriendID, size);
    FriendID[9] = iIdx;
    return true;
}

/**
 * Converts a LongIP to a human-readable IP.
 * @note Credit SMLib.
 *
 * @param ip        LongIP.
 * @param buffer    Buffer to store the new IP.
 * @param size      Size of the buffer.
 * @noreturn
 */
stock void LongToIP(int ip, char[] buffer, int size)
{
    Format(
        buffer, size,
        "%d.%d.%d.%d",
            (ip >> 24)    & 0xFF,
            (ip >> 16)    & 0xFF,
            (ip >> 8 )    & 0xFF,
            ip            & 0xFF
        );
}

/**
 * Converts a human-readable IP to a LongIP.
 * @note Credit SMLib.
 *
 * @param ip        The human-readable IP.
 * @return          The LongIP integer.
 */
stock int IPToLong(const char[] ip)
{
    char pieces[4][4];

    if (ExplodeString(ip, ".", pieces, sizeof(pieces), sizeof(pieces[])) != 4) {
        return 0;
    }

    return (
        StringToInt(pieces[0]) << 24    |
        StringToInt(pieces[1]) << 16    |
        StringToInt(pieces[2]) << 8        |
        StringToInt(pieces[3])
    );
}

/**
 * Detects if an IP address is local or not.
 * @note Credit SMLib.
 *
 * @param ip        The LongIP.
 * @return          True on local, false otherwise.
 */
stock bool IsIPLocal(int ip)
{
    int range, bits, move;
    bool matches;

    for (int i = 0; i < sizeof(g_LocalIPRanges); i++)
    {
        range = g_LocalIPRanges[i];
        matches = true;

        for (int j = 0; j < 4; j++)
        {
            move = j * 8;
            bits = (range >> move) & 0xFF;

            if (bits && bits != ((ip >> move) & 0xFF))
            {
                matches = false;
            }
        }

        if (matches)
        {
            return true;
        }
    }

    return false;
}

/**
 * Detects Server OS.
 * @note Credit: https://forums.alliedmods.net/showpost.php?p=891866&postcount=23
 *
 * @return 1 for windows 2 for linux
 */
int GetServerOS()
{
    Handle conf = LoadGameConfigFile("motdmod.gamedata");
    int OS = GameConfGetOffset(conf, "OperatingSystem");
    delete conf;
    return OS;
}

/**
 * Will log debug messages to the sourcemod logs if verbose logging is enabled.
 *
 * @param message   The message.
 * @param ...       The formatting of the message.
 * @noreturn
 */
void DebugMessage(const char[] message, any ...)
{
    char text[512];
    VFormat(text, sizeof(text), message, 2);
    
    // Just incase.
    if(g_cvVerbose == null)
        g_cvVerbose = CreateConVar("sm_motdmod_debug", "0.0", "1 = Enables verbose logging | 0 = disabled (default)", _, true, 0.0);
    
    if(g_cvVerbose.BoolValue)
    {
        LogMessage(text);
    }
}

/**
 * Extracts the KeyValues from the given VGUIMenu usermessage buffer.
 * The panel name is set as the KeyValues' section name.
 */
stock KeyValues ExtractVGUIPanelKeyValues(Handle buffer, bool &show = false,
        int &nSubKeys = 0)
{
    char panelName[128];
    
    KeyValues kv = new KeyValues("(missing panel name)");
    switch (GetUserMessageType_Compat())
    {
        case UM_BitBuf:
        {
            BfRead bitbuf = UserMessageToBfRead(buffer);
            bitbuf.ReadString(panelName, sizeof(panelName));
            
            show = !!bitbuf.ReadByte();
            nSubKeys = bitbuf.ReadByte();
            
            kv.SetSectionName(panelName);
            for (int i = 0; i < nSubKeys; i++) {
                char key[192], value[192];
                
                bitbuf.ReadString(key, sizeof(key), false);
                bitbuf.ReadString(value, sizeof(value), false);
                
                kv.SetString(key, value);
            }
        }
        case UM_Protobuf:
        {
            Protobuf protobuf = UserMessageToProtobuf(buffer);
            protobuf.ReadString("name", panelName, sizeof(panelName));
            
            show = protobuf.ReadBool("show");
            nSubKeys = protobuf.GetRepeatedFieldCount("subkeys");
            
            kv.SetSectionName(panelName);
            for (int i = 0; i < nSubKeys; i++)
            {
                char key[192], value[192];
                
                Protobuf subkey = protobuf.ReadRepeatedMessage("subkeys", i);
                subkey.ReadString("name", key, sizeof(key));
                subkey.ReadString("str", value, sizeof(value));
                
                kv.SetString(key, value);
            }
        }
        default:
        {
            ThrowError("ExtractInfoPanelKeyValues does not support this usermessage type (%d)",
                    GetUserMessageType_Compat());
        }
    }
    return kv;
}

/**
 * Writes a string into the info panel string table with the specified name, replacing it if
 * it already exists.
 * 
 * @param name      String table entry name.
 * @param data      Data to be inserted (text, a URL, or an HTML string: first char must be '<')
 * 
 * @noreturn
 */
stock void SetInfoPanelData(const char[] name, const char[] data)
{
    static int s_iStringTableInfoPanel = INVALID_STRING_INDEX;
    
    if (s_iStringTableInfoPanel == INVALID_STRING_INDEX)
        s_iStringTableInfoPanel = FindStringTable("InfoPanel");
    
    int iInfoIdentifier = FindStringIndex(s_iStringTableInfoPanel, name);
    if (iInfoIdentifier == INVALID_STRING_INDEX)
        AddToStringTable(s_iStringTableInfoPanel, name, data, strlen(data) + 1);
    else
        SetStringTableData(s_iStringTableInfoPanel, iInfoIdentifier, data, strlen(data) + 1);
}

/**
 * Compatibility shim for GetUserMessageType().
 */
stock UserMessageType GetUserMessageType_Compat()
{
    static UserMessageType s_UMType = UM_BitBuf;
    static bool s_bCached;
    
    if (!s_bCached && GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available)
    {
        s_UMType = GetUserMessageType();
        s_bCached = true;
    }
    
    return s_UMType;
}