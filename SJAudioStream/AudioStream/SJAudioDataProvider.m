//
//  SJAudioDataProvider.m
//  SJAudioStream
//
//  Created by 张诗健 on 16/4/29.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import "SJAudioDataProvider.h"
#import "SJHttpStream.h"
#import "SJAudioCacheDataStream.h"


@interface SJAudioDataProvider ()

@property (nonatomic, strong) SJHttpStream *stream;

@property (nonatomic, strong) SJAudioCacheDataStream *cacheDataStream;

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, strong) NSString *cachePath;

@property (nonatomic, assign) NSUInteger byteOffset;

@property (nonatomic, readwrite, assign) NSUInteger startOffset;

@property (nonatomic, readwrite, assign) NSUInteger contentLength;

@end

@implementation SJAudioDataProvider

- (instancetype)initWithURL:(NSURL *)url cacheFilePath:(NSString *)cacheFilePath byteOffset:(NSUInteger)byteOffset
{
    self = [super init];
    
    if (self)
    {
        self.url = url;
        self.cachePath   = cacheFilePath;
        self.byteOffset  = byteOffset;
        self.startOffset = byteOffset;
    }
    return self;
}


- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error completed:(BOOL *)completed
{
    // 音频数据偏移量 大于 音频数据总长度时 返回nil
    if (self.contentLength && self.byteOffset >= self.contentLength)
    {
        return nil;
    }
    
    if (!self.stream && self.url)
    {
        self.stream = [[SJHttpStream alloc] initWithURL:self.url byteOffset:self.byteOffset];
    }
    
    NSData *data = [self.stream readDataWithMaxLength:maxLength error:error completed:completed];
    
    return data;
}


- (NSUInteger)contentLength
{
    NSUInteger length = 0;
    
    length = self.cacheDataStream.contentLength;
    
    if (length)
    {
        return length;
    }
    
    length = self.stream.contentLength;
    
    return length;
}


- (void)close
{
    [self.stream close];
}

@end
