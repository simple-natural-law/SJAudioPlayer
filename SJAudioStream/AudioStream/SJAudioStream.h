//
//  SJAudioStream.h
//  SJAudioStream
//
//  Created by 张诗健 on 16/4/28.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SJAudioStream;

@protocol SJAudioStreamDelegate <NSObject>

- (void)audioStreamHasBytesAvailable:(SJAudioStream *)audioStream;

- (void)audioStreamErrorOccurred:(SJAudioStream *)audioStream;

- (void)audioStreamEndEncountered:(SJAudioStream *)audioStream;

@end


@interface SJAudioStream : NSObject

/// 音频数据总长度
@property (nonatomic, assign, readonly) NSUInteger contentLength;

/// 根据 URL 和 数据偏移量（用于seek） 创建HTTP请求
- (instancetype)initWithURL:(NSURL *)url byteOffset:(SInt64)byteOffset delegate:(id<SJAudioStreamDelegate>)delegate;

/// 读取数据
- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error;

/// 关闭ReadStream
- (void)closeReadStream;

- (BOOL)hasBytesAvailable;

@end
