// battery: print the IORegistry properties of the iPhone's power source(s) (iPhone OS 3).
// The iOS SDK ships IOKit without headers, so the few calls used are declared here.
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <stdio.h>

typedef mach_port_t io_object_t, io_iterator_t, io_registry_entry_t;
extern const mach_port_t kIOMasterPortDefault;
extern CFMutableDictionaryRef IOServiceMatching(const char *name);
extern kern_return_t IOServiceGetMatchingServices(mach_port_t, CFDictionaryRef, io_iterator_t *);
extern io_object_t IOIteratorNext(io_iterator_t);
extern kern_return_t IORegistryEntryCreateCFProperties(io_registry_entry_t, CFMutableDictionaryRef *, CFAllocatorRef, uint32_t);
extern kern_return_t IORegistryEntryGetName(io_registry_entry_t, char name[128]);
extern kern_return_t IOObjectRelease(io_object_t);

static void dump(const char *cls) {
    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(cls), &it)) return;
    io_object_t o;
    while ((o = IOIteratorNext(it))) {
        char name[128] = "";
        IORegistryEntryGetName(o, name);
        CFMutableDictionaryRef props = NULL;
        IORegistryEntryCreateCFProperties(o, &props, NULL, 0);
        printf("== %s (%s)\n", cls, name);
        if (props) {
            CFStringRef d = CFCopyDescription(props);
            char buf[16384];
            CFStringGetCString(d, buf, sizeof buf, kCFStringEncodingUTF8);
            printf("%s\n", buf);
            CFRelease(d); CFRelease(props);
        }
        IOObjectRelease(o);
    }
    IOObjectRelease(it);
}

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) dump(argv[i]);
    if (argc < 2) { dump("IOPMPowerSource"); dump("AppleARMPMUCharger"); dump("AppleARMPMUPowerSource"); }
    return 0;
}
