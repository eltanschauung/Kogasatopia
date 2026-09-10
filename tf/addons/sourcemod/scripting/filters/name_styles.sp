void BuildTeamTag(int team, char[] tag, int length)
{
    switch (team)
    {
        case 3: strcopy(tag, length, "(輝夜)");
        case 2: strcopy(tag, length, "(妹紅)");
        default: strcopy(tag, length, "(永琳)");
    }
}

void ToLowercase(char[] text)
{
    for (int i = 0; text[i] != '\0'; i++)
    {
        text[i] = CharToLower(text[i]);
    }
}

void BuildNameColorTag(int client, char[] colorTag, int length)
{
    if (g_NameColors[client][0] != '\0')
    {
        Format(colorTag, length, "{%s}", g_NameColors[client]);
    }
    else
    {
        strcopy(colorTag, length, "{teamcolor}");
    }
}

bool Filters_FindClientBySteamId64(const char[] steamId, int &client)
{
    client = Kogasa_FindClientBySteamId64(steamId, true);
    return client > 0;
}

bool Filters_GetClientColorToken(int client, char[] colorTag, int maxlen)
{
    colorTag[0] = '\0';

    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return false;
    }

    char formattedTag[40];
    BuildNameColorTag(client, formattedTag, sizeof(formattedTag));
    TrimString(formattedTag);
    if (!formattedTag[0])
    {
        return false;
    }

    int length = strlen(formattedTag);
    if (length >= 3 && formattedTag[0] == '{' && formattedTag[length - 1] == '}')
    {
        formattedTag[length - 1] = '\0';
        strcopy(colorTag, maxlen, formattedTag[1]);
        return (colorTag[0] != '\0');
    }

    strcopy(colorTag, maxlen, formattedTag);
    return (colorTag[0] != '\0');
}

void BuildMessageColorTag(int client, char[] colorTag, int length)
{
    if (g_hFiltersChristmas != null && g_hFiltersChristmas.BoolValue)
    {
        int team = GetClientTeam(client);
        if (team == 3)
        {
            strcopy(colorTag, length, "{lightgreen}");
            return;
        }
        if (team == 2)
        {
            strcopy(colorTag, length, "{tomato}");
            return;
        }
    }

    strcopy(colorTag, length, "{default}");
}

bool IsAmericaNamePattern(const char[] pattern)
{
    return StrEqual(pattern, NAME_COLOR_AMERICA, false);
}

bool IsMapNamePattern(const char[] pattern)
{
    return StrEqual(pattern, NAME_PATTERN_MAP, false);
}

bool IsTransNamePattern(const char[] pattern)
{
    return StrEqual(pattern, NAME_PATTERN_TRANS, false);
}

bool IsRainbowNamePattern(const char[] pattern)
{
    return StrEqual(pattern, NAME_PATTERN_RAINBOW, false);
}

bool ParseGradientNamePattern(
    const char[] pattern,
    char[] firstColor,
    int firstLen,
    char[] secondColor,
    int secondLen,
    int &completionPercent)
{
    firstColor[0] = '\0';
    secondColor[0] = '\0';
    completionPercent = NAME_GRADIENT_DEFAULT_COMPLETION;
    if (StrContains(pattern, NAME_PATTERN_GRADIENT_PREFIX, false) != 0)
    {
        return false;
    }

    char colors[NAME_PATTERN_MAX];
    strcopy(colors, sizeof(colors), pattern[strlen(NAME_PATTERN_GRADIENT_PREFIX)]);
    int separator = FindCharInString(colors, ':');
    if (separator <= 0 || !colors[separator + 1])
    {
        return false;
    }

    colors[separator] = '\0';
    strcopy(firstColor, firstLen, colors);

    char remainder[NAME_PATTERN_MAX];
    strcopy(remainder, sizeof(remainder), colors[separator + 1]);
    int percentageSeparator = FindCharInString(remainder, ':');
    if (percentageSeparator == -1)
    {
        strcopy(secondColor, secondLen, remainder);
    }
    else
    {
        remainder[percentageSeparator] = '\0';
        strcopy(secondColor, secondLen, remainder);

        char percentageText[8];
        strcopy(percentageText, sizeof(percentageText), remainder[percentageSeparator + 1]);
        int parsedLength = StringToIntEx(percentageText, completionPercent);
        if (parsedLength <= 0
            || percentageText[parsedLength] != '\0'
            || completionPercent <= 0
            || completionPercent > NAME_GRADIENT_MAX_COMPLETION)
        {
            return false;
        }
    }
    TrimString(firstColor);
    TrimString(secondColor);
    ToLowercase(firstColor);
    ToLowercase(secondColor);
    return firstColor[0] != '\0'
        && secondColor[0] != '\0'
        && CColorExists(firstColor)
        && CColorExists(secondColor);
}

