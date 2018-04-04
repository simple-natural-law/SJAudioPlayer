//
//  SJAudioDataProvider.m
//  AudioTest
//
//  Created by 张诗健 on 16/4/29.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJAudioDataProvider.h"
#import "SJHttpStream.h"
#import "SJAudioCacheDataStream.h"


@interface SJAudioDataProvider ()



@end

@implementation SJAudioDataProvider
{
    SJHttpStream     *_stream;
    SJAudioCacheDataStream *_cacheDataStream;
    NSString         *_cachePath;
    NSUInteger        _byteOffset;
    NSURL            *_url;
}

- (void)dealloc
{
    
}


- (instancetype)initWithURL:(NSURL *)url cacheFilePath:(NSString *)cacheFilePath byteOffset:(NSUInteger)byteOffset
{
    self = [super init];
    
    if (self)
    {
        _url = url;
        _cachePath   = cacheFilePath;
        _byteOffset  = byteOffset;
        _startOffset = byteOffset;
    }
    return self;
}


- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength isEof:(BOOL *)isEof
{
    // 音频数据偏移量 大于 音频数据总长度时 返回nil
    if (self.contentLength && _byteOffset >= self.contentLength)
    {
        return nil;
    }
    
    if (!_stream && _url)
    {
        _stream = [[SJHttpStream alloc]initWithURL:_url byteOffset:_byteOffset];
    }
    
    NSData *data = [_stream readDataWithMaxLength:maxLength isEof:isEof];
    
    return data;
}


- (NSUInteger)contentLength
{
    NSUInteger length = 0;
    
    length = _cacheDataStream.contentLength;
    
    if (length)
    {
        return length;
    }
    
    length = _stream.contentLength;
    
    return length;
}


- (void)close
{
    [_stream close];
}

@end
