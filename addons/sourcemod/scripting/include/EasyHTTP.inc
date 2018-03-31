/*
    EasyHTTP
    
    Thanks to these people:
    
    Original Author: https://forums.alliedmods.net/showpost.php?p=2256124&postcount=4
    Edited by: https://forums.alliedmods.net/showthread.php?t=219062
    and: https://forums.alliedmods.net/showthread.php?t=271168
	and: lake393 (MOTDs Network) - Added JWT Header Support
*/
#if defined _easyhttp_included
 #endinput
#endif
#define _easyhttp_included

#if defined REQUIRE_EXTENSIONS
#undef REQUIRE_EXTENSIONS
#endif

#define STRING(%1) %1, sizeof(%1)

#include <cURL>
#include <socket>
#include <steamtools>
#include <SteamWorks>

#if !defined _easyrcon_included
bool g_bExtensions = false;
bool g_bCURL = false;
bool g_bSteamTools = false;
bool g_bSockets = false;
bool g_bSteamWorks = false;
#endif

enum DataPackPos: {};

char g_szInterfaceIP[16];

enum EHTTPMethodInternal
{
    GET,
    POST,
    DELETE,
}

stock void EasyHTTPCheckExtensions()
{
    g_bExtensions = true;
    // g_bSockets = (GetExtensionFileStatus("socket.ext")==1?true:false); Something is wrong with socket sending json, so it needs fixing too. Should be fixed by version 2 of the plugin.
    // g_bCURL = (GetExtensionFileStatus("curl.ext")==1?true:false); CURL Is broken at the moment so we can't use it.
    g_bSteamTools = (GetExtensionFileStatus("steamtools.ext")==1?true:false);
    g_bSteamWorks = (GetExtensionFileStatus("SteamWorks.ext")==1?true:false);
    
    if(!g_bSteamTools && !g_bSteamWorks)
        SetFailState("You must have at least one web extension installed to use this plugin. (Steamworks or steamtools.)");
}

stock void EasyHTTP_QueryString(Handle params, char[] out, int maxlen)
{
    char m_szQuery[maxlen];

    Handle m_hKeys = ReadPackCell(params);
    Handle m_hValues = ReadPackCell(params);
    ResetPack(params);

    int m_unSize = GetArraySize(m_hKeys);
    char m_szKey[64];
    char m_szKeyEncoded[128];
    char m_szValue[256];
    char m_szValueEncoded[512];
    int idx=0;

    for(int i=0;i<m_unSize;++i)
    {
        GetArrayString(m_hKeys, i, STRING(m_szKey));
        if(GetTrieString(m_hValues, m_szKey, STRING(m_szValue)))
        {
            EasyHTTP_URLEncode(m_szKey, STRING(m_szKeyEncoded));
            EasyHTTP_URLEncode(m_szValue, STRING(m_szValueEncoded));
            idx += Format(m_szQuery[idx], maxlen-idx, "&%s=%s", m_szKeyEncoded, m_szValueEncoded);
        }
    }

    if(idx > 0)
    {
        strcopy(out, maxlen, m_szQuery[1]);
    }
}

