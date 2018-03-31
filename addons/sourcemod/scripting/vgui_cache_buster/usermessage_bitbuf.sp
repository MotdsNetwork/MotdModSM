/**
 * Creates and sends a VGUIMenu bitbuffer usermessage from a KeyValues struct.
 */
void BitBuf_KeyValuesToVGUIMessage(int[] players, int nPlayers, int flags, KeyValues kvMessage) {
    BfWrite buffer = view_as<BfWrite>(StartMessage("VGUIMenu", players, nPlayers,
            flags | USERMSG_BLOCKHOOKS));
    kvMessage.Rewind();
    
    buffer.WriteString("info");
    buffer.WriteByte(!!kvMessage.GetNum("show")); // bShow
    
    int count = kvMessage.GetNum("num_subkeys");
    buffer.WriteByte(count);
    
    kvMessage.JumpToKey("subkeys", false);
    kvMessage.GotoFirstSubKey(false);
    
    char content[1024];
    do {
        // key
        kvMessage.GetSectionName(content, sizeof(content));
        buffer.WriteString(content);
        
        // value
        kvMessage.GetString(NULL_STRING, content, sizeof(content));
        buffer.WriteString(content);
    } while (kvMessage.GotoNextKey(false));
    kvMessage.GoBack();
    
    EndMessage();
}