static bool IsGradientNamePattern(const char[] pattern)
{
    char firstColor[32];
    char secondColor[32];
    int completionPercent;
    return ParseGradientNamePattern(pattern, firstColor, sizeof(firstColor), secondColor, sizeof(secondColor), completionPercent);
}

static bool ParseTripleGradientNamePattern(
    const char[] pattern,
    char[] firstColor,
    int firstLen,
    char[] secondColor,
    int secondLen,
    char[] thirdColor,
    int thirdLen)
{
    firstColor[0] = '\0';
    secondColor[0] = '\0';
    thirdColor[0] = '\0';
    if (StrContains(pattern, NAME_PATTERN_TRIPLE_GRADIENT_PREFIX, false) != 0)
    {
        return false;
    }

    char colors[3][32];
    int count = ExplodeString(
        pattern[strlen(NAME_PATTERN_TRIPLE_GRADIENT_PREFIX)],
        ":",
        colors,
        sizeof(colors),
        sizeof(colors[]));
    if (count != 3)
    {
        return false;
    }

    for (int i = 0; i < sizeof(colors); i++)
    {
        TrimString(colors[i]);
        ToLowercase(colors[i]);
        if (!colors[i][0] || !CColorExists(colors[i]))
        {
            return false;
        }
    }

    strcopy(firstColor, firstLen, colors[0]);
    strcopy(secondColor, secondLen, colors[1]);
    strcopy(thirdColor, thirdLen, colors[2]);
    return true;
}

bool IsTripleGradientNamePattern(const char[] pattern)
{
    char firstColor[32];
    char secondColor[32];
    char thirdColor[32];
    return ParseTripleGradientNamePattern(
        pattern,
        firstColor,
        sizeof(firstColor),
        secondColor,
        sizeof(secondColor),
        thirdColor,
        sizeof(thirdColor));
}

bool IsValidNamePattern(const char[] pattern)
{
    return IsAmericaNamePattern(pattern)
        || IsMapNamePattern(pattern)
        || IsTransNamePattern(pattern)
        || IsRainbowNamePattern(pattern)
        || IsGradientNamePattern(pattern)
        || IsTripleGradientNamePattern(pattern);
}

bool HasValidNamePattern(int client)
{
    return IsValidNamePattern(g_NamePatterns[client]);
}

static bool GetActiveNamePattern(int client, char[] pattern, int maxlen)
{
    pattern[0] = '\0';

    if (!HasValidNamePattern(client))
    {
        return false;
    }

    strcopy(pattern, maxlen, g_NamePatterns[client]);
    return true;
}

static bool GetNamedColorRgb(const char[] colorName, int &rgb)
{
    CCheckTrie();
    return GetTrieValue(CTrie, colorName, rgb);
}