stock bool EasyHTTP(const char[] url, EHTTPMethodInternal method, Handle params, Function complete = INVALID_FUNCTION, any data = 0, const char[] path = "", Handle headers = null)
{
    bool bheaders = false;
    bool noauth = false;
    
    if(!g_bExtensions)
        EasyHTTPCheckExtensions();
    if(g_szInterfaceIP[0]==0)
    {
        Handle m_hHostIP = FindConVar("hostip");
        if(m_hHostIP == null)
            LogError("EasyHTTP can't determine IP address of the server.");
        int m_iServerIP = GetConVarInt(m_hHostIP);
        Format(STRING(g_szInterfaceIP), "%d.%d.%d.%d", m_iServerIP >>> 24 & 255, m_iServerIP >>> 16 & 255, m_iServerIP >>> 8 & 255, m_iServerIP & 255);
    }

    int m_unURLSize = strlen(url)+2048;
    char[] m_szURLNew = new char[m_unURLSize];
    char m_szQuery[2048];

    char json[4096];
    if(params != null)
    {
        DataPack pack = view_as<DataPack>(params);
        pack.Reset();
        pack.ReadString(json, sizeof(json));
        
        delete pack;
    }
    
    char contentheader[256];
    char authorizationheader[512];
    
    if(headers != null)
    {
        bheaders = true;
        
        DataPack pack = view_as<DataPack>(headers);
        pack.Reset();
        pack.ReadString(contentheader, sizeof(contentheader));
        pack.ReadString(authorizationheader, sizeof(authorizationheader));
        
        if(StrEqual(authorizationheader, ""))
            noauth = true;
        delete pack;
    }

    if(method == GET)
        Format(m_szURLNew, m_unURLSize, "%s?%s", url, m_szQuery);
    else
        strcopy(m_szURLNew, m_unURLSize, url);

    if(g_bCURL)
    {
        Handle m_hCurl = curl_easy_init();
        if(m_hCurl != null)
        {
            int CURL_Default_opt[][2] = {
                {_:CURLOPT_NOPROGRESS,1},
                {_:CURLOPT_TIMEOUT,30},
                {_:CURLOPT_CONNECTTIMEOUT,60},
                {_:CURLOPT_VERBOSE,0}};

            Handle m_hData = CreateDataPack();
            Handle m_hContents = null;
            if(path[0] == 0)
            {
                m_hContents = CreateDataPack();
                WritePackCell(m_hContents, 0);
                WritePackCell(m_hContents, 0);
                ResetPack(m_hContents);
            }
            else
            {
                m_hContents = OpenFile(path, "wb");
                if(m_hContents == null)
                {
                    LogError("EasyHTTP OpenFile error.");
                    return false;
                }
            }

            WritePackFunction(m_hData, complete);
            WritePackCell(m_hData, data);
            WritePackString(m_hData, path);
            WritePackCell(m_hData, _:m_hContents);
            ResetPack(m_hData);
    
            curl_easy_setopt_int_array(m_hCurl, CURL_Default_opt, sizeof(CURL_Default_opt));
            curl_easy_setopt_string(m_hCurl, CURLOPT_URL, m_szURLNew);
            curl_easy_setopt_function(m_hCurl, CURLOPT_WRITEFUNCTION, EasyHTTP_CurlWrite, m_hData);
            curl_easy_setopt_int(m_hCurl, CURLOPT_NOSIGNAL, 1);
            
            if(bheaders)
            {
                char localcontent[256];
                Format(localcontent, sizeof(localcontent), "Content-Type: %s", contentheader);
                curl_easy_setopt_string(m_hCurl, CURLOPT_HTTPHEADER, contentheader);
                
                if(!noauth)
                {
                    char localauth[512];
                    Format(localauth, sizeof(localauth), "Authorization: %s", authorizationheader);
                    curl_easy_setopt_string(m_hCurl, CURLOPT_HTTPHEADER, authorizationheader);
                }
            }

            if(method == POST)
            {
                curl_easy_setopt_int(m_hCurl, CURLOPT_POST, 1);
                curl_easy_setopt_string(m_hCurl, CURLOPT_POSTFIELDS, json);
            }

            CURLcode m_iCode = curl_load_opt(m_hCurl);
            if(m_iCode != CURLE_OK)
            {
                CloseHandle(m_hCurl);
                CloseHandle(m_hContents);
                CloseHandle(m_hData);
                return false;
            }

            curl_easy_perform_thread(m_hCurl, EasyHTTP_CurlComplete, m_hData);
    
            return true;
        }
    } else if(g_bSteamTools || g_bSteamWorks)
    {
        Handle m_hData = CreateDataPack();
        WritePackFunction(m_hData, complete);
        WritePackCell(m_hData, data);
        WritePackString(m_hData, path);
        ResetPack(m_hData);

        int m_iLength = strlen(m_szURLNew)+8;
        char[] m_szURL = new char[m_iLength];
        if(StrContains(m_szURLNew, "http://")==-1 && StrContains(m_szURLNew, "https://")==-1)
        {
            strcopy(m_szURL, m_iLength, "http://");
            strcopy(m_szURL[7], m_iLength-7, m_szURLNew);
        }
        else
            strcopy(m_szURL, m_iLength, m_szURLNew);

        Handle m_hRequestWorks;
        HTTPRequestHandle m_hRequestTools;

        if(g_bSteamWorks)
        {
            if(method == POST)
                m_hRequestWorks = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, m_szURL);
            else
                m_hRequestWorks = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, m_szURL);
        }
        else
        {
            if(method == POST)
                m_hRequestTools = Steam_CreateHTTPRequest(HTTPMethod_POST, m_szURL);
            else
                m_hRequestTools = Steam_CreateHTTPRequest(HTTPMethod_GET, m_szURL);
        }
            
        
        if(bheaders)
        {
            if(g_bSteamWorks)
            {
                SteamWorks_SetHTTPRequestHeaderValue(m_hRequestWorks, "Content-Type", contentheader);
                if(!noauth)
                    SteamWorks_SetHTTPRequestHeaderValue(m_hRequestWorks, "Authorization", authorizationheader);
            }
            else
            {
                Steam_SetHTTPRequestHeaderValue(m_hRequestTools, "Content-Type", contentheader);
                if(!noauth)
                    Steam_SetHTTPRequestHeaderValue(m_hRequestTools, "Authorization", authorizationheader);
            }
        }
        
        if(method == POST)
        {
            if(g_bSteamWorks)
            {
                SteamWorks_SetHTTPRequestRawPostBody(m_hRequestWorks, "application/json", json, sizeof(json));
            }
            else
                Steam_SetHTTPRequestRawPostBody(m_hRequestTools, json, sizeof(json), "application/json");
        }
        
        if(g_bSteamWorks)
        {
            SteamWorks_SetHTTPRequestContextValue(m_hRequestWorks, m_hData);
            SteamWorks_SetHTTPCallbacks(m_hRequestWorks, EasyHTTP_SteamWorksComplete);
            SteamWorks_SendHTTPRequest(m_hRequestWorks);
        }
        else
            Steam_SendHTTPRequest(m_hRequestTools, EasyHTTP_SteamToolsComplete, m_hData);
        return true;
    } else if(g_bSockets)
    {
        Handle m_hData = CreateDataPack();
        Handle m_hContents = null;
        if(path[0] == 0)
        {
            m_hContents = CreateDataPack();
            WritePackCell(m_hContents, 0);
            WritePackCell(m_hContents, 0);
            ResetPack(m_hContents);
        }
        else
        {
            m_hContents = OpenFile(path, "wb");
            if(m_hContents == null)
            {
                LogError("EasyHTTP OpenFile error.");
                return false;
            }
        }

        int m_iLength = strlen(m_szURLNew)+1;
        char[] m_szBaseURL = new char[m_iLength];
        EasyHTTP_GetBaseURL(m_szURLNew, m_szBaseURL, m_iLength);

        int m_iPos = 0;
        if(StrContains(m_szURLNew, "http://")!=-1)
            m_iPos = 7;
        m_iPos += FindCharInString(m_szURLNew[m_iPos], '/');

        WritePackCell(m_hData, method);
        if(m_iPos == -1)
        {
            WritePackCell(m_hData, 1);
            WritePackString(m_hData, "/");
        }
        else
        {
            WritePackCell(m_hData, strlen(m_szURLNew[m_iPos]));
            WritePackString(m_hData, m_szURLNew[m_iPos]);
        }
        WritePackCell(m_hData, strlen(m_szBaseURL));
        WritePackString(m_hData, m_szBaseURL);
        if(method == POST)
        {
            WritePackCell(m_hData, strlen(json));
            WritePackString(m_hData, json);
        }
        else
        {
            WritePackCell(m_hData, 0);
            WritePackString(m_hData, "");
        }
        WritePackFunction(m_hData, complete);
        WritePackCell(m_hData, data);
        WritePackString(m_hData, path);
        WritePackCell(m_hData, _:m_hContents);
        WritePackCell(m_hData, false);
        
        // Write headers
        if(bheaders)
        {
            WritePackString(m_hData, contentheader);
            WritePackString(m_hData, authorizationheader);
        }
        else
        {
            WritePackString(m_hData, "");
            WritePackString(m_hData, "");
        }
        ResetPack(m_hData);

        Handle m_hSocket = SocketCreate(SOCKET_TCP, EasyHTTP_SocketError);
        SocketSetArg(m_hSocket, m_hData);
        if(strncmp(m_szBaseURL, "www.", 4)==0)
            SocketConnect(m_hSocket, EasyHTTP_SocketConnected, EasyHTTP_SocketReceive, EasyHTTP_SocketDisconnected, m_szBaseURL[4], 80);
        else
            SocketConnect(m_hSocket, EasyHTTP_SocketConnected, EasyHTTP_SocketReceive, EasyHTTP_SocketDisconnected, m_szBaseURL, 80);

        return true;
    }

    return false;
}

