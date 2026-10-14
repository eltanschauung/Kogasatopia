#include <weapons_ext_dependency>
#if defined _weapons_attributes_included
  #endinput
#endif
#define _weapons_attributes_included

/**
 * Sets an attribute's value on an entity, adding it if it isn't on the entity.
 *
 * @param iEntity		Entity index to set the attribute on. Must have m_AttributeList.
 * @param strAttrib		Name of the attribute, as from the "name" key in items_game.
 * @param flValue		Value to set the attribute to
 *
 * @return				True if the attribute was added successfully, false if entity does not have m_AttributeList.
 * @error				Invalid entity index or attribute name passed.
 */
native bool WeaponsAttrib_SetByName(int iEntity, const char[] strAttrib, float flValue);

/**
 * Sets an attribute's value on an entity, adding it if it isn't on the entity.
 *
 * @param iEntity		Entity index to set the attribute on. Must have m_AttributeList.
 * @param iDefIndex		Definition index of the attribute, as from the number on the attribute entry in items_game.
 * @param flValue		Value to set the attribute to
 *
 * @return				True if the attribute was added successfully, false if entity does not have m_AttributeList.
 * @error				Invalid entity index or attribute name passed.
 */
native bool WeaponsAttrib_SetByDefIndex(int iEntity, int iDefIndex, float flValue);

/**
 * Parses the attribute name and value strings and applies it on the entity.  This parses
 * numeric and string attributes.
 *
 * If you use this on a non-numeric attribute, make sure that only the server reads off of that
 * attribute.  Non-primitive values aren't replicated correctly between the client and the
 * server; the client will read garbage and may crash!
 *
 * @param iEntity		Entity index to set the attribute on. Must have m_AttributeList.
 * @param strAttrib		Name of the attribute, as from the "name" key in items_game.
 * @param strValue		Value to set the attribute to.
 *
 * @return				True if the attribute was added successfully, false if the attribute name was invalid.
 * @error				Invalid entity index or entity does not have m_AttributeList.
 */
native bool WeaponsAttrib_SetFromStringValue(int iEntity, const char[] strAttrib, const char[] strValue);

/**
 * Returns the address of an attribute on an entity.
 *
 * @param iEntity		Entity index to get attribute from. Must have m_AttributeList.
 * @param strAttrib		Name of the attribute, as from the "name" key in items_game.
 *
 * @return				Address of the attribute on the entity, or Address_Null if the attribute does not exist on the entity.
 * @error				Invalid entity index or attribute name passed.
 */
native Address WeaponsAttrib_GetByName(int iEntity, const char[] strAttrib);

/**
 * Returns the address of an attribute (by attribute index) on an entity.
 *
 * @param iEntity		Entity index to get attribute from. Must have m_AttributeList.
 * @param iDefIndex		Definition index of the attribute, as from the number on the attribute entry in items_game.
 *
 * @return				Address of the attribute on the entity, or Address_Null if the attribute does not exist on the entity.
 * @error				Invalid entity index or attribute index passed.
 */
native Address WeaponsAttrib_GetByDefIndex(int iEntity, int iDefIndex);

/**
 * Removes an attribute from an entity.
 *
 * @param iEntity		Entity index to remove attribute from. Must have m_AttributeList.
 * @param strAttrib		Name of the attribute, as from the "name" key in items_game.
 *
 * @return				True if the SDKCall was made, false if entity had invalid address or m_AttributeList missing.
 * @error				Invalid entity index or attribute name passed.
 */
native bool WeaponsAttrib_RemoveByName(int iEntity, const char[] strAttrib);

/**
 * Removes an attribute from an entity.
 *
 * @param iEntity		Entity index to remove attribute from. Must have m_AttributeList.
 * @param iDefIndex		Definition index of the attribute, as from the number on the attribute entry in items_game.
 *
 * @return				True if the SDKCall was made, false if entity had invalid address or m_AttributeList missing.
 * @error				Invalid entity index or attribute index passed.
 */
native bool WeaponsAttrib_RemoveByDefIndex(int iEntity, int iDefIndex);

/**
 * Removes all attributes from an entity.
 *
 * @param iEntity		Entity index to remove attribute from. Must have m_AttributeList.
 *
 * @return				True if the SDKCall was made, false if entity had invalid address or m_AttributeList missing.
 * @error				Invalid entity index passed.
 */
native bool WeaponsAttrib_RemoveAll(int iEntity);

