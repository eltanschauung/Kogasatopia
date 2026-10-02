

#include "extension.h"

#include "sourcehook.h"
#include "detours.h"

#include "vphysics_interface.h"
#include "ihandleentity.h"
#include "engine/IStaticPropMgr.h"

#include "tier1/strtools.h"


// memdbgon must be the last include file in a .cpp file!!!
#include "tier0/memdbgon.h"



CollisionHook g_CollisionHook;
SMEXT_LINK( &g_CollisionHook );


SH_DECL_HOOK0( IPhysics, CreateEnvironment, SH_NOATTRIB, 0 , IPhysicsEnvironment * );
SH_DECL_HOOK1_void( IPhysicsEnvironment, SetCollisionSolver, SH_NOATTRIB, 0, IPhysicsCollisionSolver * );

#if (SOURCE_ENGINE == SE_LEFT4DEAD2)
SH_DECL_HOOK6( IPhysicsCollisionSolver, ShouldCollide, SH_NOATTRIB, 0, int, IPhysicsObject *,
	IPhysicsObject *, void *, void *, const PhysicsCollisionRulesCache_t&, const PhysicsCollisionRulesCache_t& );
#else
SH_DECL_HOOK4( IPhysicsCollisionSolver, ShouldCollide, SH_NOATTRIB, 0, int, IPhysicsObject *, IPhysicsObject *, void *, void * );
#endif


IGameConfig *g_pGameConf = NULL;
CDetour *g_pFilterDetour = NULL;
CDetour *g_pOptimizedFilterDetour = NULL;
IStaticPropMgrServer *g_pStaticProps = NULL;
static thread_local unsigned int g_InsideOriginalFilter;
struct OriginalFilterScope
{
    OriginalFilterScope() { ++g_InsideOriginalFilter; }
    ~OriginalFilterScope() { --g_InsideOriginalFilter; }
};

IPhysics *g_pPhysics = NULL;

IForward *g_pCollisionFwd = NULL;
IForward *g_pPassFwd = NULL;

int gSetCollisionSolverHookId, gShouldCollideHookId;


// Apply the same public forward to the exported wrapper and the optimizer's
// private entry. Source's own wrapper can tail-call that private entry, so only
// suppress a duplicate while executing the original implementation.
static bool OverridePassFilter(const IHandleEntity *touch, const IHandleEntity *pass, bool &allow)
{
    if (g_InsideOriginalFilter || !g_pPassFwd || !g_pPassFwd->GetFunctionCount()
        || !touch || !pass || touch == pass)
        return false;
    // A static prop is an IHandleEntity but is not an IServerUnknown.
    if (g_pStaticProps->IsStaticProp(const_cast<IHandleEntity *>(touch))
        || g_pStaticProps->IsStaticProp(const_cast<IHandleEntity *>(pass)))
        return false;
    CBaseEntity *first = const_cast<CBaseEntity *>(UTIL_EntityFromEntityHandle(touch));
    CBaseEntity *second = const_cast<CBaseEntity *>(UTIL_EntityFromEntityHandle(pass));
    if (!first || !second) return false;
    cell_t result = 0, action = 0;
    g_pPassFwd->PushCell(gamehelpers->EntityToBCompatRef(first));
    g_pPassFwd->PushCell(gamehelpers->EntityToBCompatRef(second));
    g_pPassFwd->PushCellByRef(&result);
    g_pPassFwd->Execute(&action);
    if (action <= Pl_Continue) return false;
    allow = result == 1;
    return true;
}

DETOUR_DECL_STATIC2(PassServerEntityFilterFunc, bool, const IHandleEntity *, touch, const IHandleEntity *, pass)
{
    bool allow;
    if (OverridePassFilter(touch, pass, allow)) return allow;
    OriginalFilterScope scope;
    return DETOUR_STATIC_CALL(PassServerEntityFilterFunc)(touch, pass);
}

