//
//  SJAudioCache.m
//  SJAudioPlayerDemo
//
//  Created by 张诗健 on 2020/5/22.
//  Copyright © 2020 张诗健. All rights reserved.
//

#import "SJAudioCache.h"
#import <CommonCrypto/CommonDigest.h>

@interface SJAudioCache()

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, assign) BOOL isExistDiskCache;

@property (nonatomic, strong) NSFileHandle *readFileHandle;

@property (nonatomic, strong) NSFileHandle *writeFileHandle;

@property (nonatomic, strong) NSString *cachePath;

@end


@implementation SJAudioCache


- (instancetype)initWithURL:(NSURL *)url
{
    self = [super init];
    
    if (self)
    {
        self.url = url;
        
        if ([self.url isFileURL])
        {
            self.isExistDiskCache = YES;
            
            self.cachePath = self.url.path;
            
            self.readFileHandle = [NSFileHandle fileHandleForReadingAtPath:self.cachePath];
        }else
        {
            NSString *directryPath = [self getDirectryPath];
            
            NSString *fullNamespace = [self getMD5StringForString:self.url.absoluteString];
            
            NSString *cachePath = [directryPath stringByAppendingPathComponent:fullNamespace];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath])
            {
                self.isExistDiskCache = YES;
                
                self.cachePath = cachePath;
                
                self.readFileHandle = [NSFileHandle fileHandleForReadingAtPath:self.cachePath];
                
            }else
            {
                self.isExistDiskCache = NO;
                
                BOOL success = [self createDiskCacheWithDirectryPath:directryPath fullNamespace:fullNamespace];
                
                if (success)
                {
                    self.cachePath = cachePath;
                    
                    self.readFileHandle  = [NSFileHandle fileHandleForReadingAtPath:self.cachePath];
                    
                    self.writeFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.cachePath];
                }else
                {
                    if (DEBUG)
                    {
                        NSLog(@"SJAudioCacheManager: failed to create audio file.");
                    }
                }
            }
        }
    }
    
    return self;
}


- (NSData *)getAudioDataWithLength:(NSUInteger)length
{
   return [self.readFileHandle readDataOfLength:length];
}


- (void)storeAudioData:(NSData *)data
{
    [self.writeFileHandle seekToEndOfFile];
    
    [self.writeFileHandle writeData:data];
}


- (void)seekToOffset:(unsigned long long)offset
{
    [self.readFileHandle seekToFileOffset:offset];
}


- (BOOL)removeAudioCache
{
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:self.cachePath error:nil];
    
    return success;
}



- (void)closeWriteAndReadCache
{
    [self.readFileHandle closeFile];
    
    if (self.writeFileHandle)
    {
        [self.writeFileHandle closeFile];
    }
}


- (unsigned long long)getAudioDiskCacheContentLength
{
    return [[[NSFileManager defaultManager] attributesOfItemAtPath:self.cachePath error:nil] fileSize];;
}


- (BOOL)createDiskCacheWithDirectryPath:(NSString *)directryPath fullNamespace:(NSString *)fullNamespace
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:directryPath])
    {
        NSString *filePath = [directryPath stringByAppendingPathComponent:fullNamespace];
        
        BOOL success = [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
        
        return success;
    }else
    {
        BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:directryPath withIntermediateDirectories:YES attributes:nil error:nil];
        
        if (success)
        {
            NSString *filePath = [directryPath stringByAppendingPathComponent:fullNamespace];
            
            success = [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
        }
        
        return success;
    }
}


- (NSString *)getDirectryPath
{
    return [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"Audio"];
}


- (NSString *)getMD5StringForString:(NSString *)str
{
    const char *cStr = [str UTF8String];
    
    unsigned char result[16];
    
    CC_MD5(cStr, (CC_LONG)strlen(cStr), result);
    
    NSString *md5String = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",result[0], result[1], result[2], result[3],result[4], result[5], result[6], result[7],result[8], result[9], result[10], result[11],result[12], result[13], result[14], result[15]];
    
    return md5String;
}


@end
