// Dynamic schema API, based on nosoop's SMExt-TFEconDynamic.
#if defined _weapons_schema_included
    #endinput
#endif
#define _weapons_schema_included
#include <weapons_ext_dependency>

/** Cold-path builder for engine attribute definitions. Delete handles when done.
 * Register clones the definition, installs it and invalidates Weapons' caches.
 * Engine definitions are reinstalled before plugin OnMapStart on later maps.
 */
methodmap WeaponsSchemaAttribute < Handle {
    public native WeaponsSchemaAttribute();
    public native void SetClass(const char[] attributeClass);
    public native void SetName(const char[] name);
    public native void SetDescriptionFormat(const char[] format);
    public native void SetCustom(const char[] key, const char[] value);
    /** Explicit indices are 1..65535. Valve definitions cannot be replaced. */
    public native void SetDefIndex(int index);
    public native void ClearDefIndex();
    /** Uses attribute_class as the name if none was set. Auto IDs start at 4000.
     * Returns false for invalid/colliding definitions without registering them.
     */
    public native bool Register();
    /** Imports a clone. Use ClearDefIndex before registering a Valve-derived copy. */
    public native bool Import(const char[] name);
    public native void Clear();
}