// GCC's internal TF2 i386 .part.0 helper uses EAX/EDX rather than the public
// wrapper's stack ABI. This was checked in both the wrapper and real movement
// caller of build 11068238. x86-64 uses its ordinary SysV register ABI.
#if defined(__linux__) && defined(__i386__)
#define OPTIMIZED_FILTER_ABI __attribute__((regparm(2)))
#else
#define OPTIMIZED_FILTER_ABI
#endif
static bool (OPTIMIZED_FILTER_ABI *OptimizedFilterActual)(const IHandleEntity *, const IHandleEntity *);
static bool OPTIMIZED_FILTER_ABI OptimizedFilter(const IHandleEntity *touch, const IHandleEntity *pass)
{
    bool allow;
    if (OverridePassFilter(touch, pass, allow)) return allow;
    OriginalFilterScope scope;
    return OptimizedFilterActual(touch, pass);
}


bool CollisionHook::SDK_OnLoad( char *error, size_t maxlength, bool late )
{
	char szConfError[ 256 ] = "";
	if ( !gameconfs->LoadGameConfigFile( "collisionhook", &g_pGameConf, szConfError, sizeof( szConfError ) ) )
	{
		snprintf( error, maxlength,  "Could not read collisionhook gamedata: %s", szConfError );
		return false;
	}

	CDetourManager::Init( g_pSM->GetScriptingEngine(), g_pGameConf );

	g_pFilterDetour = DETOUR_CREATE_STATIC( PassServerEntityFilterFunc, "PassServerEntityFilter" );
	if ( !g_pFilterDetour )
	{
		snprintf( error, maxlength,  "Unable to hook PassServerEntityFilter!" );
		return false;
	}



	g_pCollisionFwd = forwards->CreateForward( "CH_ShouldCollide", ET_Hook, 3, NULL, Param_Cell, Param_Cell, Param_CellByRef );
	g_pPassFwd = forwards->CreateForward( "CH_PassFilter", ET_Hook, 3, NULL, Param_Cell, Param_Cell, Param_CellByRef );

#if defined(__linux__) && SOURCE_ENGINE == SE_TF2
    void *optimized = NULL;
    if (g_pGameConf->GetMemSig("PassServerEntityFilter_Optimized", &optimized) && optimized)
    {
        g_pOptimizedFilterDetour = CDetourManager::CreateDetour(
            reinterpret_cast<void *>(&OptimizedFilter),
            reinterpret_cast<void **>(&OptimizedFilterActual), optimized);
        if (!g_pOptimizedFilterDetour)
        {
            forwards->ReleaseForward(g_pCollisionFwd);
            forwards->ReleaseForward(g_pPassFwd);
            g_pCollisionFwd = g_pPassFwd = NULL;
            g_pFilterDetour->Destroy(); g_pFilterDetour = NULL;
            gameconfs->CloseGameConfigFile(g_pGameConf); g_pGameConf = NULL;
            snprintf(error, maxlength, "Cannot hook TF2's optimized trace filter");
            return false;
        }
        g_pOptimizedFilterDetour->EnableDetour();
    }
#endif
    g_pFilterDetour->EnableDetour();
    smutils->LogMessage(myself, "Optimized TF2 trace filter: %s", g_pOptimizedFilterDetour ? "active" : "not present");
	sharesys->RegisterLibrary( myself, "collisionhook" );

	return true;
}

void CollisionHook::SDK_OnUnload()
{
    if (g_pOptimizedFilterDetour)
    {
        g_pOptimizedFilterDetour->Destroy(); g_pOptimizedFilterDetour = NULL;
    }
	forwards->ReleaseForward( g_pCollisionFwd );
	forwards->ReleaseForward( g_pPassFwd );

	gameconfs->CloseGameConfigFile( g_pGameConf );

	if ( g_pFilterDetour )
	{
		g_pFilterDetour->Destroy();
		g_pFilterDetour = NULL;
	}
}

bool CollisionHook::SDK_OnMetamodLoad( ISmmAPI *ismm, char *error, size_t maxlen, bool late )
{
	GET_V_IFACE_CURRENT( GetPhysicsFactory, g_pPhysics, IPhysics, VPHYSICS_INTERFACE_VERSION );
    GET_V_IFACE_CURRENT(GetEngineFactory, g_pStaticProps, IStaticPropMgrServer, INTERFACEVERSION_STATICPROPMGR_SERVER);

	SH_ADD_HOOK( IPhysics, CreateEnvironment, g_pPhysics, SH_MEMBER( this, &CollisionHook::CreateEnvironment ), true );

	return true;
}