stock void EasyHTTP_GetBaseURL(const char[] url, char[] output, int maxlen, bool protocol = false, bool pathinfo = false)
{
    int m_iPos = 0;
    if(!protocol)
        if(strncmp(url, "http://", 7)==0)
            m_iPos = 7;
        else if(strncmp(url, "https://", 8)==0)
            m_iPos = 8;
    int m_iLength = FindCharInString(url[m_iPos], (pathinfo?'?':'/'))+1;
    if(m_iLength == -1)
        m_iLength = maxlen;
    else if(m_iLength > maxlen)
        m_iLength = maxlen;

    strcopy(output, m_iLength, url[m_iPos]);
    if(output[m_iLength-1]=='/')
        output[m_iLength-1] = 0;
}

public int EasyHTTP_CurlWrite(Handle hndl, const char[] buffer, const int bytes, const int nmemb, any data)
{
    ReadPackFunction(view_as<Handle>(data));
    ReadPackCell(view_as<Handle>(data));
    char m_szPath[PLATFORM_MAX_PATH];
    ReadPackString(view_as<Handle>(data), STRING(m_szPath));
    bool m_bFile = (m_szPath[0]?true:false);
    Handle m_hData = view_as<Handle>(ReadPackCell(view_as<Handle>(data)));
    ResetPack(data);

    if(m_bFile)
    {
        int m_iIdx = 0;
        while(m_iIdx < nmemb)
            WriteFileCell(m_hData, buffer[m_iIdx++], 1);
    }
    else
    {
        int m_iBytes = ReadPackCell(m_hData);
        int m_iStrings = ReadPackCell(m_hData);
        ResetPack(m_hData);
        WritePackCell(m_hData, m_iBytes + nmemb);
        WritePackCell(m_hData, m_iStrings + 1);

        char m_szTmp[1024];
        for(int i=0;i<m_iStrings;++i)
            ReadPackString(m_hData, STRING(m_szTmp));

        WritePackString(m_hData, buffer);
        ResetPack(m_hData);
    }
    return bytes*nmemb;
}

