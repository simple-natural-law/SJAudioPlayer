//
//  SJAudioCache.h
//  SJAudioPlayerDemo
//
//  Created by 张诗健 on 2020/5/22.
//  Copyright © 2020 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJAudioCache : NSObject

- (instancetype)initWithURL:(NSURL *)url;

- (BOOL)isExistDiskCache;

- (NSData *)getAudioDataWithLength:(NSUInteger)length;

- (void)storeAudioData:(NSData *)data;

- (void)seekToOffset:(unsigned long long)offset;

- (BOOL)removeAudioCache;

- (unsigned long long)getAudioDiskCacheContentLength;

- (void)closeWriteAndReadCache;

@end

NS_ASSUME_NONNULL_END
