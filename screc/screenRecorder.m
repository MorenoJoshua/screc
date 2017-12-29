//
//  screenRecorder.m
//  screc
//
//  Created by Max Fomichev on 11/11/15.
//  Copyright © 2015 Pieci Kvadrati. All rights reserved.
//

#include <sys/types.h>
#include <sys/stat.h>

#include "wrapper.hpp"
#import "screenRecorder.h"

@interface screenRecorder () <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

@implementation screenRecorder {
    AVCaptureSession *m_session;
    AVAssetWriter *m_videoWriter;
    AVAssetWriterInput* m_writerInput;
    UInt64 m_writeFrames;
    UInt8 m_frameRate;
    UInt8 m_fontSize;
}

void *start(unsigned char _display, enum screenResolution_t _screenResolution,
            unsigned char _frameRate, unsigned char _fontSize, const char *_fileName)
{
    void *ret = NULL;
    @autoreleasepool {
        screenRecorder *recorder = [[screenRecorder alloc] setupCaptureSession:_display
                                                           andScreenResolution:_screenResolution
                                                                  andFrameRate:_frameRate
                                                                   andFontSize:_fontSize
                                                                   andFileName:_fileName];
        ret = (void *) CFBridgingRetain(recorder);
    }
    
    return ret;
}

- (id) setupCaptureSession: (unsigned char) _display
       andScreenResolution: (enum screenResolution_t) _screenResolution
              andFrameRate: (unsigned char) _frameRate
               andFontSize: (unsigned char) _fontSize andFileName: (const char *) _fileName
{
    NSError *error = nil;
    m_frameRate = _frameRate;
    m_fontSize = _fontSize;

    @autoreleasepool {
        m_session = [[AVCaptureSession alloc] init];
    
//        m_session.sessionPreset = AVCaptureSessionPresetMedium;
        m_session.sessionPreset = AVCaptureSessionPresetLow;

        int videoWidth = 0;
        int videoHeight = 0;
        switch (_screenResolution) {
            case SR320x240:
                m_session.sessionPreset = AVCaptureSessionPreset320x240;
                videoWidth = 320;
                videoHeight = 240;
                break;
            case SR352x288:
                m_session.sessionPreset = AVCaptureSessionPreset352x288;
                videoWidth = 352;
                videoHeight = 288;
                break;
            case SR640x480:
                m_session.sessionPreset = AVCaptureSessionPreset640x480;
                videoWidth = 640;
                videoHeight = 480;
                break;
            case SR960x540:
                m_session.sessionPreset = AVCaptureSessionPreset960x540;
                videoWidth = 960;
                videoHeight = 540;
                break;
            case SR1280x720:
                m_session.sessionPreset = AVCaptureSessionPreset1280x720;
                videoWidth = 1280;
                videoHeight = 720;
                break;
        }
    
//        CGDirectDisplayID displayID = CGMainDisplayID();
        uint32_t maxDisplays = 8;
        CGDirectDisplayID activeDisplays[maxDisplays];
        uint32_t displayCount;
        
        CGError displayErr = CGGetActiveDisplayList(maxDisplays, activeDisplays, &displayCount);
        if ((displayErr != kCGErrorSuccess) || (_display >= displayCount)) {
            return NULL;
        }
        
//        AVCaptureScreenInput *input = [[AVCaptureScreenInput alloc] initWithDisplayID:displayID];
        AVCaptureScreenInput *input = [[AVCaptureScreenInput alloc] initWithDisplayID:activeDisplays[_display]];
        if (!input) {
//            NSLog(@"%@",[error localizedDescription]);
            return NULL;
        }
        input.minFrameDuration = CMTimeMake(1, _frameRate);
    
        [m_session addInput:input];
    
        AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    
        dispatch_queue_t queue = dispatch_queue_create("myQueue", DISPATCH_QUEUE_SERIAL);
        [output setSampleBufferDelegate:self queue:queue];
    
        output.videoSettings = [NSDictionary dictionaryWithObject:
                                [NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                                           forKey:(id)kCVPixelBufferPixelFormatTypeKey];

        [m_session addOutput:output];
    
        NSString *outputFile = [NSString stringWithFormat:@"%s", _fileName];
        NSURL *outputFileUrl = [NSURL fileURLWithPath:outputFile];
        m_videoWriter = [AVAssetWriter assetWriterWithURL:outputFileUrl fileType:AVFileTypeMPEG4 error:&error];

        NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                       AVVideoCodecH264, AVVideoCodecKey,
                                       [NSNumber numberWithInt:videoWidth], AVVideoWidthKey,
                                       [NSNumber numberWithInt:videoHeight], AVVideoHeightKey,
                                       nil];

        m_writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                           outputSettings:videoSettings];
    
        m_writerInput.expectsMediaDataInRealTime = YES;
    
        [m_videoWriter addInput:m_writerInput];
        m_writeFrames = 0;
        [m_videoWriter startWriting];
        [m_videoWriter startSessionAtSourceTime:kCMTimeZero];
    
        [m_session startRunning];
        
#warning Make suru that 0666 is not dangerous
        chmod(_fileName, 0666);
    
//        NSLog(@"%s", "Display capturing started...");
    }
    
    return self;
}

