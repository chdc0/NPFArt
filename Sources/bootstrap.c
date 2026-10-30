#include <dispatch/dispatch.h>

// Implemented in Swift (@_cdecl in NowPlayingFullArt.swift).
extern void npa_bootstrap(void);

// Constructor runs when dyld loads the dylib. The hook itself is installed on
// the main queue so the Swift runtime and UIKit are fully up by then, and so
// the swizzle is in place before the first now-playing update.
static void npa_deferred(void *context) {
    (void)context;
    npa_bootstrap();
}

__attribute__((constructor))
static void npa_constructor(void) {
    dispatch_async_f(dispatch_get_main_queue(), NULL, npa_deferred);
}
