/* screentime window scanner (macOS).
 *
 * Prints every visible window as "<screen><TAB><title>". The screen number is
 * 1-based in the order of CGGetActiveDisplayList and is resolved from the
 * window's centre point against CGDisplayBounds; 0 means the centre sits on no
 * active display.
 *
 * Why native: asking System Events for all windows took 13 to 25 seconds per
 * run and failed in two of three runs with "-1719 invalid index".
 * CGWindowListCopyWindowInfo needs 0.03 s.
 *
 * No app bundle and no signature of its own: this runs as a child of
 * Screentime.app and inherits its screen-recording grant. A second bundle
 * would be a second entry in System Settings, and re-signing would invalidate
 * the existing TCC grants.
 *
 * Build: cc -o mac/windowscan mac/windowscan.c -framework ApplicationServices
 */
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>

#define MAXD 16

int main(void) {
    CGDirectDisplayID ids[MAXD];
    uint32_t nd = 0;
    if (CGGetActiveDisplayList(MAXD, ids, &nd) != kCGErrorSuccess || nd == 0)
        return 1;

    CFArrayRef wl = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (!wl) return 1;

    int seen[MAXD] = {0};
    CFIndex n = CFArrayGetCount(wl);
    for (CFIndex i = 0; i < n; i++) {
        CFDictionaryRef w = CFArrayGetValueAtIndex(wl, i);
        CFStringRef name = CFDictionaryGetValue(w, kCGWindowName);
        CFDictionaryRef bounds = CFDictionaryGetValue(w, kCGWindowBounds);
        char nb[512] = {0};
        CGRect r;
        if (!name || !bounds) continue;
        if (!CFStringGetCString(name, nb, sizeof nb, kCFStringEncodingUTF8)) continue;
        if (!nb[0]) continue;
        if (!CGRectMakeWithDictionaryRepresentation(bounds, &r)) continue;

        /* A newline inside a title would produce a second line without a
         * screen number; the block check could then not tell which screen was
         * meant and would let the frame through. */
        for (char *p = nb; *p; p++)
            if (*p == '\n' || *p == '\r') *p = ' ';

        CGPoint c = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
        int screen = 0;
        for (uint32_t d = 0; d < nd; d++) {
            if (CGRectContainsPoint(CGDisplayBounds(ids[d]), c)) {
                screen = (int)d + 1;
                seen[d] = 1;
                break;
            }
        }
        printf("%d\t%s\n", screen, nb);
    }
    CFRelease(wl);

    /* A screen with no titled window still gets a line, with an empty title.
     * Otherwise the caller could not count the screens from this output, and
     * its fail-closed comparison against the number of frames would block
     * every tick as soon as one screen showed nothing but the desktop. */
    for (uint32_t d = 0; d < nd; d++)
        if (!seen[d]) printf("%u\t\n", d + 1);
    return 0;
}
