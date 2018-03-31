/**
 * Creates and sends a VGUIMenu protocol buffer usermessage from a KeyValues struct.
 */
void Protobuf_KeyValuesToVGUIMessage(int[] players, int nPlayers, int flags, KeyValues kvMessage) {
    Protobuf buffer = view_as<Protobuf>(StartMessage("VGUIMenu", players, nPlayers,
            flags | USERMSG_BLOCKHOOKS));
    
    buffer.SetString("name", "info");
    buffer.SetBool("show", !!kvMessage.GetNum("show"));
    
    kvMessage.JumpToKey("subkeys", false);
    kvMessage.GotoFirstSubKey(false);
    
    char content[1024];
    do {
        Protobuf subkey = buffer.AddMessage("subkeys");
        
        // key
        kvMessage.GetSectionName(content, sizeof(content));
        subkey.SetString("name", content);
        
        // value
        kvMessage.GetString(NULL_STRING, content, sizeof(content));
        subkey.SetString("str", content);
    } while (kvMessage.GotoNextKey(false));
    kvMessage.GoBack();
    
    EndMessage();
}