public int EasyHTTP_CurlComplete(Handle hndl, CURLcode code, any data)
{
    Function m_fnCallback = ReadPackFunction(view_as<Handle>(data));
    any m_aData = ReadPackCell(view_as<Handle>(data));
    char m_szPath[PLATFORM_MAX_PATH];
    ReadPackString(view_as<Handle>(data), STRING(m_szPath));
    bool m_bFile = (m_szPath[0]!=0?true:false);

    Handle m_hData = view_as<Handle>(ReadPackCell(view_as<Handle>(data)));
    CloseHandle(data);

    if(code != CURLE_OK)
    {
        char err[256];
        curl_get_error_buffer(hndl, err, sizeof(err));
        LogError("CURL error received: %d (%s)", code, err);
        CloseHandle(hndl);
        if(m_fnCallback != INVALID_FUNCTION)
        {
            Call_StartFunction(null, m_fnCallback);
            Call_PushCell(m_aData);
            Call_PushString("");
            Call_PushCell(false);
            Call_Finish();
        }
        return;
    }
    CloseHandle(hndl);

    if(m_fnCallback != INVALID_FUNCTION)
    {
        Call_StartFunction(null, m_fnCallback);
        Call_PushCell(m_aData);

        int m_iBytes = 1;
        int m_iStrings = 0;
        if(!m_bFile)
        {
            m_iBytes = ReadPackCell(m_hData);
            m_iStrings = ReadPackCell(m_hData);
        }

        char[] m_szBuffer = new char[m_iBytes+1];
        if(!m_bFile)
        {
            int m_iPos = 0;
            for(int i=0;i<m_iStrings;++i)
            {
                ReadPackString(m_hData, m_szBuffer[m_iPos], m_iBytes+1-m_iPos);
                m_iPos = strlen(m_szBuffer);
            }
            
        }
        Call_PushString(m_szBuffer);
        Call_PushCell(true);
        Call_Finish();
    }
    CloseHandle(m_hData);
}

public int EasyHTTP_SteamWorksComplete(Handle request, bool failure, bool successful, EHTTPStatusCode code, any data)
{
    Function m_fnCallback = ReadPackFunction(view_as<Handle>(data));
    any m_aData = ReadPackCell(view_as<Handle>(data));
    char m_szPath[PLATFORM_MAX_PATH];
    ReadPackString(view_as<Handle>(data), STRING(m_szPath));
    CloseHandle(data);

    if(!successful)
    {
        CloseHandle(request);
        LogError("Request failed. HTTP status: %d", code);

        if(m_fnCallback != INVALID_FUNCTION)
        {
            Call_StartFunction(null, m_fnCallback);
            Call_PushCell(m_aData);
            Call_PushString("");
            Call_PushCell(false);
            Call_Finish();
        }

        return;
    }

    int m_iLength = 1;
    if(m_szPath[0] == 0)
    {
        SteamWorks_GetHTTPResponseBodySize(request, m_iLength);
    }

    char[] m_szBuffer = new char[m_iLength+1];
        
    if(m_szPath[0] == 0)
    {
        SteamWorks_GetHTTPResponseBodyData(request, m_szBuffer, m_iLength);
        m_szBuffer[m_iLength] = 0;
    }
    else
        SteamWorks_WriteHTTPResponseBodyToFile(request, m_szPath);

    if(m_fnCallback != INVALID_FUNCTION)
    {
        Call_StartFunction(null, m_fnCallback);
        Call_PushCell(m_aData);
        Call_PushString(m_szBuffer);
        Call_PushCell(true);
        Call_Finish();
    }
    CloseHandle(request);
}

public int EasyHTTP_SteamToolsComplete(HTTPRequestHandle request, bool successful, HTTPStatusCode code, any data)
{
    Function m_fnCallback = ReadPackFunction(view_as<Handle>(data));
    any m_aData = ReadPackCell(view_as<Handle>(data));
    char m_szPath[PLATFORM_MAX_PATH];
    ReadPackString(view_as<Handle>(data), STRING(m_szPath));
    CloseHandle(data);

    if(!successful)
    {
        Steam_ReleaseHTTPRequest(request);
        LogError("Request failed. HTTP status: %d", code);

        if(m_fnCallback != INVALID_FUNCTION)
        {
            Call_StartFunction(null, m_fnCallback);
            Call_PushCell(m_aData);
            Call_PushString("");
            Call_PushCell(false);
            Call_Finish();
        }

        return;
    }

    int m_iLength = 1;
    if(m_szPath[0] == 0)
        m_iLength = Steam_GetHTTPResponseBodySize(request);

    char[] m_szBuffer = new char[m_iLength+1];
        
    if(m_szPath[0] == 0)
    {
        Steam_GetHTTPResponseBodyData(request, m_szBuffer, m_iLength);
        m_szBuffer[m_iLength] = 0;
    }
    else
        Steam_WriteHTTPResponseBody(request, m_szPath);

    if(m_fnCallback != INVALID_FUNCTION)
    {
        Call_StartFunction(null, m_fnCallback);
        Call_PushCell(m_aData);
        Call_PushString(m_szBuffer);
        Call_PushCell(true);
        Call_Finish();
    }
    Steam_ReleaseHTTPRequest(request);
}

