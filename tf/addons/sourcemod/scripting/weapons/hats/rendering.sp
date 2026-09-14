void ApplyCustomModel(int entity, const char[] modelPath)
{
	if (!modelPath[0])
	{
		return;
	}

	int modelIndex = PrecacheModel(modelPath, true);
	SetEntityModel(entity, modelPath);
	SetEntProp(entity, Prop_Send, "m_nModelIndex", modelIndex);
	if (HasEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity"))
	{
		SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
	}

	if (HasEntProp(entity, Prop_Send, "m_nModelIndexOverrides"))
	{
		int count = GetEntPropArraySize(entity, Prop_Send, "m_nModelIndexOverrides");
		for (int i = 0; i < count; i++)
		{
			SetEntProp(entity, Prop_Send, "m_nModelIndexOverrides", modelIndex, .element = i);
		}
	}
}

void ApplyModelScale(int entity, bool hasModelScale, float modelScale)
{
	if (!hasModelScale || !IsValidEntity(entity) || !HasEntProp(entity, Prop_Send, "m_flModelScale"))
	{
		return;
	}

	SetEntPropFloat(entity, Prop_Send, "m_flModelScale", modelScale);
}

void ApplyStyle(int entity, int style)
{
	if (style < 0)
	{
		return;
	}

	TF2Attrib_SetByDefIndex(entity, 834, float(style));
	if (HasEntProp(entity, Prop_Send, "m_nStyle"))
	{
		SetEntProp(entity, Prop_Send, "m_nStyle", style);
	}
}

void ApplyPaint(int hat, int paint)
{
	switch (paint)
	{
		case 1:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 3100495.0);
			TF2Attrib_SetByDefIndex(hat, 261, 3100495.0);
		}
		case 2:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 8208497.0);
			TF2Attrib_SetByDefIndex(hat, 261, 8208497.0);
		}
		case 3:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 1315860.0);
			TF2Attrib_SetByDefIndex(hat, 261, 1315860.0);
		}
		case 4:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 12377523.0);
			TF2Attrib_SetByDefIndex(hat, 261, 12377523.0);
		}
		case 5:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 2960676.0);
			TF2Attrib_SetByDefIndex(hat, 261, 2960676.0);
		}
		case 6:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 8289918.0);
			TF2Attrib_SetByDefIndex(hat, 261, 8289918.0);
		}
		case 7:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 15132390.0);
			TF2Attrib_SetByDefIndex(hat, 261, 15132390.0);
		}
		case 8:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 15185211.0);
			TF2Attrib_SetByDefIndex(hat, 261, 15185211.0);
		}
		case 9:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 14204632.0);
			TF2Attrib_SetByDefIndex(hat, 261, 14204632.0);
		}
		case 10:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 15308410.0);
			TF2Attrib_SetByDefIndex(hat, 261, 15308410.0);
		}
		case 11:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 8421376.0);
			TF2Attrib_SetByDefIndex(hat, 261, 8421376.0);
		}
		case 12:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 7511618.0);
			TF2Attrib_SetByDefIndex(hat, 261, 7511618.0);
		}
		case 13:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 13595446.0);
			TF2Attrib_SetByDefIndex(hat, 261, 13595446.0);
		}
		case 14:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 10843461.0);
			TF2Attrib_SetByDefIndex(hat, 261, 10843461.0);
		}
		case 15:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 5322826.0);
			TF2Attrib_SetByDefIndex(hat, 261, 5322826.0);
		}
		case 16:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 12955537.0);
			TF2Attrib_SetByDefIndex(hat, 261, 12955537.0);
		}
		case 17:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 16738740.0);
			TF2Attrib_SetByDefIndex(hat, 261, 16738740.0);
		}
		case 18:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 6901050.0);
			TF2Attrib_SetByDefIndex(hat, 261, 6901050.0);
		}
		case 19:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 3329330.0);
			TF2Attrib_SetByDefIndex(hat, 261, 3329330.0);
		}
		case 20:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 15787660.0);
			TF2Attrib_SetByDefIndex(hat, 261, 15787660.0);
		}
		case 21:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 8154199.0);
			TF2Attrib_SetByDefIndex(hat, 261, 8154199.0);
		}
		case 22:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 4345659.0);
			TF2Attrib_SetByDefIndex(hat, 261, 4345659.0);
		}
		case 23:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 6637376.0);
			TF2Attrib_SetByDefIndex(hat, 261, 2636109.0);
		}
		case 24:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 3874595.0);
			TF2Attrib_SetByDefIndex(hat, 261, 1581885.0);
		}
		case 25:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 12807213.0);
			TF2Attrib_SetByDefIndex(hat, 261, 12091445.0);
		}
		case 26:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 4732984.0);
			TF2Attrib_SetByDefIndex(hat, 261, 3686984.0);
		}
		case 27:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 12073019.0);
			TF2Attrib_SetByDefIndex(hat, 261, 5801378.0);
		}
		case 28:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 8400928.0);
			TF2Attrib_SetByDefIndex(hat, 261, 2452877.0);
		}
		case 29:
		{
			TF2Attrib_SetByDefIndex(hat, 142, 11049612.0);
			TF2Attrib_SetByDefIndex(hat, 261, 8626083.0);
		}
	}
}
