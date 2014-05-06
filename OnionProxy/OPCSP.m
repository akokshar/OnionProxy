//
//  OPCSP.m
//  OnionProxy
//
//  Created by Koksharov Alexander on 04/04/14.
//
//

#import "OPCSP.h"

/*
 * Standard app-level memory functions required by CDSA.
 */
void * appMalloc (CSSM_SIZE size, void *allocRef) {
	return( malloc(size) );
}

void appFree (void *mem_ptr, void *allocRef) {
	free(mem_ptr);
 	return;
}

void * appRealloc (void *ptr, CSSM_SIZE size, void *allocRef) {
	return( realloc( ptr, size ) );
}

void * appCalloc (uint32 num, CSSM_SIZE size, void *allocRef) {
	return( calloc( num, size ) );
}

static CSSM_API_MEMORY_FUNCS memFuncs = {
	appMalloc,
	appFree,
	appRealloc,
 	appCalloc,
 	NULL
};

@implementation OPCSP

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@synthesize handle = _handle;

- (CSSM_CSP_HANDLE) getHandle {
    @synchronized(self) {
        if (_handle == 0) {
            CSSM_CSP_HANDLE cspHandle;
            CSSM_RETURN	crtn;
            CSSM_VERSION vers = {2, 0};
            
            /* Load the CSP bundle into this app's memory space */
            crtn = CSSM_ModuleLoad(&gGuidAppleCSP, CSSM_KEY_HIERARCHY_NONE, NULL, NULL);
            if(crtn != CSSM_OK) {
                return 0;
            }
            
            /* obtain a handle which will be used to refer to the CSP */
            crtn = CSSM_ModuleAttach (&gGuidAppleCSP, &vers, &memFuncs, 0, CSSM_SERVICE_CSP, 0, CSSM_KEY_HIERARCHY_NONE, NULL, 0, NULL, &cspHandle);
            if(crtn) {
                return 0;
            }
            _handle = cspHandle;
        }
        return _handle;
    }
}

#pragma clang diagnostic pop

- (id) init {
    self = [super init];
    if (self) {
        _handle = 0;
    }
    return self;
}

+ (OPCSP *) instance {
    static OPCSP *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OPCSP alloc] init];
    });
    return instance;
}

@end