public int EasyHTTP_SocketConnected(Handle socket, any data)
{
    EHTTPMethodInternal method = ReadPackCell(view_as<Handle>(data));
    int m_iGETLength = ReadPackCell(view_as<Handle>(data));
    char[] m_szGET = new char[m_iGETLength+1];
    ReadPackString(view_as<Handle>(data), m_szGET, m_iGETLength+1);
    int m_iURLLength = ReadPackCell(view_as<Handle>(data));
    char[] m_szURL = new char[m_iURLLength+1];
    ReadPackString(view_as<Handle>(data), m_szURL, m_iURLLength+1);

    int m_iQueryLength = ReadPackCell(view_as<Handle>(data));
    char[] m_szQueryString = new char[m_iQueryLength+1];
    ReadPackString(view_as<Handle>(data), m_szQueryString, m_iQueryLength+1);
    
    // Advance the pack to the position I need.
    char tmp[512];
    ReadPackFunction(view_as<Handle>(data));
    ReadPackCell(view_as<Handle>(data));
    ReadPackString(view_as<Handle>(data), tmp, sizeof(tmp));
    ReadPackCell(view_as<Handle>(data));
    ReadPackCell(view_as<Handle>(data));
    
    char contentheader[256];
    char authorizationheader[512];
    ReadPackString(view_as<Handle>(data), contentheader, sizeof(contentheader));
    ReadPackString(view_as<Handle>(data), authorizationheader, sizeof(authorizationheader));
    if(StrEqual(contentheader, "", false))
    {
        Format(contentheader, sizeof(contentheader), "application/x-www-form-urlencoded");
    }
    if(!StrEqual(authorizationheader, "", false))
    {
        Format(authorizationheader, sizeof(authorizationheader), "\r\nAuthorization: %s", authorizationheader);
    }
    ResetPack(view_as<Handle>(data));

    char m_szMethod[32];
    if(method == GET)
        strcopy(STRING(m_szMethod), "GET");
    else if(method == POST)
        strcopy(STRING(m_szMethod), "POST");
    else if(method == DELETE)
        strcopy(STRING(m_szMethod), "DELETE");

    char[] m_szRequest = new char[m_iGETLength+m_iURLLength+64];
    Format(m_szRequest, m_iGETLength+m_iURLLength+m_iQueryLength+256, "%s %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\nContent-Length: %d%s\r\nContent-Type: %s\r\n\r\n%s", m_szMethod, m_szGET, m_szURL, m_iQueryLength, authorizationheader, contentheader, m_szQueryString);

    SocketSend(socket, m_szRequest);
}

public int EasyHTTP_SocketReceive(Handle socket, char[] receiveData, const int dataSize, any data)
{
    ReadPackCell(view_as<Handle>(data));
    char m_szHelper[1];
    ReadPackCell(view_as<Handle>(data));
    ReadPackString(view_as<Handle>(data), STRING(m_szHelper));
    ReadPackCell(view_as<Handle>(data));
    ReadPackString(view_as<Handle>(data), STRING(m_szHelper));
    ReadPackCell(view_as<Handle>(data));
    ReadPackString(view_as<Handle>(data), STRING(m_szHelper));

    ReadPackFunction(view_as<Handle>(data));
    ReadPackCell(view_as<Handle>(data));
    char m_szPath[PLATFORM_MAX_PATH];
    ReadPackString(view_as<Handle>(data), STRING(m_szPath));
    bool m_bFile = (m_szPath[0]?true:false);
    Handle m_hData = view_as<Handle>(ReadPackCell(view_as<Handle>(data)));
    DataPackPos m_iHeaders = GetPackPosition(view_as<Handle>(data));
    bool m_bHeaders = view_as<bool>(ReadPackCell(view_as<Handle>(data)));
    ResetPack(view_as<Handle>(data));

    int m_iPos = 0;
    if(!m_bHeaders)
    {
        if ((m_iPos= StrContains(receiveData, "\r\n\r\n")) == -1)
            m_iPos = 0;
        else
        {
            m_iPos += 4;
            SetPackPosition(view_as<Handle>(data), m_iHeaders);
            WritePackCell(view_as<Handle>(data), true);
            ResetPack(data);
        }
    }

    if(m_bFile)
    {
        int m_iIdx = m_iPos;
        while(m_iIdx < dataSize)
            WriteFileCell(m_hData, receiveData[m_iIdx++], 1);
    }
    else
    {
        int m_iBytes = ReadPackCell(m_hData);
        int m_iStrings = ReadPackCell(m_hData);
        ResetPack(m_hData);
        WritePackCell(m_hData, m_iBytes + dataSize);
        WritePackCell(m_hData, m_iStrings + 1);

        char m_szTmp[4096];
        for(int i=0;i<m_iStrings;++i)
            ReadPackString(m_hData, STRING(m_szTmp));

        WritePackString(m_hData, receiveData[m_iPos]);
        ResetPack(m_hData);
    }
}

