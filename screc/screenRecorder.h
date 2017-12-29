//
//  screenRecorder.h
//  screc
//
//  Created by Max Fomichev on 11/11/15.
//  Copyright © 2015 Pieci Kvadrati. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface screenRecorder : NSObject

- (id) setupCaptureSession: (unsigned char) _display
                andScreenResolution: (enum screenResolution_t) _screenResolution
                andFrameRate: (unsigned char) _frameRate
                andFontSize: (unsigned char) _fontSize andFileName: (const char *) _fileName;
- (void) imageFromSampleBuffer:(CMSampleBufferRef) _sampleBuffer;
- (void) stop;

@end