bool CollisionHook::SDK_OnMetamodUnload(char *error, size_t maxlength)
{
	SH_REMOVE_HOOK( IPhysics, CreateEnvironment, g_pPhysics, SH_MEMBER( this, &CollisionHook::CreateEnvironment ), true );
	SH_REMOVE_HOOK_ID( gSetCollisionSolverHookId );
	SH_REMOVE_HOOK_ID( gShouldCollideHookId );

	g_pPhysics = NULL;
	gSetCollisionSolverHookId = gShouldCollideHookId = 0;

	return true;
}


IPhysicsEnvironment *CollisionHook::CreateEnvironment()
{
	// in order to hook IPhysicsCollisionSolver::ShouldCollide, we need to know when a solver is installed
	// in order to hook any installed solvers, we need to hook any created physics environments

	IPhysicsEnvironment *pEnvironment = META_RESULT_ORIG_RET( IPhysicsEnvironment * );

	if ( !pEnvironment )
		RETURN_META_VALUE( MRES_SUPERCEDE, pEnvironment ); // just in case

	// Hook globally so we know when any solver is installed
	gSetCollisionSolverHookId = SH_ADD_VPHOOK( IPhysicsEnvironment, SetCollisionSolver, pEnvironment,
		SH_MEMBER( this, &CollisionHook::SetCollisionSolver ), true );

	SH_REMOVE_HOOK( IPhysics, CreateEnvironment, g_pPhysics,
		SH_MEMBER( this, &CollisionHook::CreateEnvironment ), true ); // No longer needed

	RETURN_META_VALUE( MRES_SUPERCEDE, pEnvironment );
}

void CollisionHook::SetCollisionSolver( IPhysicsCollisionSolver *pSolver )
{
	if ( !pSolver )
		RETURN_META( MRES_IGNORED ); // this shouldn't happen, but knowing valve...

	// The game installed a solver, globally hook ShouldCollide
	gShouldCollideHookId = SH_ADD_VPHOOK( IPhysicsCollisionSolver, ShouldCollide, pSolver,
		SH_MEMBER( this, &CollisionHook::VPhysics_ShouldCollide ), false );

	SH_REMOVE_HOOK_ID( gSetCollisionSolverHookId ); // No longer needed
	gSetCollisionSolverHookId = 0;

	RETURN_META( MRES_IGNORED );
}

int CollisionHook::VPhysics_ShouldCollide(IPhysicsObject *pObj1, IPhysicsObject *pObj2, void *pGameData1, void *pGameData2
#if (SOURCE_ENGINE == SE_LEFT4DEAD2)
	, const PhysicsCollisionRulesCache_t&, const PhysicsCollisionRulesCache_t&
#endif
)
{
	if ( g_pCollisionFwd->GetFunctionCount() == 0 )
		RETURN_META_VALUE( MRES_IGNORED, 1 ); // no plugins are interested, let the game decide

	if ( pObj1 == pObj2 )
		RETURN_META_VALUE( MRES_IGNORED, 1 ); // self collisions aren't interesting

	CBaseEntity *pEnt1 = reinterpret_cast<CBaseEntity *>( pGameData1 );
	CBaseEntity *pEnt2 = reinterpret_cast<CBaseEntity *>( pGameData2 );

	if ( !pEnt1 || !pEnt2 )
		RETURN_META_VALUE( MRES_IGNORED, 1 ); // we need two entities

	cell_t ent1 = gamehelpers->EntityToBCompatRef( pEnt1 );
	cell_t ent2 = gamehelpers->EntityToBCompatRef( pEnt2 );

	// todo: do we want to fill result with with the game's result? perhaps the forward path is more performant...
	cell_t result = 0;
	g_pCollisionFwd->PushCell( ent1 );
	g_pCollisionFwd->PushCell( ent2 );
	g_pCollisionFwd->PushCellByRef( &result );

	cell_t retValue = 0;
	g_pCollisionFwd->Execute( &retValue );

	if ( retValue > Pl_Continue )
	{
		// plugin wants to change the result
		RETURN_META_VALUE( MRES_SUPERCEDE, result == 1 );
	}

	// otherwise, game decides
	RETURN_META_VALUE( MRES_IGNORED, 0 );
}
