#include "vgui_cache_buster/usermessage_bitbuf.sp"
#include "vgui_cache_buster/usermessage_protobuf.sp"

/**
 * Display an info panel with the specified KeyValues data, bypassing all hooks.
 */
void ShowInfoPanelBlockHooks(const int[] players, int nPlayers, KeyValues kv, bool show) {
    // thx sm
    int players_nonconst[MAXPLAYERS];
    for (int i = 0; i < nPlayers; i++) {
        players_nonconst[i] = players[i];
    }
    
    int flags = USERMSG_RELIABLE;
    int nSubKeys;
    if (kv.GotoFirstSubKey(false)) {
        do {
            nSubKeys++;
        } while (kv.GotoNextKey(false));
        kv.GoBack();
    }
    
    KeyValues kvMessage = new KeyValues("VGUIMessage");
    kvMessage.SetNum("show", show);
    kvMessage.SetNum("num_subkeys", nSubKeys);
    kvMessage.JumpToKey("subkeys", true);
    
    kvMessage.Import(kv);
    
    UserMessageType messageType = GetUserMessageType();
    switch (messageType) {
        case UM_BitBuf: {
            BitBuf_KeyValuesToVGUIMessage(players_nonconst, nPlayers, flags, kvMessage);
        }
        case UM_Protobuf: {
            Protobuf_KeyValuesToVGUIMessage(players_nonconst, nPlayers, flags, kvMessage);
        }
        default: {
            LogError("Plugin does not implement KV to usermessage type %d", messageType);
        }
    }
    
    delete kvMessage;
}
