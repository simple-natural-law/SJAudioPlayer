//
//  SJAudioFileStream.m
//  SJAudioStream
//
//  Created by zhangshijian on 15/12/14.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import "SJAudioFileStream.h"
#import "SJParsedAudioData.h"

#define BitRateEstimationMaxPackets 5000
#define BitRateEstimationMinPackets 50


@interface SJAudioFileStream ()

@property (nonatomic, assign, readwrite) AudioFileTypeID fileType;

@property (nonatomic, assign, readwrite) BOOL available;

@property (nonatomic, assign, readwrite) BOOL readyToProducePackets;

@property (nonatomic, assign, readwrite) AudioStreamBasicDescription format;

@property (nonatomic, assign, readwrite) NSUInteger fileSize;

@property (nonatomic, assign, readwrite) NSTimeInterval duration;

@property (nonatomic, assign, readwrite) UInt32 bitRate;

@property (nonatomic, assign, readwrite) UInt32 maxPacketSize;

@property (nonatomic, assign, readwrite) UInt64 audioDataSize;

@property (nonatomic, assign) BOOL discontinuous;
// 文件流ID
@property (nonatomic, assign) AudioFileStreamID audioFileStreamID;

@property (nonatomic, assign) SInt64 dataOffset;

@property (nonatomic, assign) NSTimeInterval packetDuration;

@property (nonatomic, assign) UInt64 processedPacketsCount;

@property (nonatomic, assign) UInt64 processedPacketsSizeTotal;

@end



@implementation SJAudioFileStream

