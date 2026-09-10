bool ValidateNativeStringLength(int param, int maxlen)
{
    int length;
    return GetNativeStringLength(param, length) == SP_ERROR_NONE && length > 0 && length < maxlen;
}

bool QueueConnectedNativeMail(int numParams, bool customTitle, bool currency)
{
    int sender = GetNativeCell(1);
    int receiver = GetNativeCell(2);
    if ((sender != 0 && !IsMailClient(sender)) || !IsMailClient(receiver))
    {
        return false;
    }

    int titleParam = customTitle ? 3 : 0;
    int contentsParam = customTitle ? 4 : 3;
    int gemsParam = currency ? 5 : 0;
    int requestParam = currency ? 6 : (customTitle ? 5 : 4);
    if (!ValidateNativeStringLength(contentsParam, MAIL_CONTENTS_MAX)
        || (customTitle && !ValidateNativeStringLength(titleParam, MAIL_TITLE_MAX)))
    {
        return false;
    }

    char senderSteam[MAIL_STEAMID_MAX];
    char senderName[MAIL_NAME_MAX];
    char receiverSteam[MAIL_STEAMID_MAX];
    char receiverName[MAIL_NAME_MAX];
    if (!GetMailClientIdentity(sender, senderSteam, sizeof(senderSteam), senderName, sizeof(senderName))
        || !GetMailClientIdentity(receiver, receiverSteam, sizeof(receiverSteam), receiverName, sizeof(receiverName)))
    {
        return false;
    }

    char title[MAIL_TITLE_MAX];
    char contents[MAIL_CONTENTS_MAX];
    char requestKey[MAIL_REQUEST_KEY_MAX];
    if (customTitle)
    {
        GetNativeString(titleParam, title, sizeof(title));
    }
    else
    {
        strcopy(title, sizeof(title), senderName);
    }
    GetNativeString(contentsParam, contents, sizeof(contents));
    requestKey[0] = '\0';
    if (numParams >= requestParam)
    {
        GetNativeString(requestParam, requestKey, sizeof(requestKey));
    }
    int gems = currency ? GetNativeCell(gemsParam) : 0;

    return QueueMailInsert(
        senderSteam,
        senderName,
        receiverSteam,
        receiverName,
        title,
        contents,
        gems,
        requestKey,
        sender > 0 ? GetClientUserId(sender) : 0,
        true);
}

bool QueueSteamNativeMail(int numParams, bool customTitle, bool currency)
{
    int titleParam = customTitle ? 4 : 0;
    int contentsParam = customTitle ? 5 : 4;
    int gemsParam = currency ? 6 : 0;
    int requestParam = currency ? 7 : (customTitle ? 6 : 5);
    if (!ValidateNativeStringLength(2, MAIL_NAME_MAX)
        || !ValidateNativeStringLength(3, MAIL_STEAMID_MAX)
        || !ValidateNativeStringLength(contentsParam, MAIL_CONTENTS_MAX)
        || (customTitle && !ValidateNativeStringLength(titleParam, MAIL_TITLE_MAX)))
    {
        return false;
    }

    char senderSteam[MAIL_STEAMID_MAX];
    char senderName[MAIL_NAME_MAX];
    char receiverSteam[MAIL_STEAMID_MAX];
    char receiverName[MAIL_NAME_MAX];
    char title[MAIL_TITLE_MAX];
    char contents[MAIL_CONTENTS_MAX];
    char requestKey[MAIL_REQUEST_KEY_MAX];
    GetNativeString(1, senderSteam, sizeof(senderSteam));
    GetNativeString(2, senderName, sizeof(senderName));
    GetNativeString(3, receiverSteam, sizeof(receiverSteam));

    int receiver = Kogasa_FindClientBySteamId64(receiverSteam);
    strcopy(receiverName, sizeof(receiverName), receiverSteam);
    if (IsMailClient(receiver))
    {
        GetClientName(receiver, receiverName, sizeof(receiverName));
    }
    else if (GetFeatureStatus(FeatureType_Native, "Filters_GetLastRecordedSteamName") == FeatureStatus_Available)
    {
        Filters_GetLastRecordedSteamName(receiverSteam, receiverName, sizeof(receiverName));
    }

    if (customTitle)
    {
        GetNativeString(titleParam, title, sizeof(title));
    }
    else
    {
        strcopy(title, sizeof(title), senderName);
    }
    GetNativeString(contentsParam, contents, sizeof(contents));
    requestKey[0] = '\0';
    if (numParams >= requestParam)
    {
        GetNativeString(requestParam, requestKey, sizeof(requestKey));
    }
    int gems = currency ? GetNativeCell(gemsParam) : 0;

    return QueueMailInsert(
        senderSteam,
        senderName,
        receiverSteam,
        receiverName,
        title,
        contents,
        gems,
        requestKey,
        0,
        true);
}

public any Native_ServerMail_Send(Handle plugin, int numParams)
{
    return QueueConnectedNativeMail(numParams, false, false);
}

public any Native_ServerMail_SendCustom(Handle plugin, int numParams)
{
    return QueueConnectedNativeMail(numParams, true, false);
}

public any Native_ServerMail_SendCurrency(Handle plugin, int numParams)
{
    return QueueConnectedNativeMail(numParams, true, true);
}

public any Native_ServerMail_SendSteamId(Handle plugin, int numParams)
{
    return QueueSteamNativeMail(numParams, false, false);
}

public any Native_ServerMail_SendCustomSteamId(Handle plugin, int numParams)
{
    return QueueSteamNativeMail(numParams, true, false);
}

public any Native_ServerMail_SendCurrencySteamId(Handle plugin, int numParams)
{
    return QueueSteamNativeMail(numParams, true, true);
}