static void BuildGradientName(
    const char[] name,
    const char[] firstColor,
    const char[] secondColor,
    int completionPercent,
    char[] output,
    int maxlen)
{
    output[0] = '\0';

    int firstRgb;
    int secondRgb;
    if (!GetNamedColorRgb(firstColor, firstRgb) || !GetNamedColorRgb(secondColor, secondRgb))
    {
        strcopy(output, maxlen, name);
        return;
    }

    int charCount = CountUtf8Chars(name);
    if (charCount <= 0)
    {
        strcopy(output, maxlen, "{default}");
        return;
    }

    int firstRed = (firstRgb >> 16) & 0xFF;
    int firstGreen = (firstRgb >> 8) & 0xFF;
    int firstBlue = firstRgb & 0xFF;
    int secondRed = (secondRgb >> 16) & 0xFF;
    int secondGreen = (secondRgb >> 8) & 0xFF;
    int secondBlue = secondRgb & 0xFF;
    int stepCount = charCount < NAME_GRADIENT_MAX_STEPS ? charCount : NAME_GRADIENT_MAX_STEPS;
    int denominator = stepCount > 1 ? stepCount - 1 : 1;
    int completionIndex = charCount > 1
        ? RoundToCeil(float(charCount - 1) * float(completionPercent) / 100.0)
        : 1;
    int currentStep = -1;
    int charIndex = 0;
    int byteIndex = 0;

    while (name[byteIndex] != '\0')
    {
        int step = charCount > 1 ? charIndex * (stepCount - 1) / completionIndex : 0;
        if (step >= stepCount)
        {
            step = stepCount - 1;
        }
        if (step != currentStep)
        {
            int red = (firstRed * (denominator - step) + secondRed * step + denominator / 2) / denominator;
            int green = (firstGreen * (denominator - step) + secondGreen * step + denominator / 2) / denominator;
            int blue = (firstBlue * (denominator - step) + secondBlue * step + denominator / 2) / denominator;
            int rgb = (red << 16) | (green << 8) | blue;

            char colorCode[8];
            FormatEx(colorCode, sizeof(colorCode), "\x07%06X", rgb);
            StrCat(output, maxlen, colorCode);
            currentStep = step;
        }

        int charBytes = IsCharMB(name[byteIndex]);
        if (charBytes <= 0)
        {
            charBytes = 1;
        }

        char glyph[8];
        int copyLen = charBytes;
        if (copyLen > sizeof(glyph) - 1)
        {
            copyLen = sizeof(glyph) - 1;
        }
        for (int i = 0; i < copyLen; i++)
        {
            glyph[i] = name[byteIndex + i];
        }
        glyph[copyLen] = '\0';
        StrCat(output, maxlen, glyph);

        byteIndex += charBytes;
        charIndex++;
    }

    StrCat(output, maxlen, "\x01");
}

static void BuildTripleGradientName(
    const char[] name,
    const char[] firstColor,
    const char[] secondColor,
    const char[] thirdColor,
    char[] output,
    int maxlen)
{
    output[0] = '\0';

    int rgbStops[3];
    if (!GetNamedColorRgb(firstColor, rgbStops[0])
        || !GetNamedColorRgb(secondColor, rgbStops[1])
        || !GetNamedColorRgb(thirdColor, rgbStops[2]))
    {
        strcopy(output, maxlen, name);
        return;
    }

    int charCount = CountUtf8Chars(name);
    if (charCount <= 0)
    {
        strcopy(output, maxlen, "{default}");
        return;
    }

    int stepCount = charCount < NAME_GRADIENT_MAX_STEPS ? charCount : NAME_GRADIENT_MAX_STEPS;
    int denominator = stepCount > 1 ? stepCount - 1 : 1;
    int currentStep = -1;
    int charIndex = 0;
    int byteIndex = 0;

    while (name[byteIndex] != '\0')
    {
        int step = charCount > 1 ? charIndex * (stepCount - 1) / (charCount - 1) : 0;
        if (step != currentStep)
        {
            int scaledStep = step * 2;
            int firstStop = scaledStep <= denominator ? 0 : 1;
            int secondStop = firstStop + 1;
            int blend = firstStop == 0 ? scaledStep : scaledStep - denominator;
            int fromRgb = rgbStops[firstStop];
            int toRgb = rgbStops[secondStop];
            int red = ((((fromRgb >> 16) & 0xFF) * (denominator - blend))
                + (((toRgb >> 16) & 0xFF) * blend) + denominator / 2) / denominator;
            int green = ((((fromRgb >> 8) & 0xFF) * (denominator - blend))
                + (((toRgb >> 8) & 0xFF) * blend) + denominator / 2) / denominator;
            int blue = (((fromRgb & 0xFF) * (denominator - blend))
                + ((toRgb & 0xFF) * blend) + denominator / 2) / denominator;
            AppendRgbColorCode((red << 16) | (green << 8) | blue, output, maxlen);
            currentStep = step;
        }

        int charBytes = IsCharMB(name[byteIndex]);
        if (charBytes <= 0)
        {
            charBytes = 1;
        }
        char glyph[8];
        int copyLen = charBytes < sizeof(glyph) ? charBytes : sizeof(glyph) - 1;
        for (int i = 0; i < copyLen; i++)
        {
            glyph[i] = name[byteIndex + i];
        }
        glyph[copyLen] = '\0';
        StrCat(output, maxlen, glyph);
        byteIndex += charBytes;
        charIndex++;
    }

    StrCat(output, maxlen, "\x01");
}

