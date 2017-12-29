//
//  wrapper.hpp
//  screc
//
//  Created by Max Fomichev on 11/11/15.
//  Copyright © 2015 Pieci Kvadrati. All rights reserved.
//

#ifndef wrapper_hpp
#define wrapper_hpp

#ifdef __cplusplus
extern "C" {
#endif
    enum screenResolution_t {
        SR320x240,
        SR352x288,
        SR640x480,
        SR960x540,
        SR1280x720
    };
    
    void *start(unsigned char _display, enum screenResolution_t _screenResolution,
                unsigned char _frameRate, unsigned char _fontSize, const char *_fileName);
    void stop(void *_objectInstance);
#ifdef __cplusplus
}
#endif

#endif /* wrapper_hpp */