- (void)errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError
{
    if (status != noErr && outError != NULL)
    {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
}


- (instancetype)initWithFileType:(AudioFileTypeID)fileType fileSize:(NSUInteger)fileSize error:(NSError **)error
{
    self = [super init];
    
    if (self)
    {
        self.discontinuous = NO;
        
        self.fileType = fileType;
        
        self.fileSize = fileSize;
        
        [self openAudioFileStreamWithFileTypeHint:self.fileType error:error];
    }
    
    return self;
}


- (BOOL)openAudioFileStreamWithFileTypeHint:(AudioFileTypeID)fileTypeHint error:(NSError *__autoreleasing *)error
{
    // 打开AudioFileStream来读取采样率、码率、时长等基本信息以及分离音频帧。
    OSStatus status = AudioFileStreamOpen((__bridge void * _Nullable)(self), SJAudioFileStreamPropertyListener, SJAudioFileStreamPacketsCallBack, fileTypeHint, &_audioFileStreamID);
    
    if (status != noErr)
    {
        self.audioFileStreamID = NULL;
    }
    
    [self errorForOSStatus:status error:error];
    
    return status == noErr;
}


- (void)close
{
    if (self.available)
    {
        AudioFileStreamClose(self.audioFileStreamID);
        
        self.audioFileStreamID = NULL;
    }
}



- (BOOL)available
{
    return self.audioFileStreamID != NULL;
}


- (void)handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID
{
    // 一旦解析到音频数据的开头，流的所有属性就都是已知的了。
    
    switch (propertyID)
    {
        case kAudioFileStreamProperty_ReadyToProducePackets:
        {
            self.readyToProducePackets = YES;
            self.discontinuous = YES;
            
            UInt32 sizeOfUInt32 = sizeof(self.maxPacketSize);
            
            //  获取文件中理论上最大的数据包的大小
            OSStatus status = AudioFileStreamGetProperty(self.audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &_maxPacketSize);
            
            // 如果获取失败或者最大数据包的大小为0
            if (status != noErr || self.maxPacketSize == 0)
            {
                // 则获取文件中包含的数据包的最大尺寸
                status = AudioFileStreamGetProperty(self.audioFileStreamID, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &_maxPacketSize);
            }
            
            if (self.delegate && [self.delegate respondsToSelector:@selector(audioFileStreamReadyToProducePackets:)])
            {
                [self.delegate audioFileStreamReadyToProducePackets:self];
            }
        }
            break;
        
        case kAudioFileStreamProperty_DataOffset:
        {
            UInt32 offsetSize = sizeof(self.dataOffset);
            
            // kAudioFileStreamProperty_DataOffset表示音频数据在整个音频文件中的offset，因为大多数音频文件都会有一个文件头，之后才是真正的音频数据。这个值在seek时会发挥比较大的作用，音频的seek并不是直接seek文件位置而seek时间（比如seek到2分10秒的位置），seek时会根据时间计算出音频数据的字节offset然后需要再加上音频数据的offset才能得到在文件中的真正offset。
            AudioFileStreamGetProperty(self.audioFileStreamID, kAudioFileStreamProperty_DataOffset, &offsetSize, &_dataOffset);
            
            self.audioDataSize = self.fileSize - self.dataOffset;
            
            // 计算音频持续时长
            [self calculateDuration];
        }
            break;
            
        case kAudioFileStreamProperty_DataFormat:
        {
            UInt32 asbdSize = sizeof(self.format);
            
            // kAudioFileStreamProperty_DataFormat用来描述音频数据的格式
            AudioFileStreamGetProperty(self.audioFileStreamID, kAudioFileStreamProperty_DataFormat, &asbdSize, &_format);
            
            // 计算数据包间隔时长
            [self calculatePacketDuration];
        }
            break;
            
        case kAudioFileStreamProperty_FormatList:
        {
            Boolean outWriteable;
            UInt32 formatListSize;
            
            // 该方法用来获取某个属性对应的数据的大小(outDataSize)以及该属性是否可以被write（isWriteable）AudioFileStreamGetProperty用来获取属性对应的数据.对于一些大小可变的属性需要先使用 AudioFileStreamGetPropertyInfo获取数据大小，之后才能获取数据(例如formatList)。而有些确定类型单个属性则不必先调用AudioFileGetPropertyInfo，直接调用AudioFileGetProperty即可（比如BitRate）。
            // kAudioFileStreamProperty_FormatList (为了支持包括AAC和SBR格式编码的数据流可以被解码到多个目的地的格式，此属性返回包含这些格式的AudioFormatListItems数组（见AudioFormat.h）。默认行为是与kAudioFileStreamProperty_DataFormat属性返回相同的AudioStreamBasicDescription的一个AudioFormatListItem。)
            OSStatus status = AudioFileStreamGetPropertyInfo(self.audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, &outWriteable);
            
            if (status == noErr)
            {
                // 获取formatlist
                AudioFormatListItem *formatlist = malloc(formatListSize);
                
                OSStatus status = AudioFileStreamGetProperty(self.audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, formatlist);
                
                if (status == noErr)
                {
                    UInt32 supportedFormatsSize;
                    
                    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize);
                    
                    if (status != noErr)
                    {
                        // 错误处理
                        free(formatlist);
                        return;
                    }
                    
                    UInt32 supportedFormatCount = supportedFormatsSize / sizeof(OSType);
                    
                    OSType *supportedFormats = (OSType *)malloc(supportedFormatsSize);
                    
                    status = AudioFormatGetProperty(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatCount, supportedFormats);
                    
                    if (status != noErr)
                    {
                        // 错误处理
                        free(formatlist);
                        free(supportedFormats);
                        return;
                    }
                    
                    // 选择需要的格式
                    for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i += sizeof(AudioFormatListItem))
                    {
                        AudioStreamBasicDescription format = formatlist[i].mASBD;
                        
                        for (UInt32 j = 0; j < supportedFormatCount; ++j)
                        {
                            
                            if (format.mFormatID == supportedFormats[j])
                            {
                                self.format = format;
                                [self calculatePacketDuration];
                                break;
                            }
                        }
                    }
                    free(supportedFormats);
                }
                free(formatlist);
            }
        }
            break;
            
        default:
            break;
    }
}