public int EasyHTTP_SocketDisconnected(Handle socket, any data)
{
    ReadPackCell(view_as<Handle>(data));
    char m_szHelper[1];
    ReadPackCell(view_as<Handle>(data));
    ReadPackString(view_as<Handle>(data), STRING(m_szHelper));
    ReadPackCell(view_as<Handle>(data));
    ReadPackString(view_as<Handle>(data), STRING(m_szHelper));
    ReadPackCell(view_as<Handle>(data));
    ReadPackString(view_as<Handle>(data), STRING(m_szHelper));
    Function m_fnCallback = ReadPackFunction(view_as<Handle>(data));
    any m_aData = ReadPackCell(view_as<Handle>(data));
    char m_szPath[PLATFORM_MAX_PATH];
    ReadPackString(view_as<Handle>(data), STRING(m_szPath));
    bool m_bFile = (m_szPath[0]?true:false);
    Handle m_hData = view_as<Handle>(ReadPackCell(view_as<Handle>(data)));
    CloseHandle(data);

    if(m_fnCallback != INVALID_FUNCTION)
    {
        Call_StartFunction(null, m_fnCallback);
        Call_PushCell(m_aData);
        int m_iBytes = 1;
        int m_iStrings = 0;
        if(!m_bFile)
        {
            m_iBytes = ReadPackCell(m_hData);
            m_iStrings = ReadPackCell(m_hData);
        }

        char[] m_szBuffer = new char[m_iBytes+1];
        if(!m_bFile)
        {
            int m_iPos = 0;
            for(int i=0;i<m_iStrings;++i)
            {
                ReadPackString(m_hData, m_szBuffer[m_iPos], m_iBytes+1-m_iPos);
                m_iPos = strlen(m_szBuffer);
            }
            
        }
        Call_PushString(m_szBuffer);
        Call_PushCell(true);
        Call_Finish();
    }

    CloseHandle(m_hData);
    CloseHandle(socket);
}

public int EasyHTTP_SocketError(Handle socket, const int errorType, const int errorNum, any data)
{
    ReadPackCell(view_as<Handle>(data));
    char m_szHelper[1];
    ReadPackCell(view_as<Handle>(data));
    ReadPackString(view_as<Handle>(data), STRING(m_szHelper));
    ReadPackCell(view_as<Handle>(data));
    ReadPackString(view_as<Handle>(data), STRING(m_szHelper));
    ReadPackCell(view_as<Handle>(data));
    ReadPackString(view_as<Handle>(data), STRING(m_szHelper));

    Function m_fnCallback = ReadPackFunction(view_as<Handle>(data));
    any m_aData = ReadPackCell(view_as<Handle>(data));
    CloseHandle(data);

    LogError("Request failed. Error type: %d Num: %d", errorType, errorNum);

    if(m_fnCallback != INVALID_FUNCTION)
    {
        Call_StartFunction(null, m_fnCallback);
        Call_PushCell(m_aData);
        Call_PushString("");
        Call_PushCell(false);
        Call_Finish();
    }

    CloseHandle(socket);
}

// Code by Exolent[jNr]
// https://forums.alliedmods.net/showpost.php?p=1078411&postcount=3

