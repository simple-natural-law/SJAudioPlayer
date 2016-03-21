//
//  SJAudioNetWorkControl.h
//  SJAudioStream
//
//  Created by 张诗健 on 16/3/20.
//  Copyright © 2016年 张诗健. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SJAudioNetWorkControl : NSObject

@property (nonatomic,assign) NSUInteger contentLength;

- (instancetype)initWithURL:(NSURL *)url
                 byteoffset:(NSUInteger)byteoffset;


- (NSData *)readDataWithMaxlength:(NSUInteger)maxLength
                            error:(NSError **)error;

- (void)close;

@end