// Delegate routine that is called when a sample buffer was written
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
fromConnection:(AVCaptureConnection *)connection
{
    if(!CMSampleBufferDataIsReady(sampleBuffer))
        return;
    
    @autoreleasepool {
        if( [m_writerInput isReadyForMoreMediaData] ) {
            CFRetain(sampleBuffer);
            CMSampleBufferRef newSampleBuffer = [self offsetTimmingWithSampleBufferForVideo:sampleBuffer];

            [self imageFromSampleBuffer:newSampleBuffer];
        
            BOOL wrote = [m_writerInput appendSampleBuffer:newSampleBuffer];
            if (wrote == NO) {
                if (m_videoWriter.status == AVAssetWriterStatusFailed) {
//                    NSLog(@"%s %llu %s %i", "video frame", m_writeFrames, "write failed", m_videoWriter.error.code);
                }
            }
            
            CFRelease(sampleBuffer);
            CFRelease(newSampleBuffer);

            m_writeFrames++;
        }
    }
}

// Create a frame image from sample buffer data
- (void) imageFromSampleBuffer:(CMSampleBufferRef) _sampleBuffer
{
    @autoreleasepool {
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(_sampleBuffer);
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
        void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
    
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
        CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                     bytesPerRow, colorSpace,
                                                     kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
        double timestamp = [[NSDate date] timeIntervalSince1970];
        time_t curTime = timestamp;
        uint16_t mls = (uint16_t)((timestamp - (double) curTime) * 1000);

        char timeTxt[256];
        memset(timeTxt, 0, sizeof(timeTxt));
        ctime_r(&curTime, timeTxt);

        if (strlen(timeTxt) > 0) {
            timeTxt[strlen(timeTxt) - 1] = 0;

            char part1[256];
            memset(part1, 0, sizeof(part1));
            char part2[256];
            memset(part2, 0, sizeof(part1));

            int i = 0;
            int first = 0;
            int second = 0;
            for (; i < strlen(timeTxt); i++) {
                if (timeTxt[i] == ':') {
                    if (first == 1)
                        second = 1;
                    else
                        first = 1;
                }
                if ((second == 1) && (timeTxt[i] == ' '))
                    break;
            }
            memmove(part1, timeTxt, i);
            memmove(part2, timeTxt + i + 1, strlen(timeTxt) - i - 1);
            memset(timeTxt, 0, sizeof(timeTxt));
            sprintf(timeTxt, "%s %s:%u", part2, part1, mls);
        }
    
        CGContextSelectFont(context, "Arial Bold", m_fontSize, kCGEncodingMacRoman);
        CGContextSetTextDrawingMode(context, kCGTextFill);
        CGContextSetRGBFillColor(context, 250, 0, 0, 1);
        CGContextShowTextAtPoint(context, width / 2 - 200, 68, timeTxt, strlen(timeTxt));

        CVPixelBufferUnlockBaseAddress(imageBuffer,0);

        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
    }
    
    return;
}

- (CMSampleBufferRef)offsetTimmingWithSampleBufferForVideo:(CMSampleBufferRef)sampleBuffer
{
    CMSampleBufferRef newSampleBuffer;
    CMSampleTimingInfo sampleTimingInfo;
    sampleTimingInfo.duration = CMTimeMake(1, m_frameRate);
    sampleTimingInfo.presentationTimeStamp = CMTimeMake(m_writeFrames, m_frameRate);
    sampleTimingInfo.decodeTimeStamp = kCMTimeInvalid;
    
    CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault,
                                          sampleBuffer,
                                          1,
                                          &sampleTimingInfo,
                                          &newSampleBuffer);
    
    
    return newSampleBuffer;
}

void stop(void *_objectInstance)
{
    @autoreleasepool {
        [(__bridge screenRecorder *) _objectInstance stop];
    }
    
    return;
}

- (void) stop
{
    @autoreleasepool {
//        NSLog(@"%s %llu", "Display capturing stoped", m_writeFrames);
        [m_writerInput markAsFinished];
        [m_videoWriter endSessionAtSourceTime:CMTimeMake(m_writeFrames, m_frameRate)];
//        [m_videoWriter finishWriting];
        [m_videoWriter finishWritingWithCompletionHandler:^{
            m_videoWriter = nil;
        }];

        [m_session stopRunning];
    }
}

@end
