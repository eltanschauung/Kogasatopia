/**
 * vim: set ts=4 :
 * =============================================================================
 * SourceMod Team Fortress 2 Extension
 * Copyright (C) 2004-2008 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

#include "criticals.h"
#include "util.h"
#include "shared_vtable_lifetime.h"

CritManager g_CritManager;

IForward *g_critForward = NULL;

SH_DECL_MANUALHOOK0(CalcIsAttackCriticalHelper, 0, 0, 0, bool);
SH_DECL_MANUALHOOK0(CalcIsAttackCriticalHelperNoCrits, 0, 0, 0, bool);

const char TF_WEAPON_DATATABLE[] = "DT_TFWeaponBase";

CON_COMMAND(sm_tf2tools_crit_hooks, "Report shared critical-hit hook coverage")
{
	g_CritManager.DumpHookStats();
}

void CritManager::DumpHookStats()
{
	int fallback = 0;
	for (int i = m_entsHooked.FindNextSetBit(playerhelpers->GetMaxClients() + 1);
		i != -1; i = m_entsHooked.FindNextSetBit(i + 1))
		fallback++;
	Msg("[TF2SharedCritHooks] enabled=%d shared_vtables=%u shared_hooks=%u private_entities=%d\n",
		m_enabled, static_cast<unsigned>(m_sharedHooks.size()),
		static_cast<unsigned>(m_sharedHooks.size() * 2), fallback);
}

CritManager::CritManager() :
	m_enabled(false),
	m_hooksSetup(false)
{
	m_entsHooked.Init();
}

bool CritManager::TryEnable()
{
	if (!m_hooksSetup)
	{
		int offset;

		if (!g_pGameConf->GetOffset("CalcIsAttackCriticalHelper", &offset))
		{
			g_pSM->LogError(myself, "Failed to find CalcIsAttackCriticalHelper offset");
			return false;
		}

		SH_MANUALHOOK_RECONFIGURE(CalcIsAttackCriticalHelper, offset, 0, 0);

		if (!g_pGameConf->GetOffset("CalcIsAttackCriticalHelperNoCrits", &offset))
		{
			g_pSM->LogError(myself, "Failed to find CalcIsAttackCriticalHelperNoCrits offset");
			return false;
		}

		SH_MANUALHOOK_RECONFIGURE(CalcIsAttackCriticalHelperNoCrits, offset, 0, 0);

		m_hooksSetup = true;
	}

	m_enabled = true;
	for (size_t i = playerhelpers->GetMaxClients() + 1; i < MAX_EDICTS; ++i)
	{
		CBaseEntity *pEntity = gamehelpers->ReferenceToEntity(i);
		if (pEntity == nullptr)
		{
			continue;
		}

		HookEntityIfWeapon(pEntity);
	}

	return true;
}

void CritManager::Disable()
{
	m_enabled = false;
	int i = m_entsHooked.FindNextSetBit(playerhelpers->GetMaxClients() + 1);
	for (i; i != -1; i = m_entsHooked.FindNextSetBit(i))
	{
		CBaseEntity *pEntity = gamehelpers->ReferenceToEntity(i);
		m_entsHooked.Set(i, false);
		if (pEntity != nullptr)
		{
			SH_REMOVE_MANUALHOOK(CalcIsAttackCriticalHelper, pEntity, SH_MEMBER(&g_CritManager, &CritManager::Hook_CalcIsAttackCriticalHelper), false);
			SH_REMOVE_MANUALHOOK(CalcIsAttackCriticalHelperNoCrits, pEntity, SH_MEMBER(&g_CritManager, &CritManager::Hook_CalcIsAttackCriticalHelperNoCrits), false);
		}
	}
	// No entity pointers are retained. These vtables belong to loaded modules,
	// so remove by SourceHook ID at forward disable/extension unload, not death.
	for (const SharedHooks &hooks : m_sharedHooks)
	{
		SH_REMOVE_HOOK_ID(hooks.critical);
		SH_REMOVE_HOOK_ID(hooks.noCrits);
	}
	m_sharedHooks.clear();
}

void CritManager::OnEntityCreated(CBaseEntity *pEntity, const char *classname)
{
	if (!m_enabled)
	{
		return;
	}
	HookEntityIfWeapon(pEntity);
}

void CritManager::HookEntityIfWeapon(CBaseEntity *pEntity)
{

	ServerClass *pServerClass = gamehelpers->FindEntityServerClass(pEntity);
	if (pServerClass == nullptr)
	{
		return;
	}
	if (!UTIL_ContainsDataTable(pServerClass->m_pTable, TF_WEAPON_DATATABLE))
	{
		return;
	}
	void **vtable = *reinterpret_cast<void ***>(pEntity);
	for (const SharedHooks &hooks : m_sharedHooks)
	{
		if (hooks.vtable == vtable)
			return;
	}
	if (gamedll != nullptr
		&& IsServerImageVtable(vtable, *reinterpret_cast<void ***>(gamedll)))
	{
		int critical = SH_ADD_MANUALVPHOOK(CalcIsAttackCriticalHelper, pEntity,
			SH_MEMBER(&g_CritManager, &CritManager::Hook_CalcIsAttackCriticalHelper), false);
		int noCrits = SH_ADD_MANUALVPHOOK(CalcIsAttackCriticalHelperNoCrits, pEntity,
			SH_MEMBER(&g_CritManager, &CritManager::Hook_CalcIsAttackCriticalHelperNoCrits), false);
		if (critical && noCrits)
		{
			m_sharedHooks.push_back({vtable, critical, noCrits});
			return;
		}
		if (critical) SH_REMOVE_HOOK_ID(critical);
		if (noCrits) SH_REMOVE_HOOK_ID(noCrits);
		g_pSM->LogError(myself, "Shared critical hook installation failed; using entity hooks");
	}

	SH_ADD_MANUALHOOK(CalcIsAttackCriticalHelper, pEntity, SH_MEMBER(&g_CritManager, &CritManager::Hook_CalcIsAttackCriticalHelper), false);
	SH_ADD_MANUALHOOK(CalcIsAttackCriticalHelperNoCrits, pEntity, SH_MEMBER(&g_CritManager, &CritManager::Hook_CalcIsAttackCriticalHelperNoCrits), false);

	m_entsHooked.Set(gamehelpers->EntityToBCompatRef(pEntity));
}

void CritManager::OnEntityDestroyed(CBaseEntity *pEntity)
{
	if (!m_enabled)
		return;

	int index = gamehelpers->EntityToBCompatRef(pEntity);
	if (index < 0 || index >= MAX_EDICTS)
		return;

	if (!m_entsHooked.IsBitSet(index))
		return;

	SH_REMOVE_MANUALHOOK(CalcIsAttackCriticalHelper, pEntity, SH_MEMBER(&g_CritManager, &CritManager::Hook_CalcIsAttackCriticalHelper), false);
	SH_REMOVE_MANUALHOOK(CalcIsAttackCriticalHelperNoCrits, pEntity, SH_MEMBER(&g_CritManager, &CritManager::Hook_CalcIsAttackCriticalHelperNoCrits), false);

	m_entsHooked.Set(index, false);
}

bool CritManager::Hook_CalcIsAttackCriticalHelper()
{
	return Hook_CalcIsAttackCriticalHelpers(false);
}

bool CritManager::Hook_CalcIsAttackCriticalHelperNoCrits()
{
	return Hook_CalcIsAttackCriticalHelpers(true);
}

bool CritManager::Hook_CalcIsAttackCriticalHelpers(bool noCrits)
{
	if (!m_enabled)
		RETURN_META_VALUE(MRES_IGNORED, false);
	CBaseEntity *pWeapon = META_IFACEPTR(CBaseEntity);

	// If there's an invalid ent or invalid server class here, we've got issues elsewhere.
	ServerClass *pServerClass = gamehelpers->FindEntityServerClass(pWeapon);
	if (pServerClass == nullptr)
	{
		g_pSM->LogError(myself, "Invalid server class on weapon.");
		RETURN_META_VALUE(MRES_IGNORED, false);
	}

	sm_sendprop_info_t info;
	if (!gamehelpers->FindSendPropInfo(pServerClass->GetName(), "m_hOwnerEntity", &info))
	{
		g_pSM->LogError(myself, "Could not find m_hOwnerEntity on %s", pServerClass->GetName());
		RETURN_META_VALUE(MRES_IGNORED, false);
	}

	int returnValue;
	if (noCrits)
	{
		returnValue = SH_MCALL(pWeapon, CalcIsAttackCriticalHelperNoCrits)() ? 1 : 0;
	}
	else
	{
		returnValue = SH_MCALL(pWeapon, CalcIsAttackCriticalHelper)() ? 1 : 0;
	}

	int origReturnValue = returnValue;
	int ownerIndex = -1;
	CBaseHandle &hndl = *(CBaseHandle *) ((intptr_t)pWeapon + info.actual_offset);
	CBaseEntity *pHandleEntity = gamehelpers->ReferenceToEntity(hndl.GetEntryIndex());

	if (pHandleEntity != NULL && hndl == reinterpret_cast<IHandleEntity *>(pHandleEntity)->GetRefEHandle())
	{
		ownerIndex = hndl.GetEntryIndex();
	}

	g_critForward->PushCell(ownerIndex); //Client index
	g_critForward->PushCell(gamehelpers->EntityToBCompatRef(pWeapon)); // Weapon index
	g_critForward->PushString(gamehelpers->GetEntityClassname(pWeapon)); //Weapon classname
	g_critForward->PushCellByRef(&returnValue); //return value

	cell_t result = 0;

	g_critForward->Execute(&result);

	if (result > Pl_Continue)
	{
		RETURN_META_VALUE(MRES_SUPERCEDE, returnValue);
	}

	RETURN_META_VALUE(MRES_SUPERCEDE, origReturnValue);
}