/**
 * Clears and presumably rebuilds the attribute cache for an entity, 'refreshing' attributes.
 * Call this after making changes to an attribute with any of the WeaponsAttrib_Set*(Address pAttrib, arg) natives below.
 * You may also need to call this on the entity's m_hOwnerEntity if it is a weapon or wearable.
 * You do NOT need to call this after calls to WeaponsAttrib_SetByName, WeaponsAttrib_Remove, and WeaponsAttrib_RemoveAll.
 *
 * @param iEntity		Entity index to remove attribute from. Must have m_AttributeList.
 *
 * @return				True if the SDKCall was made, false if entity had invalid address or m_AttributeList missing.
 * @error				Invalid entity index passed.
 */
native bool WeaponsAttrib_ClearCache(int iEntity);

/**
 * Sets the value of m_iAttributeDefinitionIndex (the attribute ID) on an attribute.
 * Warning, this changes what GetByName/ID and SetByName 'see' as the name of the attribute,
 * but will only change attribute's effects if WeaponsAttrib_ClearCache is called on the entity with the attribute after.
 *
 * @param pAttrib		Address of the attribute.
 * @param iDefIndex		Value to set m_iAttributeDefinitionIndex to.
 *
 * @noreturn
 */
native void WeaponsAttrib_SetDefIndex(Address pAttrib, int iDefIndex);

/**
 * Returns the value of m_iAttributeDefinitionIndex (the attribute ID) on an attribute.
 *
 * @param pAttrib		Address of the attribute.
 *
 * @return				The integer value of m_iAttributeDefinitionIndex on the attribute.
 */
native int WeaponsAttrib_GetDefIndex(Address pAttrib);

/**
 * Sets the value of m_flValue on an attribute.
 *
 * @param pAttrib		Address of the attribute.
 * @param flValue		Value to set m_flValue to.
 *
 * @noreturn
 */
native void WeaponsAttrib_SetValue(Address pAttrib, float flValue);

/**
 * Returns the value of m_flValue on an attribute.
 *
 * @param pAttrib		Address of the attribute.
 *
 * @return				The floating point value of m_flValue on the attribute.
 */
native float WeaponsAttrib_GetValue(Address pAttrib);

/**
 * Returns the string data from its raw value representation (a CAttribute_String instance).
 *
 * WARNING: This dereferences the input value!  Feeding it values that aren't CAttribute_String pointers will result in unexpected behavior, potentially crashing the server.
 * In the case where you only want the currently active value, use WeaponsAttrib_HookValueString instead.
 *
 * @param pRawValue		Raw attribute value.  You can get this value with either WeaponsAttrib_GetValue, WeaponsAttrib_GetSOCAttribs, or WeaponsAttrib_GetStaticAttribs.
 * @param buffer		Buffer to store the resulting string to.
 * @param maxlen		Maximum length of the buffer.
 *
 * @return Number of bytes written.
 */
native int WeaponsAttrib_UnsafeGetStringValue(any pRawValue, char[] buffer, int maxlen);

/**
 * Sets the value of m_nRefundableCurrency on an attribute.
 *
 * @param pAttrib		Address of the attribute.
 * @param nCurrency		Value to set m_nRefundableCurrency to.
 *
 * @noreturn
 */
native void WeaponsAttrib_SetRefundableCurrency(Address pAttrib, int nCurrency);

/**
 * Returns the value of m_nRefundableCurrency on an attribute.
 *
 * @param pAttrib		Address of the attribute.
 *
 * @return				The (unsigned) integer value of m_nRefundableCurrency on the attribute.
 */
native int WeaponsAttrib_GetRefundableCurrency(Address pAttrib);

/**
 * Returns an array containing the attributes (as indices) present on an entity.
 *
 * @param iEntity		Entity index to get attribute list from. Must have m_AttributeList.
 * @param iDefIndices	Array of attribute definition indices found on the entity.
 * @param iMaxLen		Max length of the iDefIndices array, default 20. Does not affect the return value.
 *
 * @return				The number of attributes found on the entity's attribute list (max 20 as of Oct 2017), or -1 if some error happened.
 * @error				Invalid iEntity or iMaxLen.
 */
native int WeaponsAttrib_ListDefIndices(int iEntity, int[] iDefIndices, int iMaxLen=20);

/**
 * Returns arrays containing the static attributes and their values present on an item definition.
 *
 * @param iItemDefIndex		Item definition index (e.g. 7 for Shovel) to get static attribute list from.
 * @param iAttribIndices	Array of attribute definition indices found on the item definition.
 * @param flAttribValues	Array of attribute values found on the item definition, corresponding to the indices.
 * @param iMaxLen			Max length of the two arrays passed in, default 16. Does not affect the return value.
 *
 * @return					The number of attributes found on the item definition's static attribute list (max 16 as of June 2017), or -1 if no schema or item definition found.
 * @error					Invalid iMaxLen, or gamedata for this function failed to load.
 */
