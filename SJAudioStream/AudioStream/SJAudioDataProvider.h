//
//  SJAudioDataProvider.h
//  AudioTest
//
//  Created by 张诗健 on 16/4/29.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SJAudioDataProvider : NSObject

/**
 *  开始读取数据时的音频数据偏移量
 */
@property (nonatomic, readonly) NSUInteger startOffset;


/**
 *  音频数据总长度
 */
@property (nonatomic, readonly) NSUInteger contentLength;



/**
 *  初始化对象
 *
 *  @param url           URL
 *  @param cacheFilePath 缓存路径
 *  @param byteOffset    音频数据偏移(seek)
 *
 *  @return
 */
- (instancetype)initWithURL:(NSURL *)url cacheFilePath:(NSString *)cacheFilePath byteOffset:(NSUInteger)byteOffset;


/**
 *  读取音频数据
 *
 *  @param maxLength 最大返回数据长度
 *  @param error     error地址
 *
 *  @return
 */
- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength isEof:(BOOL *)isEof;


- (void)close;

@end
