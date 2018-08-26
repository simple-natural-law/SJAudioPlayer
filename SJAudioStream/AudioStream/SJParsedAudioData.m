//
//  SJParsedAudioData.m
//  SJAudioStream
//
//  Created by 张诗健 on 15/12/30.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import "SJParsedAudioData.h"

@interface SJParsedAudioData ()

@property (nonatomic, readwrite, strong) NSData *data;

@property (nonatomic, readwrite, assign) AudioStreamPacketDescription packetDescription;

@end

@implementation SJParsedAudioData


+ (instancetype)parsedAudioDataWithBytes:(const void *)bytes packetDescription:(AudioStreamPacketDescription)packetDescription
{
    return [[self alloc] initWithBytes:bytes packetDescription:packetDescription];
}


- (instancetype)initWithBytes:(const void *)bytes packetDescription:(AudioStreamPacketDescription)packetDescription
{
    if (bytes == NULL || packetDescription.mDataByteSize == 0)
    {
        return nil;
    }
    
    self = [super init];
    
    if (self)
    {
        self.data = [NSData dataWithBytes:bytes length:packetDescription.mDataByteSize];
        
        self.packetDescription = packetDescription;
    }
    return self;
}


@end
