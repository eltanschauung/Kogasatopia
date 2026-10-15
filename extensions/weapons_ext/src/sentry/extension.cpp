#include "extension.h"
#include "modules.h"
#include "range_override.h"

#include <cstring>

TF2SentryNewTargetExt g_TF2SentryNewTargetExt;
IGameConfig *g_SentryGameConf = nullptr;

SMEXT_LINK(&g_TF2SentryNewTargetExt);
SDKExtension &SentryModule() { return g_TF2SentryNewTargetExt; }

extern sp_nativeinfo_t g_TF2SentryNewTargetNatives[];

bool TF2SentryNewTargetExt::SDK_OnLoad(char *error, size_t maxlength, bool late)
{
    if (std::strcmp(g_pSM->GetGameFolderName(), "tf") != 0)
    {
        ke::SafeSprintf(error, maxlength, "This extension only supports Team Fortress 2.");
        return false;
    }

    char confError[255] = "";
    if (!gameconfs->LoadGameConfigFile(WEAPONS_GAMECONFIG_NAME, &g_SentryGameConf, confError, sizeof(confError)))
    {
        if (confError[0])
            ke::SafeSprintf(error, maxlength, "Could not load weapons.games.txt: %s", confError);
        else
            ke::SafeSprintf(error, maxlength, "Could not load weapons.games.txt");
        return false;
    }

    CDetourManager::Init(g_pSM->GetScriptingEngine(), g_SentryGameConf);

    if (!SentryRangeOverride::Init(g_SentryGameConf, error, maxlength))
        return false;

    sharesys->AddNatives(myself, g_TF2SentryNewTargetNatives);

    return true;
}

void TF2SentryNewTargetExt::SDK_OnUnload()
{
    SentryRangeOverride::Shutdown();

    if (g_SentryGameConf)
    {
        gameconfs->CloseGameConfigFile(g_SentryGameConf);
        g_SentryGameConf = nullptr;
    }
}