- (void)handleAudioFileStreamPackets:(const void *)packets
                       numberOfBytes:(UInt32)numberOfBytes
                     numberOfPackets:(UInt32)numberOfPackets
                  packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions
{
    if (self.discontinuous) {
        self.discontinuous = NO;
    }
    if (numberOfBytes == 0 || numberOfPackets == 0) {
        return;
    }
    
    BOOL deletePackDesc = NO;
    
    // 如果 packetDescriptions 不存在，就按照CBR处理，平均每一帧的数据后生成packetDescriptions
    if (packetDescriptions == NULL) {
        deletePackDesc = YES;
        
        UInt32 packetSize = numberOfBytes / numberOfPackets;
        
        AudioStreamPacketDescription *description = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * numberOfPackets);
        
        for (int i = 0; i < numberOfPackets; i++) {
            UInt32 packetOffset = packetSize * i;
            description[i].mStartOffset = packetOffset;
            description[i].mVariableFramesInPacket = 0;
            if (i == numberOfPackets - 1) {
                description[i].mDataByteSize = numberOfBytes - packetOffset;
            }else
            {
                description[i].mDataByteSize = packetSize;
            }
        }
        packetDescriptions = description;
    }
    
    NSMutableArray *parsedDataArray = [[NSMutableArray alloc] init];
    
    for (int i = 0; i < numberOfPackets; ++i) {
        SInt64 packetOffset = packetDescriptions[i].mStartOffset;
        
        // 把解析出来的帧数据放进自己的buffer中
        SJParsedAudioData *parsedData = [SJParsedAudioData parsedAudioDataWithBytes:packets + packetOffset packetDescription:packetDescriptions[i]];
        
        [parsedDataArray addObject:parsedData];
        
        if (self.processedPacketsCount < BitRateEstimationMaxPackets) {
            self.processedPacketsSizeTotal += parsedData.packetDescription.mDataByteSize;
            self.processedPacketsCount += 1;
            [self calculateBitRate];
            [self calculateDuration];
        }
        
    }
    
    [self.delegate audioFileStream:self audioDataParsed:parsedDataArray];
    
    if (deletePackDesc)
    {
        free(packetDescriptions);
    }
}


/*
 A void * pointing to memory set up by the caller.
 Some file types require that a magic cookie be provided before packets can be written
 to the file, so this property should be set before calling
 AudioFileWriteBytes()/AudioFileWritePackets() if a magic cookie exists.
 */
