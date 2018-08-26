//
//  SJAudioStream.h
//  SJAudioStream
//
//  Created by 张诗健 on 16/4/28.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface SJAudioStream : NSObject

/// 音频数据总长度
@property (nonatomic, assign, readonly) NSUInteger contentLength;


/// 根据 URL 和 数据偏移量（用于seek） 创建一个`SJAudioStream`对象
- (instancetype)initWithURL:(NSURL *)url byteOffset:(NSUInteger)byteOffset;


/**
 *  读取数据
 *
 *  param maxLength  最大读取长度
 *  param error      错误信息
 *  param isEof  是否已读完
 *  return  data     数据
 */
- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength error:(NSError **)error isEof:(BOOL *)isEof;


/// 关闭ReadStream
- (void)closeReadStream;


@end