native int WeaponsAttrib_GetStaticAttribs(int iItemDefIndex, int[] iAttribIndices, float[] flAttribValues, int iMaxLen=16);

/**
 * Returns arrays containing the item server (SOC) attributes and their values present on an item definition.
 *
 * @param iEntity			Entity index to get the item server attribute list from.
 * @param iAttribIndices	Array of attribute definition indices found.
 * @param flAttribValues	Array of attribute values found, corresponding to the indices.
 * @param iMaxLen			Max length of the two arrays passed in, default 16. Does not affect the return value.
 *
 * @return					The number of attributes found on the item's SOC attribute list (max 16 as of June 2017), or -1 if some error happened.
 * @error					Invalid iEntity or iMaxLen, or gamedata for this function failed to load.
 */
native int WeaponsAttrib_GetSOCAttribs(int iEntity, int[] iAttribIndices, float[] flAttribValues, int iMaxLen=16);

/**
 * Gets whether an attribute is stored as an integer or as a float.
 * Use WeaponsAttrib_SetValue(attribute, view_as<float>(intValue)) on attributes that store values as ints
 *   to avoid compiler tag mismatch warnings.
 *
 * @param iDefIndex		Index of the attribute (as returned by WeaponsAttrib_GetDefIndex()).
 *
 * @return				True if attribute value is supposed to be an int, false if float.
 */
native bool WeaponsAttrib_IsIntegerValue(int iDefIndex);

/**
 * Returns true if an attribute with the specified name exists.
 *
 * @param strAttrib			Name of the attribute, as from the "name" key in items_game.
 *
 * @return					True if the attribute exists, false otherwise.
 */
native bool WeaponsAttrib_IsValidAttributeName(const char[] strAttrib);

/**
 * Adds a custom, potentially temporary attribute to a player.
 *
 * @param client			Client index to set the attribute on.
 * @param strAttrib			Name of the attribute, as from the "name" key in items_game.
 * @param flValue			Value to set m_flValue to.
 * @param flDuration		Duration of the attribute.  If less than 0, the attribute will not be automatically removed.
 *
 * @noreturn
 */
native void WeaponsAttrib_AddCustomPlayerAttribute(int client, const char[] strAttrib, float flValue, float flDuration = -1.0);

/**
 * Removes a previously applied custom attribute on a player.
 *
 * @param client			Client index to remove the attribute from.
 * @param strAttrib			Name of the attribute, as from the "name" key in items_game.
 *
 * @noreturn
 */
native void WeaponsAttrib_RemoveCustomPlayerAttribute(int client, const char[] strAttrib);

/**
 * Applies a transformation to the given initial value, following the rules according to the given attribute class.
 *
 * @param flInitial			Initial float value.
 * @param attrClass			The attribute class, as from the "attribute_class" key in items_game.
 * @param iEntity			The entity that should be checked.  Checking players also checks their equipped items.
 *
 * @return					Transformed initial value.
 */
native float WeaponsAttrib_HookValueFloat(float flInitial, const char[] attrClass, int iEntity);

/**
 * Applies a transformation to the given initial value, following the rules according to the given attribute class.
 *
 * @param nInitial			Initial integer value.
 * @param attrClass			The attribute class, as from the "attribute_class" key in items_game.
 * @param iEntity			The entity that should be checked.  Checking players also checks their equipped items.
 *
 * @return					Transformed initial value.
 */
native int WeaponsAttrib_HookValueInt(int nInitial, const char[] attrClass, int iEntity);

/**
 * Applies a transformation to the given initial value, following the rules according to the given attribute class.
 *
 * @param initial			Initial string value.  (This appears to only be returned if the entity doesn't have the attribute.)
 * @param attrClass			The attribute class, as from the "attribute_class" key in items_game.
 * @param iEntity			The entity that should be checked.  Checking players also checks their equipped items.
 * @param buffer			Transformed initial value.
 * @param maxlen			Buffer size.
 *
 * @return					Number of bytes written.
 */
native int WeaponsAttrib_HookValueString(const char[] initial, const char[] attrClass, int iEntity, char[] buffer, int maxlen);

/**
 * Gets whether the plugin loaded without ANY errors.
 * For the purpose of allowing dependencies to ignore the plugin if this returns false.
 * Check in OnAllPluginsLoaded() or something. I dunno.
 *
 * @return				True if no errors while loading, false otherwise.
 */
stock bool WeaponsAttrib_IsReady()
{
    return GetFeatureStatus(FeatureType_Native, "WeaponsAttrib_SetByName") == FeatureStatus_Available;
}
native void WeaponsAttrib_InvalidateDefinitions();