- (NSData *)fetchMagicCookie
{
    UInt32 cookieSize;
    Boolean writable;
    OSStatus status = AudioFileStreamGetPropertyInfo(self.audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if (status != noErr) {
        return nil;
    }
    
    void *cookieData = malloc(cookieSize);
    status = AudioFileStreamGetProperty(self.audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if (status != noErr) {
        return nil;
    }
    NSData *cookie = [NSData dataWithBytes:cookieData length:cookieSize];
    free(cookieData);
    return cookie;
}

- (BOOL)parseData:(NSData *)data error:(NSError **)error
{
    if (self.readyToProducePackets && self.packetDuration == 0) {
        [self errorForOSStatus:-1 error:error];
        return NO;
    }
    OSStatus status = AudioFileStreamParseBytes(self.audioFileStreamID, (UInt32)[data length], [data bytes], self.discontinuous ? kAudioFileStreamParseFlag_Discontinuity : 0);
    [self errorForOSStatus:status error:error];
    return status == noErr;
}

/*
 seek : 拖动到xx分xx秒，而实际操作时我们需要操作的是文件，就是要从第几个字节开始读取音频数据。对于原始的PCM数据来说，每一个PCM帧都是固定长度的，对应的播放时长也是固定的。但一旦转换成压缩后的音频数据就会因为编码形式的不同而不同了，对于CBR（固定码率）而言每个帧中所包含的PCM数据帧是恒定的，所以每一帧对应的播放时长也是恒定的；而VBR（可变码率）则不同，为了保证数据最优并且文件大小最小，VBR的每一帧中所包含的PCM数据帧是不固定的，这就导致在流播放的情况下VBR的数据想要做seek并不容易。这里只讨论CBR下的seek
 
 double seekToTime ＝ ...; // 需要seek到哪个时间，秒为单位
 Uint64 audioDataByteCount = ...; // 通过kAudioFileStreamProperty_AudioDataByteCount获取的值
 Sint64 dataOffset = ...; // 通过kAudioFileStreamProperty_DataOffset获取的值
 double duration = ...; // 通过公式(AudioDataByteCount * 8) / BitRate 计算得到时长
 
 按照seekByteOffset读取对应的数据继续使用 AudioFileStreamParseByte 方法来进行解析
 如果是网络流可以通过设置range头来获取字节，本地文件的话直接seek就好。 ⚠ 调用AudioFileStreamParseByte 方法时注意刚seek完第一次parse数据需要加参数 kAudioFileStreamParseFlag_Discontinuity。
 
 */
- (SInt64)seekToTime:(NSTimeInterval *)time
{
    // 近似seekOffset = 数据偏移 + seekToTime对应的近似字节数
    SInt64 approximateSeekoffset = self.dataOffset + (*time / self.duration) * self.audioDataSize;
    
    // floor() 向下取整  计算packet位置
    SInt64 seekToPacket = floor(*time / self.packetDuration);
    SInt64 seekByteOffset;
    UInt32 ioFlags = 0;
    SInt64 outDataByteOffset;
    /*
     使用AudioStreamSeek计算精确的字节偏移和时间
     AudioStreamSeek 可以用来寻找某一个帧（packet）对应的字节偏移（byte offset）：如果ioFlags里有kAudioFileStreamFlag_OffsetIsEstimated 说明给出的outDataByteOffset是估算的，并不准确，那么还是应该用第一步计算出来的approximateSeekOffset来做seek； 如果ioFlags里没有 kAudioFileStreamFlag_OffsetIsEstimated 说明给出了准确的outDataByteOffset， 就是输入的seekToPacket对应的字节偏移量，可以根据outDataByteOffset来计算出精确的seekOffset 和 seekToTime；
     */
    OSStatus status = AudioFileStreamSeek(self.audioFileStreamID, seekToPacket, &outDataByteOffset, &ioFlags);
    if (status == noErr && !(ioFlags & kAudioFileStreamSeekFlag_OffsetIsEstimated))
    {
        // 如果AudioFileStreamSeek方法找到了准确的帧字节偏移，就需要修正一下时间
        *time -= ((approximateSeekoffset - self.dataOffset) - outDataByteOffset) * 8.0 / self.bitRate;
        
        seekByteOffset = outDataByteOffset + self.dataOffset;
    }else
    {
        self.discontinuous = YES;
        seekByteOffset = approximateSeekoffset;
    }
    return seekByteOffset;
}



#pragma -mark
// 计算码率
- (void)calculateBitRate
{
    if (self.packetDuration && self.processedPacketsCount > BitRateEstimationMinPackets && self.processedPacketsCount <= BitRateEstimationMaxPackets)
    {
        double averagePacketByteSize = self.processedPacketsSizeTotal / self.processedPacketsCount;
        self.bitRate = 8.0 * averagePacketByteSize / self.packetDuration;
    }

}

/*
 获取时长的最佳方法是从ID3信息中去读取，那样是最准确的。如果ID3信息中没有存，那就依赖于文件头中的信息去计算。
 
 音频数据的字节总量`audioDataByteCount`可以通`kAudioFileStreamProperty_AudioDataByteCount`获取
 码率`bitRate`可以通过`kAudioFileStreamProperty_BitRate`获取，也可以通过解析一部分数据后计算平均码率
 来得到。
*/
- (void)calculateDuration
{
    if (self.fileSize > 0 && self.bitRate > 0)
    {
        self.duration = (self.audioDataSize * 8.0) / self.bitRate;
    }
}


/*
 利用之前解析得到的音频格式信息来计算PacketDuration（每个帧数据对应的时长）。
*/
- (void)calculatePacketDuration
{
    if (self.format.mSampleRate > 0)
    {
        self.packetDuration = self.format.mFramesPerPacket / self.format.mSampleRate;
    }
}


/*
 在调用`AudioFileStreamParseBytes`方法进行解析时会首先读取格式信息，每解析出一个音频的格式信息都会同步调用一次此方法。
 
 注意`AudioFileStreamParseBytes`方法每一次调用都应该注意返回值，一旦出现错误就可以不用继续解析了。
*/
static void SJAudioFileStreamPropertyListener(void *inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags)
{
    SJAudioFileStream *audioFileStream = (__bridge SJAudioFileStream *)inClientData;
    
    [audioFileStream handleAudioFileStreamProperty:inPropertyID];
}


/*
 读取格式信息完成之后，继续调用`AudioFileStreamParseBytes`方法可以对帧进行分离，每解析出一部分帧就会同步调用一次此方法。
*/
static void SJAudioFileStreamPacketsCallBack(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescription)
{
    SJAudioFileStream *audioFileStream = (__bridge SJAudioFileStream *)inClientData;
    
    [audioFileStream handleAudioFileStreamPackets:inInputData numberOfBytes:inNumberBytes numberOfPackets:inNumberPackets packetDescriptions:inPacketDescription];
}

@end

