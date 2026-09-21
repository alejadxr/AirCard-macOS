#ifndef AIRLIFT_TARGET_H
#define AIRLIFT_TARGET_H

#define AIRLIFT_TESTED_BUILDS(X) \
    X(@"27.0", @"24A435")       \
    X(@"27.0", @"24A437")       \
    X(@"27.0", @"24A5390f")

#define AIRLIFT_SOURCE_PREFIX @"airlift-src-"
#define AIRLIFT_LINK_PREFIX @"airlift-link-"
#define AIRLIFT_RECOVERED_PREFIX @"airlift-recovered-"
#define AIRLIFT_CANARY_PREFIX @"airlift-canary-"

#endif
