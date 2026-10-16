/** Building-only crit policy; the native service never sends players here. */
public Action Weapons_OnBuildingTakeDamage(int building, int attacker, int inflictor,
    float &damage, int damageType, int weapon, int damageCustom, CritType critType)
{
    if (damage <= 0.0)
        return Plugin_Continue;

    // The native hook passes a target-local copy before CBaseObject's normal
    // attributes, resistances, sapper handling and destruction/event pipeline.
    // Do not rewrite critType or DMG_CRIT: they are read-only metadata here.
    switch (critType)
    {
        case CritType_MiniCrit:
        {
            damage *= 1.35;
            return Plugin_Changed;
        }
        case CritType_Crit:
        {
            damage *= 3.0;
            return Plugin_Changed;
        }
    }
    return Plugin_Continue;
}
