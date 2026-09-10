void LoadLotteryWords()
{
    g_LotteryWords.Clear();
    g_LotteryRarities.Clear();
    g_LotteryTotalWeight = 0;

    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), "configs/points_store.cfg");

    File file = OpenFile(configPath, "r");
    if (file == null)
    {
        LogError("[points_store] Could not open %s for lottery words.", configPath);
        return;
    }

    bool inLottery = false;
    int depth = 0;
    char line[256];
    while (!IsEndOfFile(file) && ReadFileLine(file, line, sizeof(line)))
    {
        StripLineComment(line);
        TrimString(line);
        if (line[0] == '\0')
        {
            continue;
        }

        if (!inLottery)
        {
            char section[64];
            if (ExtractFirstQuotedToken(line, section, sizeof(section)) && StrEqual(section, "lottery", false))
            {
                inLottery = true;
                if (StrContains(line, "{") != -1)
                {
                    depth = 1;
                }
            }
            continue;
        }

        if (StrContains(line, "{") != -1)
        {
            depth++;
            continue;
        }

        if (StrContains(line, "}") != -1)
        {
            depth--;
            if (depth <= 0)
            {
                break;
            }
            continue;
        }

        if (depth <= 0)
        {
            continue;
        }

        char word[LOTTO_WORD_MAX];
        char rarityText[16];
        if (!ExtractTwoQuotedTokens(line, word, sizeof(word), rarityText, sizeof(rarityText)))
        {
            continue;
        }

        TrimString(word);
        TrimString(rarityText);
        int rarity = StringToInt(rarityText);
        if (rarity < 1)
        {
            rarity = 1;
        }
        else if (rarity > 3)
        {
            rarity = 3;
        }

        if (word[0] != '\0')
        {
            g_LotteryWords.PushString(word);
            g_LotteryRarities.Push(rarity);
            g_LotteryTotalWeight += GetLotteryRarityWeight(rarity);
        }
    }

    delete file;
    LogMessage("[points_store] Loaded %d lottery word(s).", g_LotteryWords.Length);
}

void StripLineComment(char[] line)
{
    bool inQuote = false;
    int len = strlen(line);
    for (int i = 0; i < len; i++)
    {
        if (line[i] == '"')
        {
            inQuote = !inQuote;
            continue;
        }

        if (!inQuote && line[i] == '/' && i + 1 < len && line[i + 1] == '/')
        {
            line[i] = '\0';
            return;
        }
    }
}

bool ExtractFirstQuotedToken(const char[] text, char[] token, int tokenLen)
{
    int pos = 0;
    return ReadQuotedToken(text, pos, token, tokenLen);
}

bool ExtractTwoQuotedTokens(const char[] text, char[] first, int firstLen, char[] second, int secondLen)
{
    int pos = 0;
    return ReadQuotedToken(text, pos, first, firstLen) && ReadQuotedToken(text, pos, second, secondLen);
}

bool ReadQuotedToken(const char[] text, int &pos, char[] token, int tokenLen)
{
    token[0] = '\0';
    int len = strlen(text);
    while (pos < len && text[pos] != '"')
    {
        pos++;
    }

    if (pos >= len)
    {
        return false;
    }

    pos++;
    int out = 0;
    while (pos < len && text[pos] != '"')
    {
        if (out < tokenLen - 1)
        {
            token[out++] = text[pos];
        }
        pos++;
    }
    token[out] = '\0';

    if (pos >= len)
    {
        return false;
    }

    pos++;
    return true;
}