void SetNameColorPreference(int client, const char[] color)
{
    strcopy(g_NameColors[client], sizeof(g_NameColors[]), color);
    g_NamePatterns[client][0] = '\0';
    SaveNamePreferencesToDb(client);
}

void SetNamePatternPreference(int client, const char[] pattern)
{
    strcopy(g_NamePatterns[client], sizeof(g_NamePatterns[]), pattern);
    SaveNamePreferencesToDb(client);
}

void ClearNamePatternPreference(int client)
{
    g_NamePatterns[client][0] = '\0';
    SaveNamePreferencesToDb(client);
}

void ResetNamePreferences(int client)
{
    g_NamePatterns[client][0] = '\0';
    g_NameColors[client][0] = '\0';
    SaveNamePreferencesToDb(client);
}

static int CountUtf8Chars(const char[] text)
{
    int count = 0;
    int index = 0;

    while (text[index] != '\0')
    {
        int charBytes = IsCharMB(text[index]);
        if (charBytes <= 0)
        {
            charBytes = 1;
        }

        index += charBytes;
        count++;
    }

    return count;
}

static void AppendRgbColorCode(int rgb, char[] output, int maxlen)
{
    char colorCode[8];
    FormatEx(colorCode, sizeof(colorCode), "\x07%06X", rgb);
    StrCat(output, maxlen, colorCode);
}

static void BuildPaletteName(const char[] name, const int[] colors, int colorCount, char[] output, int maxlen)
{
    output[0] = '\0';

    int charCount = CountUtf8Chars(name);
    if (charCount <= 0 || colorCount <= 0)
    {
        strcopy(output, maxlen, "\x01");
        return;
    }

    int currentSegment = -1;
    int charIndex = 0;
    int byteIndex = 0;

    while (name[byteIndex] != '\0')
    {
        int segment = (charIndex * colorCount) / charCount;
        segment = segment < colorCount ? segment : colorCount - 1;

        if (segment != currentSegment)
        {
            AppendRgbColorCode(colors[segment], output, maxlen);
            currentSegment = segment;
        }

        int charBytes = IsCharMB(name[byteIndex]);
        if (charBytes <= 0)
        {
            charBytes = 1;
        }

        char glyph[8];
        int copyLen = charBytes;
        if (copyLen > sizeof(glyph) - 1)
        {
            copyLen = sizeof(glyph) - 1;
        }

        for (int i = 0; i < copyLen; i++)
        {
            glyph[i] = name[byteIndex + i];
        }
        glyph[copyLen] = '\0';
        StrCat(output, maxlen, glyph);

        byteIndex += charBytes;
        charIndex++;
    }

    StrCat(output, maxlen, "\x01");
}

static void BuildAmericaName(const char[] name, char[] output, int maxlen)
{
    int colors[] = {
        0xFFFFFF, 0x1E90FF, 0xFFFFFF, 0x1E90FF, 0xFFFFFF, 0x1E90FF,
        0xFF4040, 0xFF4040, 0xFFFFFF, 0xFFFFFF, 0xFF4040, 0xFF4040
    };
    BuildPaletteName(name, colors, sizeof(colors), output, maxlen);
}

static void BuildMapName(const char[] name, char[] output, int maxlen)
{
    int colors[] = {0x6495ED, 0x99CCFF, 0xFFFF5E, 0xFFFFFF, 0xFFFF5E, 0xFFC0CB, 0xFF69B4};
    BuildPaletteName(name, colors, sizeof(colors), output, maxlen);
}

static void BuildTransName(const char[] name, char[] output, int maxlen)
{
    int colors[] = {0x5BCEFA, 0xFFFFFF, 0xF5A9B8};
    BuildPaletteName(name, colors, sizeof(colors), output, maxlen);
}

