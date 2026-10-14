// Weapons-owned control plane; the native Sentry module owns its engine hook.
ConVar g_WeaponsSentryRangeEnabled, g_WeaponsSentryRange;
void WeaponsSentry_OnPluginStart()
{
    g_WeaponsSentryRangeEnabled = CreateConVar("sm_tf2_sentry_newtarget_enable", "0", "Enable sentry NewTarget distance override", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_WeaponsSentryRange = CreateConVar("sm_tf2_sentry_newtarget_dist", "200.0", "Sentry NewTarget distance", FCVAR_NOTIFY, true, 0.0);
    g_WeaponsSentryRangeEnabled.AddChangeHook(WeaponsSentry_OnChanged);
    g_WeaponsSentryRange.AddChangeHook(WeaponsSentry_OnChanged);
    AutoExecConfig(true, "tf2_sentry_newtarget_dist");
    WeaponsSentry_Apply();
}
public void WeaponsSentry_OnChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    WeaponsSentry_Apply();
}
void WeaponsSentry_Apply()
{
    TF2SentryNewTarget_SetDistance(g_WeaponsSentryRange.FloatValue);
    TF2SentryNewTarget_SetEnabled(g_WeaponsSentryRangeEnabled.BoolValue);
}
