//
//  SJAudioSession.m
//  AudioStreamDemo
//
//  Created by zhangshijian on 15/12/11.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import "SJAudioSession.h"

NSString *const SJAudioSessionInterruptionNotification = @"SJAudioSessionInterruptionNotification";

NSString *const SJAudioSessionRouteChangeReason = @"SJAudioSessionRouteChangeReason";

NSString *const SJAudioSessionRouteChangeNotification = @"SJAudioSessionRouteChangeNotification";

NSString *const SJAudioSessionInterruptionStateKey = @"SJAudioSessionInterruptionStateKey";

NSString *const SJAudioSessionInterruptionTypeKey = @"SJAudioSessionInterruptionTypeKey";

static void SJAudioSessionInterruptionListener(void *inClientData, UInt32 InterruptionState)
{
    AudioSessionInterruptionType InterruptionType = kAudioSessionInterruptionType_ShouldNotResume;
    
    UInt32 interruptionTypeSize = sizeof(InterruptionType);
    
    AudioSessionGetProperty(kAudioSessionProperty_InterruptionType, &interruptionTypeSize, &InterruptionType);
    
    NSDictionary *userInfo = @{SJAudioSessionInterruptionStateKey:@(InterruptionState), SJAudioSessionInterruptionTypeKey:@(InterruptionType)};
    
    SJAudioSession *audioSession = (__bridge SJAudioSession *)(inClientData);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SJAudioSessionInterruptionNotification object:audioSession userInfo:userInfo];
}

static void SJAudioSessionRouteChangeListener(void *inClientData, AudioSessionPropertyID inPropertyID, UInt32 inPropertyValueSize, const void*inPropertyValue)
{
    if (inPropertyID != kAudioSessionProperty_AudioRouteChange) {
        return;
    }
    
    CFDictionaryRef routeChangeDictionary = inPropertyValue;
    
    CFNumberRef routeChangeReasonRef = CFDictionaryGetValue(routeChangeDictionary, CFSTR(kAudioSession_AudioRouteChangeKey_Reason));
    
    SInt32 routeChangeReason;
    
    CFNumberGetValue(routeChangeReasonRef, kCFNumberSInt32Type, &routeChangeReason);
    
    NSDictionary *userInfo = @{SJAudioSessionRouteChangeReason:@(routeChangeReason)};
    
    SJAudioSession *audioSession = (__bridge SJAudioSession *)(inClientData);
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SJAudioSessionRouteChangeNotification object:audioSession userInfo:userInfo];
}



@implementation SJAudioSession

+ (id)sharedInstance
{
    static SJAudioSession *audioSession;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        audioSession = [[SJAudioSession alloc]init];
    });
    return audioSession;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        
        [self initalizeAudioSession];
    }
    return self;
}

- (void)dealloc
{
    AudioSessionRemovePropertyListenerWithUserData(kAudioSessionProperty_AudioRouteChange, SJAudioSessionRouteChangeListener, (__bridge void *)(self));
}

#pragma -mark private
- (void)errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError
{
    if (status != noErr && outError != NULL) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
}

- (void)initalizeAudioSession
{
    AudioSessionInitialize(NULL, NULL, SJAudioSessionInterruptionListener,(__bridge void *)(self));
    
    AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, SJAudioSessionRouteChangeListener, (__bridge void *)(self));
}


#pragma -mark public
- (BOOL)setActive:(BOOL)active error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioSessionSetActive(active);
    if (status == kAudioSessionNotInitialized) {
        [self initalizeAudioSession];
        status = AudioSessionSetActive(active);
    }
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)setActive:(BOOL)active options:(UInt32)options error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioSessionSetActiveWithFlags(active, options);
    if (status == kAudioSessionNotInitialized) {
        [self initalizeAudioSession];
        status = AudioSessionSetActiveWithFlags(active, options);
    }
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)setCategory:(UInt32)category error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
    if (status == kAudioSessionNotInitialized) {
        [self initalizeAudioSession];
        status = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
    }
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)setProperty:(AudioSessionPropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioSessionSetProperty(propertyID, dataSize, data);
    if (status == kAudioSessionNotInitialized) {
        [self initalizeAudioSession];
        status = AudioSessionSetProperty(propertyID, dataSize, data);
    }
    [self errorForOSStatus:status error:outError];
    return status;
}

- (BOOL)addPropertyListener:(AudioSessionPropertyID)propertyID listenerMethod:(AudioSessionPropertyListener)listenerMethod context:(void *)context error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioSessionAddPropertyListener(propertyID, listenerMethod, context);
    if (status == kAudioSessionNotInitialized) {
        [self initalizeAudioSession];
        status = AudioSessionAddPropertyListener(propertyID, listenerMethod, context);
    }
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)removePropertyListener:(AudioSessionPropertyID)propertyID listenerMethod:(AudioSessionPropertyListener)listenerMethod context:(void *)context error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioSessionRemovePropertyListenerWithUserData(propertyID, listenerMethod, context);
    if (status == kAudioSessionNotInitialized) {
        [self initalizeAudioSession];
        status = AudioSessionRemovePropertyListenerWithUserData(propertyID, listenerMethod, context);
    }
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}


@end