static void BuildRainbowName(const char[] name, char[] output, int maxlen)
{
    int colors[] = {0xFF4040, 0xFFA500, 0xFFFF00, 0x3EFF3E, 0x99CCFF, 0x9370D8, 0xEE82EE};
    BuildPaletteName(name, colors, sizeof(colors), output, maxlen);
}

static bool BuildPatternedName(const char[] name, const char[] pattern, char[] output, int maxlen)
{
    if (IsAmericaNamePattern(pattern))
    {
        BuildAmericaName(name, output, maxlen);
        return true;
    }
    if (IsMapNamePattern(pattern))
    {
        BuildMapName(name, output, maxlen);
        return true;
    }
    if (IsTransNamePattern(pattern))
    {
        BuildTransName(name, output, maxlen);
        return true;
    }
    if (IsRainbowNamePattern(pattern))
    {
        BuildRainbowName(name, output, maxlen);
        return true;
    }

    char firstColor[32];
    char secondColor[32];
    char thirdColor[32];
    if (ParseTripleGradientNamePattern(
        pattern,
        firstColor,
        sizeof(firstColor),
        secondColor,
        sizeof(secondColor),
        thirdColor,
        sizeof(thirdColor)))
    {
        BuildTripleGradientName(name, firstColor, secondColor, thirdColor, output, maxlen);
        return true;
    }

    int completionPercent;
    if (ParseGradientNamePattern(pattern, firstColor, sizeof(firstColor), secondColor, sizeof(secondColor), completionPercent))
    {
        BuildGradientName(name, firstColor, secondColor, completionPercent, output, maxlen);
        return true;
    }

    return false;
}

void BuildRenderedStoredName(const char[] name, const char[] color, const char[] pattern, char[] output, int maxlen)
{
    output[0] = '\0';
    if (pattern[0] && BuildPatternedName(name, pattern, output, maxlen))
    {
        return;
    }

    if (color[0] && CColorExists(color))
    {
        Format(output, maxlen, "{%s}%s{default}", color, name);
        return;
    }

    Format(output, maxlen, "{default}%s", name);
}

void BuildRenderedClientName(int client, char[] output, int maxlen)
{
    output[0] = '\0';

    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return;
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));

    char pattern[NAME_PATTERN_MAX];
    if (GetActiveNamePattern(client, pattern, sizeof(pattern))
        && BuildPatternedName(name, pattern, output, maxlen))
    {
        return;
    }

    BuildColorOnlyClientName(client, output, maxlen);
}

static void BuildChatPrefix(int client, char[] output, int maxlen)
{
    output[0] = '\0';

    if (GetFeatureStatus(FeatureType_Native, "Tags_GetSelectedTag") != FeatureStatus_Available)
    {
        return;
    }

    if (!Tags_GetSelectedTag(client, output, maxlen) || !output[0])
    {
        output[0] = '\0';
    }
}

static void BuildDisplayChatPrefix(int client, char[] output, int maxlen)
{
    output[0] = '\0';

    char rawPrefix[CHAT_PREFIX_MAXLEN];
    BuildChatPrefix(client, rawPrefix, sizeof(rawPrefix));
    if (!rawPrefix[0])
    {
        return;
    }

    if (rawPrefix[0] == '[')
    {
        strcopy(output, maxlen, rawPrefix);
        return;
    }

    Format(output, maxlen, "[{gold}%s{default}]", rawPrefix);
}

static void BuildColorOnlyClientName(int client, char[] output, int maxlen)
{
    output[0] = '\0';

    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return;
    }

    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));

    char colorTag[40];
    BuildNameColorTag(client, colorTag, sizeof(colorTag));
    Format(output, maxlen, "%s%s{default}", colorTag, name);
}

void BuildChatDisplayName(int client, char[] output, int maxlen)
{
    output[0] = '\0';

    char chatPrefix[CHAT_PREFIX_MAXLEN];
    BuildDisplayChatPrefix(client, chatPrefix, sizeof(chatPrefix));

    char renderedName[256];
    BuildRenderedClientName(client, renderedName, sizeof(renderedName));

    if (chatPrefix[0])
    {
        Format(output, maxlen, "%s %s", chatPrefix, renderedName);
        return;
    }

    strcopy(output, maxlen, renderedName);
}

