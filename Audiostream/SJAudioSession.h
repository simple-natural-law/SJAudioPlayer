//
//  SJAudioSession.h
//  AudioStreamDemo
//
//  Created by zhangshijian on 15/12/11.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

/* route change notification  */
FOUNDATION_EXPORT NSString *const SJAudioSessionRouteChangeNotification;

/* a NSNumber of SInt32
 enum {
 kAudioSessionRouteChangeReason_Unknown = 0,
 kAudioSessionRouteChangeReason_NewDeviceAvailable = 1,
 kAudioSessionRouteChangeReason_OldDeviceUnavailable = 2,
 kAudioSessionRouteChangeReason_CategoryChange = 3,
 kAudioSessionRouteChangeReason_Override = 4,
 kAudioSessionRouteChangeReason_WakeFromSleep = 6,
 kAudioSessionRouteChangeReason_NoSuitableRouteForCategory = 7,
 kAudioSessionRouteChangeReason_RouteConfigurationChange = 8
 };
 */
FOUNDATION_EXPORT NSString *const SJAudioSessionRouteChangeReason;

/* interrupt notification */
FOUNDATION_EXPORT NSString *const SJAudioSessionInterruptionNotification;

/* a NSNumber of kAudioSessionBeginInterruption or kAudioSessionEndInterruption */
FOUNDATION_EXPORT NSString *const SJAudioSessionInterruptionStateKey;

/* Only present for kAudioSessionEndInterruption. a NSNumber of AudioSessionInterruptionType.*/
FOUNDATION_EXPORT NSString *const SJAudioSessionInterruptionTypeKey;


@interface SJAudioSession : NSObject

+ (id)sharedInstance;

- (BOOL)setActive:(BOOL)active error:(NSError **)outError;
/**
 *  options:
 *  enum {
 *       kAudioSessionSetActiveFlag_NotifyOthersOnDeactivation       = (1 << 0)  //  0x01
 *   };
 *
 */
- (BOOL)setActive:(BOOL)active options:(UInt32)options error:(NSError **)outError;

/**
 *  enum {
 *   kAudioSessionCategory_AmbientSound               = 'ambi',
 *   kAudioSessionCategory_SoloAmbientSound           = 'solo',
 *   kAudioSessionCategory_MediaPlayback              = 'medi',
 *   kAudioSessionCategory_RecordAudio                = 'reca',
 *   kAudioSessionCategory_PlayAndRecord              = 'plar',
 *   kAudioSessionCategory_AudioProcessing            = 'proc'
 *   };
 */
- (BOOL)setCategory:(UInt32)category error:(NSError **)outError;

- (BOOL)setProperty:(AudioSessionPropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data error:(NSError **)outError;
- (BOOL)addPropertyListener:(AudioSessionPropertyID)propertyID listenerMethod:(AudioSessionPropertyListener)listenerMethod context:(void *)context error:(NSError **)outError;
- (BOOL)removePropertyListener:(AudioSessionPropertyID)propertyID listenerMethod:(AudioSessionPropertyListener)listenerMethod context:(void *)context error:(NSError **)outError;

+ (BOOL)usingHeadset;
+ (BOOL)isAirplayActived;

@end