stock void EasyHTTP_URLEncode(const char[] szInput, char[] szOutput, const int iLen)
{
    static const HEXCHARS[ 16 ] = {
            0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
            0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66
    };

    int iPos, cChar, iFLen;
    while( ( cChar = szInput[ iPos ] ) && iFLen < iLen )
    {
        if( cChar == 0x20 )
            szOutput[ iFLen++ ] = 0x2B;
        else if( !( 0x41 <= cChar <= 0x5A )
            && !( 0x61 <= cChar <= 0x7A )
            && !( 0x30 <= cChar <= 0x39 )
            && cChar != 0x2D
            && cChar != 0x2E
            && cChar != 0x5F )
        {

            if( ( iFLen + 3 ) > iLen )
                break;
            else if( cChar > 0xFF
                 || cChar < 0x00 )
                cChar = 0x2A;

            szOutput[ iFLen++ ] = 0x25;
            szOutput[ iFLen++ ] = HEXCHARS[ cChar >> 4 ];
            szOutput[ iFLen++ ] = HEXCHARS[ cChar & 15 ];
        }
        else
            szOutput[ iFLen++ ] = cChar;

        iPos++;
    }

    szOutput[ iFLen ] = 0;
    return iFLen;
}
stock void EasyHTTP_MarkNatives()
{
        // Mark Socket natives as optional
    MarkNativeAsOptional("SocketIsConnected");
    MarkNativeAsOptional("SocketCreate");
    MarkNativeAsOptional("SocketBind");
    MarkNativeAsOptional("SocketConnect");
    MarkNativeAsOptional("SocketDisconnect");
    MarkNativeAsOptional("SocketListen");
    MarkNativeAsOptional("SocketSend");
    MarkNativeAsOptional("SocketSendTo");
    MarkNativeAsOptional("SocketSetOption");
    MarkNativeAsOptional("SocketSetReceiveCallback");
    MarkNativeAsOptional("SocketSetSendqueueEmptyCallback");
    MarkNativeAsOptional("SocketSetDisconnectCallback");
    MarkNativeAsOptional("SocketSetErrorCallback");
    MarkNativeAsOptional("SocketSetArg");
    MarkNativeAsOptional("SocketGetHostName");

    // Mark SteamWorks natives as optional
    MarkNativeAsOptional("SteamWorks_IsVACEnabled");
    MarkNativeAsOptional("SteamWorks_GetPublicIP");
    MarkNativeAsOptional("SteamWorks_GetPublicIPCell");
    MarkNativeAsOptional("SteamWorks_IsLoaded");
    MarkNativeAsOptional("SteamWorks_SetGameDescription");
    MarkNativeAsOptional("SteamWorks_IsConnected");
    MarkNativeAsOptional("SteamWorks_SetRule");
    MarkNativeAsOptional("SteamWorks_ClearRules");
    MarkNativeAsOptional("SteamWorks_ForceHeartbeat");

    MarkNativeAsOptional("SteamWorks_HasLicenseForApp");
    MarkNativeAsOptional("SteamWorks_GetClientSteamID");

    MarkNativeAsOptional("SteamWorks_RequestStatsAuthID");
    MarkNativeAsOptional("SteamWorks_RequestStats");
    MarkNativeAsOptional("SteamWorks_GetStatCell");
    MarkNativeAsOptional("SteamWorks_GetStatAuthIDCell");
    MarkNativeAsOptional("SteamWorks_GetStatFloat");
    MarkNativeAsOptional("SteamWorks_GetStatAuthIDFloat");

    MarkNativeAsOptional("SteamWorks_CreateHTTPRequest");
    MarkNativeAsOptional("SteamWorks_SetHTTPRequestContextValue");
    MarkNativeAsOptional("SteamWorks_SetHTTPRequestNetworkActivityTimeout");
    MarkNativeAsOptional("SteamWorks_SetHTTPRequestHeaderValue");
    MarkNativeAsOptional("SteamWorks_SetHTTPRequestGetOrPostParameter");

    MarkNativeAsOptional("SteamWorks_SetHTTPCallbacks");
    MarkNativeAsOptional("SteamWorks_SendHTTPRequest");
    MarkNativeAsOptional("SteamWorks_SendHTTPRequestAndStreamResponse");
    MarkNativeAsOptional("SteamWorks_DeferHTTPRequest");
    MarkNativeAsOptional("SteamWorks_PrioritizeHTTPRequest");
    MarkNativeAsOptional("SteamWorks_GetHTTPResponseHeaderSize");
    MarkNativeAsOptional("SteamWorks_GetHTTPResponseHeaderValue");
    MarkNativeAsOptional("SteamWorks_GetHTTPResponseBodySize");
    MarkNativeAsOptional("SteamWorks_GetHTTPResponseBodyData");
    MarkNativeAsOptional("SteamWorks_GetHTTPStreamingResponseBodyData");
    MarkNativeAsOptional("SteamWorks_GetHTTPDownloadProgressPct");
    MarkNativeAsOptional("SteamWorks_SetHTTPRequestRawPostBody");

    MarkNativeAsOptional("SteamWorks_GetHTTPResponseBodyCallback");
    MarkNativeAsOptional("SteamWorks_WriteHTTPResponseBodyToFile");

    // Mark SteamTools natives as optional
    MarkNativeAsOptional("Steam_IsVACEnabled");
    MarkNativeAsOptional("Steam_GetPublicIP");
    MarkNativeAsOptional("Steam_RequestGroupStatus");
    MarkNativeAsOptional("Steam_RequestGameplayStats");
    MarkNativeAsOptional("Steam_RequestServerReputation");
    MarkNativeAsOptional("Steam_IsConnected");
    MarkNativeAsOptional("Steam_SetRule");
    MarkNativeAsOptional("Steam_ClearRules");
    MarkNativeAsOptional("Steam_ForceHeartbeat");
    MarkNativeAsOptional("Steam_AddMasterServer");
    MarkNativeAsOptional("Steam_RemoveMasterServer");
    MarkNativeAsOptional("Steam_GetNumMasterServers");
    MarkNativeAsOptional("Steam_GetMasterServerAddress");
    MarkNativeAsOptional("Steam_SetGameDescription");
    MarkNativeAsOptional("Steam_RequestStats");
    MarkNativeAsOptional("Steam_GetStat");
    MarkNativeAsOptional("Steam_GetStatFloat");
    MarkNativeAsOptional("Steam_IsAchieved");
    MarkNativeAsOptional("Steam_GetNumClientSubscriptions");
    MarkNativeAsOptional("Steam_GetClientSubscription");
    MarkNativeAsOptional("Steam_GetNumClientDLCs");
    MarkNativeAsOptional("Steam_GetClientDLC");
    MarkNativeAsOptional("Steam_GetCSteamIDForClient");
    MarkNativeAsOptional("Steam_SetCustomSteamID");
    MarkNativeAsOptional("Steam_GetCustomSteamID");
    MarkNativeAsOptional("Steam_RenderedIDToCSteamID");
    MarkNativeAsOptional("Steam_CSteamIDToRenderedID");
    MarkNativeAsOptional("Steam_GroupIDToCSteamID");
    MarkNativeAsOptional("Steam_CSteamIDToGroupID");
    MarkNativeAsOptional("Steam_CreateHTTPRequest");
    MarkNativeAsOptional("Steam_SetHTTPRequestNetworkActivityTimeout");
    MarkNativeAsOptional("Steam_SetHTTPRequestHeaderValue");
    MarkNativeAsOptional("Steam_SetHTTPRequestGetOrPostParameter");
    MarkNativeAsOptional("Steam_SendHTTPRequest");
    MarkNativeAsOptional("Steam_DeferHTTPRequest");
    MarkNativeAsOptional("Steam_PrioritizeHTTPRequest");
    MarkNativeAsOptional("Steam_GetHTTPResponseHeaderSize");
    MarkNativeAsOptional("Steam_GetHTTPResponseHeaderValue");
    MarkNativeAsOptional("Steam_GetHTTPResponseBodySize");
    MarkNativeAsOptional("Steam_GetHTTPResponseBodyData");
    MarkNativeAsOptional("Steam_WriteHTTPResponseBody");
    MarkNativeAsOptional("Steam_ReleaseHTTPRequest");
    MarkNativeAsOptional("Steam_GetHTTPDownloadProgressPercent");

    // Mark cURL natives as optional
    MarkNativeAsOptional("curl_easy_init");
    MarkNativeAsOptional("curl_easy_setopt_string");
    MarkNativeAsOptional("curl_easy_setopt_int");
    MarkNativeAsOptional("curl_easy_setopt_int_array");
    MarkNativeAsOptional("curl_easy_setopt_int64");
    MarkNativeAsOptional("curl_OpenFile");
    MarkNativeAsOptional("curl_httppost");
    MarkNativeAsOptional("curl_slist");
    MarkNativeAsOptional("curl_easy_setopt_handle");
    MarkNativeAsOptional("curl_easy_setopt_functio    n");
    MarkNativeAsOptional("curl_load_opt");
    MarkNativeAsOptional("curl_easy_perform");
    MarkNativeAsOptional("curl_easy_perform_thread");
    MarkNativeAsOptional("curl_easy_send_recv");
    MarkNativeAsOptional("curl_send_recv_Signal");
    MarkNativeAsOptional("curl_send_recv_IsWaiting");
    MarkNativeAsOptional("curl_set_send_buffer");
    MarkNativeAsOptional("curl_set_receive_size");
    MarkNativeAsOptional("curl_set_send_timeout");
    MarkNativeAsOptional("curl_set_recv_timeout");
    MarkNativeAsOptional("curl_get_error_buffer");
    MarkNativeAsOptional("curl_easy_getinfo_string");
    MarkNativeAsOptional("curl_easy_getinfo_int");
    MarkNativeAsOptional("curl_easy_escape");
    MarkNativeAsOptional("curl_easy_unescape");
    MarkNativeAsOptional("curl_easy_strerror");
    MarkNativeAsOptional("curl_version");
    MarkNativeAsOptional("curl_protocols");
    MarkNativeAsOptional("curl_features");
    MarkNativeAsOptional("curl_OpenFile");
    MarkNativeAsOptional("curl_httppost");
    MarkNativeAsOptional("curl_formadd");
    MarkNativeAsOptional("curl_slist");
    MarkNativeAsOptional("curl_slist_append");
    MarkNativeAsOptional("curl_hash_file");
    MarkNativeAsOptional("curl_hash_string");
    MarkNativeAsOptional("curl_easy_setopt_function");
}
