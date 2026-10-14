/**
 * Weapons dynamic schema configuration loader (originally nosoop's loader).
 *
 * Registers configured engine attributes; no standalone plugin/library shim.
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <tf_econ_dynamic>


static TF2EconDynAttribute s_AttributeContext;
bool g_WeaponsEconSkipInitialMapReload;

public void WeaponsEcon_OnPluginStart() {
	s_AttributeContext = new TF2EconDynAttribute();

	WeaponsEcon_CreateAttributeConfigParsers();
    WeaponsEcon_LoadAttributes();
    WeaponsAttrib_InvalidateDefinitions();
    g_WeaponsEconSkipInitialMapReload = true;
}

public void WeaponsEcon_OnMapStart() {
    if (g_WeaponsEconSkipInitialMapReload) {
        g_WeaponsEconSkipInitialMapReload = false;
        return;
    }
	// this loads relatively late, but it should be fine
	WeaponsEcon_LoadAttributes();
    WeaponsAttrib_InvalidateDefinitions();
}

enum HiddenAttributeConfigParseState {
	HiddenAttributeConfigParseState_Root,

	HiddenAttributeConfigParseState_AttributeList,
	HiddenAttributeConfigParseState_AttributeProperties,
}

static SMCParser s_HiddenDevAttributeParser;

static HiddenAttributeConfigParseState s_ParseState = HiddenAttributeConfigParseState_Root;
static int s_nParseStateIgnoreNestedSections;

void WeaponsEcon_CreateAttributeConfigParsers() {
	s_HiddenDevAttributeParser = new SMCParser();


	s_HiddenDevAttributeParser.OnStart = WeaponsEcon_OnAttributeConfigStartParse;
	s_HiddenDevAttributeParser.OnEnd = WeaponsEcon_OnAttributeConfigEndParse;

	s_HiddenDevAttributeParser.OnEnterSection = WeaponsEcon_OnAttributeConfigEnterSection;
	s_HiddenDevAttributeParser.OnLeaveSection = WeaponsEcon_OnAttributeConfigLeaveSection;

	s_HiddenDevAttributeParser.OnKeyValue = WeaponsEcon_OnAttributeConfigKeyValue;
}

void WeaponsEcon_OnAttributeConfigStartParse(SMCParser smc) {
	s_ParseState = HiddenAttributeConfigParseState_Root;
	s_nParseStateIgnoreNestedSections = 0;
}

/**
 * Push new parse state depending on the current section.
 */
SMCResult WeaponsEcon_OnAttributeConfigEnterSection(SMCParser smc, const char[] name, bool opt_quotes) {
	/**
	 * If we're ignoring a parent section, increment and don't emit a change in parse state.
	 */
	if (s_nParseStateIgnoreNestedSections) {
		s_nParseStateIgnoreNestedSections++;
		return SMCParse_Continue;
	}

	switch (s_ParseState) {
		case HiddenAttributeConfigParseState_Root: {
			if (StrEqual(name, "attributes", .caseSensitive = false)) {
				s_ParseState = HiddenAttributeConfigParseState_AttributeList;
			} else {
				LogError("Entering unexpected section '%s' while in parse state %d", name, s_ParseState);
				return SMCParse_HaltFail;
			}
		}
		case HiddenAttributeConfigParseState_AttributeList: {
			s_AttributeContext.Clear();

			int attrdef;
			if (StrEqual(name, "auto", .caseSensitive = false)) {
				// do nothing
			} else if (StringToIntEx(name, attrdef)) {
				s_AttributeContext.SetDefIndex(attrdef);
#if defined DEBUG
				LogMessage("Setting attribute context to itemdef %d", attrdef);
#endif
			} else {
				LogError("Attempting to declare attribute with invalid defindex '%s'", name);
				return SMCParse_HaltFail;
			}
			s_ParseState = HiddenAttributeConfigParseState_AttributeProperties;
		}
		case HiddenAttributeConfigParseState_AttributeProperties: {
			// ignore nested properties for now
			LogMessage("Warning: Nested keys are not currently supported");
			s_nParseStateIgnoreNestedSections++;
		}
		default: {
			LogError("Entering unexpected section '%s' while in parse state %d", name,
					s_ParseState);
			return SMCParse_HaltFail;
		}
	}
	return SMCParse_Continue;
}

/**
 * Pop parse state and go back to previous one.
 */
SMCResult WeaponsEcon_OnAttributeConfigLeaveSection(SMCParser smc) {
	/**
	 * If we're leaving an ignored section, decrement and don't emit a change in parse state.
	 */
	if (s_nParseStateIgnoreNestedSections) {
		s_nParseStateIgnoreNestedSections--;
		return SMCParse_Continue;
	}

	switch (s_ParseState) {
		case HiddenAttributeConfigParseState_AttributeProperties: {
			s_ParseState = HiddenAttributeConfigParseState_AttributeList;
			s_AttributeContext.Register();
		}
		case HiddenAttributeConfigParseState_AttributeList: {
			s_ParseState = HiddenAttributeConfigParseState_Root;
		}
		case HiddenAttributeConfigParseState_Root: {
			LogError("Leaving section while in root parse state");
		}
		default: {
			LogError("Leaving section while in parse state %d", s_ParseState);
		}
	}
	return SMCParse_Continue;
}

SMCResult WeaponsEcon_OnAttributeConfigKeyValue(SMCParser smc, const char[] key, const char[] value,
		bool key_quotes, bool value_quotes) {
	switch (s_ParseState) {
		case HiddenAttributeConfigParseState_AttributeProperties: {
			s_AttributeContext.SetCustom(key, value);
#if defined DEBUG
			LogMessage("Adding attribute context key / value: '%s' = '%s'", key, value);
#endif
		}
		default: {
			LogError("Unexpected key / value pair while in parse state %d", s_ParseState);
		}
	}
	return SMCParse_Continue;
}

void WeaponsEcon_OnAttributeConfigEndParse(SMCParser smc, bool halted, bool failed) {
	if (halted || failed) {
		return;
	}

	if (s_ParseState != HiddenAttributeConfigParseState_Root) {
		LogError("Parse state not at root on end parse");
	}
}

void WeaponsEcon_LoadAttributes() {
	char configDir[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, configDir, sizeof(configDir), "configs/tf2nativeattribs");

	if (!DirExists(configDir, false)) {
		return;
	}

	DirectoryListing list = OpenDirectory(configDir, false);
	FileType fileType;
	char filename[PLATFORM_MAX_PATH];

	while (list.GetNext(filename, sizeof(filename), fileType)) {
		if (fileType != FileType_File) {
			continue;
		}

		Format(filename, sizeof(filename), "%s/%s", configDir, filename);

		if (strlen(filename) < 4 || strncmp(filename[strlen(filename) - 4], ".txt", 4, false) != 0) {
			PrintToServer("[TF2 Econ Dynamic] "
					... "Attributes file %s does not have a txt extension. "
					... "Attributes will not be loaded",
					filename);
			continue;
		}

		if (s_HiddenDevAttributeParser.ParseFile(filename) != SMCError_Okay) {
			PrintToServer("[TF2 Econ Dynamic] "
					... "Failed to load file %s. Attributes will not be loaded",
					filename);
		}
	}
	delete list;
}
