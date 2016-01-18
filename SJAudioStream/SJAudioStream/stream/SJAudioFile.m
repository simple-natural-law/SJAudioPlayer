//
//  SJAudioFile.m
//  AudioStreamDemo
//
//  Created by zhangshijian on 15/12/14.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import "SJAudioFile.h"
#import "SJParsedAudioData.h"


static const UInt32 packetPerRead = 15;


@interface SJAudioFile ()
{
@private
    SInt64 _packetOffset;
    NSFileHandle *_fileHandler;  // 此类主要是对文件内容进行读取和写入操作
    
    SInt64 _dataoffset;
    NSTimeInterval _packetDurationn;
    
    AudioFileID _audioFileID;
}

@end


@implementation SJAudioFile

@synthesize filePath = _filePath;
@synthesize fileType = _fileType;
@synthesize fileSize = _fileSize;
@synthesize duration = _duration;
@synthesize bitRate = _bitRate;
@synthesize format = _format;
@synthesize maxPacketSize = _maxPacketSize;
@synthesize audioDataByteCount = _audioDataByteCount;

#pragma -mark -init & dealloc
- (instancetype)initWithFilePath:(NSString *)filePath fileType:(AudioFileTypeID)fileType
{
    self = [super init];
    if (self) {
        _filePath = filePath;
        _fileType = fileType;
        
        // 根据文件路径打开文件，准备读取.
        _fileHandler = [NSFileHandle fileHandleForReadingAtPath:_filePath];
        
        // 获取文件的大小
        _fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:_filePath error:nil] fileSize];
        
        if (_fileHandler && _fileSize > 0)
        {
            if ([self openAudioFile]) {
                [self fetchFormatInfo];
            }
        }else
        {
            // 关闭文件
            [_fileHandler closeFile];
        }
    }
    return self;
}




- (void)dealloc
{
    [_fileHandler closeFile];
    [self closeAudioFile];
}


#pragma -mark audioFile
/*
 AudioFile提供了两个打开文件的方法：
 1、 AudioFileOpenURL
 
 enum 
 {
      kAudioFileReadPermission      = 0x01,
      kAudioFileWritePermission     = 0x02,
      kAudioFileReadWritePermission = 0x03
 };
 
 extern OSStatus AudioFileOpenURL (CFURLRef inFileRef,
                                   SInt8 inPermissions,
                                   AudioFileTypeID inFileTypeHint,
                                   AudioFileID * outAudioFile);
 
 从方法的定义上来看时用来读取本地文件的：
 第一个参数，文件路径；
 第二个参数，文件的允许使用方式，是读，写还是读写，如果打开文件后进行了允许使用方式之外的操作，就得到 kAudioFilePermissionsError 错误码（比如 open 时声明是kAudioFileReadPermission 但却调用了 AudioFileWriteBytes）；
 第三个参数，和 AudioFileStream 的open方法中一样是一个帮助AudioFile解析文件的类型提示，如果文件类型确定的话应当传入；
 第四个参数，返回AudioFile实例对应的AudioFileID，这个ID需要保存起来作为后续一些方法的参数使用。
 
 返回值 OSStatus 用来判断是否成功打开文件。
 
 
 2、 AudioFileOpenWithCallbacks
     extern OSStatus AudioFileOpenWithCallbacks (void * inClientData,
                                                 AudioFile_ReadProc inReadFunc,
                                                 AudioFile_WriteProc inWriteFunc,
                                                 AudioFile_GetSizeProc inGetSizeFunc,
                                                 AudioFile_SetSizeProc inSetSizeFunc,
                                                 AudioFileTypeID inFileTypeHint,
                                                AudioFileID * outAudioFile);
 
    第一个参数，上下文信息
    第二个参数，当 AudioFile 需要 读 音频数据时进行的回调（调用Open和Read方式后 同步 回调）；
    第三个参数，当 AudioFile 需要 写 音频数据时进行的回调（写音频文件功能时使用，暂不讨论）；
    第四个参数，当 AudioFile 需要用到文件的总大小时回调  （调用Open和Read方式后同步回调）；
    第五个参数，当 AudioFile 需要设置文件的大小时的回调  （写音频文件功能时使用，暂不讨论）；
    第六，七个参数和返回值同 AudioFileOpenURL 方法
    
    这个方法的重点在于 AudioFile_ReadProc 这个回调。换一个角度理解，这个方法相比于第一个方法自由度更高，AudioFile需要的只是一个数据源，无论是磁盘上的文件、内存里的数据甚至是网络流只要能在AudioFile需要数据时（Open和Read时）通过AudioFile_ReadProc回调为AudioFile提供合适的数据就可以了，也就是说使用方法不仅仅可以读取本地文件也可以如AudioFileStream一样以流的形式读取数据。
 */
- (BOOL)openAudioFile
{
    OSStatus status = AudioFileOpenWithCallbacks((__bridge void * _Nonnull)(self), SJAudioFileReadCallBack, NULL, SJAudioFileGetSizeCallBack, NULL, _fileType, &_audioFileID);
    
    if (status != noErr) {
        _audioFileID = NULL;
        return NO;
    }
    
    return YES;
}




// 读取音频格式信息(具体注释，参看 AudioFileStream)
- (void)fetchFormatInfo
{
    
    // 获取格式信息
    UInt32 formatlistSize;
    
    OSStatus status = AudioFileGetPropertyInfo(_audioFileID, kAudioFilePropertyFormatList, &formatlistSize, NULL);
    
    if (status == noErr) {
        
        BOOL found = NO;
        
        AudioFormatListItem *formatList = malloc(formatlistSize);
        
        OSStatus status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyFormatList, &formatlistSize, formatList);
        
        if (status == noErr) {
            UInt32 supportedFormatsSize;
            
            status = AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize);
            
            if (status != noErr) {
                free(formatList);
                [self closeAudioFile];
                return;
            }
            
            UInt32 supportedFormatCount = supportedFormatsSize / sizeof(OSType);
            
            OSType *supportedFormats = (OSType *)malloc(supportedFormatsSize);
            
            status = AudioFormatGetProperty(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize, supportedFormats);
            
            if (status != noErr) {
                free(formatList);
                free(supportedFormats);
                [self closeAudioFile];
                return;
            }
            
            for (int i = 0; i * sizeof(AudioFormatListItem) < formatlistSize; i += sizeof(AudioFormatListItem)) {
                AudioStreamBasicDescription format = formatList[i].mASBD;
                // 选择需要的格式
                for (UInt32 j = 0; j < supportedFormatCount; ++j) {
                    if (format.mFormatID == supportedFormats[j]) {
                        
                        _format = format;
                        found = YES;
                        break;
                    }
                }
            }
            free(supportedFormats);
        }
        free(formatList);
        
        if (!found) {
            
            [self closeAudioFile];
            
            return;
            
        }else
        {
            [self calculatePacketDuration];
        }
    }
    
    // 获取码率
    UInt32 size = sizeof(_bitRate);
    
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyBitRate, &size, &_bitRate);
    
    if (status != noErr) {
        [self closeAudioFile];
        return;
    }
    
    // 获取音频数据的偏移（大多数音频文件都会有一个文件头，之后才是真正的音频数据）
    size = sizeof(_dataoffset);
    
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyDataOffset, &size, &_dataoffset);
    
    if (status != noErr) {
        [self closeAudioFile];
        return;
    }
    
    // 计算音频数据字节数
    _audioDataByteCount = _fileSize - _dataoffset;
    
    // 获取音频时长
    size = sizeof(_duration);
    
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyEstimatedDuration, &size, &_duration);
    
    // 如果获取失败，就要手动计算
    if (status != noErr) {
        [self calculateDuration];
    }
    
    
    // 获取文件中包含的数据包的最大尺寸
    size = sizeof(_maxPacketSize);
    
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyMaximumPacketSize, &size, &_maxPacketSize);
    
    if (status != noErr || _maxPacketSize == 0) {
        status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyMaximumPacketSize, &size, &_maxPacketSize);
        
        if (status != noErr) {
            
            [self closeAudioFile];
            return;
        }
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
    OSStatus status = AudioFileGetPropertyInfo(_audioFileID, kAudioFilePropertyMagicCookieData, &cookieSize, NULL);
    if (status != noErr) {
        return nil;
    }
    
    void *cookieData = malloc(cookieSize);
    status = AudioFileGetProperty(_audioFileID, kAudioFilePropertyMagicCookieData, &cookieSize, cookieData);
    if (status != noErr) {
        return nil;
    }
    
    NSData *cookie = [NSData dataWithBytes:cookieData length:cookieSize];
    free(cookieData);
    
    return cookie;
}




- (NSArray *)parseData:(BOOL *)isEof
{
    UInt32 ioNumPackets = packetPerRead;
    
    UInt32 ioNumBytes = ioNumPackets * _maxPacketSize;
    
    void *outBuffer = (void *)malloc(ioNumBytes);
    
    AudioStreamPacketDescription * outPacketDescriptions = NULL;
    
    OSStatus status = noErr;
    
    if (_format.mFormatID != kAudioFormatLinearPCM) {
        
        UInt32 descriptionSize = sizeof(AudioStreamPacketDescription) * ioNumBytes;
        
        outPacketDescriptions = (AudioStreamPacketDescription *)malloc(descriptionSize);
        
        // 读取音频数据
/*
 读取音频数据的方法分为两类：
 1.直接读取音频数据：
 extern OSStatus AudioFileReadBytes (AudioFileID inAudioFile,
                                     Boolean inUseCache,
                                     SInt64 inStartingByte,
                                     UInt32 * ioNumBytes,
                                     void * outBuffer);
 第一个参数，fileID。
 第二个参数，是否需要cache，一般来说传false。
 第三个参数，从第几个byte开始读取数据。
 第四个参数，这个参数在调用时作为输入参数表示需要读取多少数据，调用完成后作为输出参数表示实际读取了多少数据（即read回调中的requestCount和actualCount）；
 第五个参数，buffer指针，需要事先分配足够大的内存空间（ioNumBytes大，即Read回调中的buffer，所以回调中不需要再分配内存）；
 返回值表示是否读取成功，EOF时会返回kAudioFileEndOfFileError
 
 使用这个方法得到的数据都是没有进行过帧分离的数据，如果想要用来播放或者解码还必须通过AudioFileStream进行帧分离；
 
 
 2.按帧（Packet）读取音频数据
 extern OSStatus AudioFileReadPacketData (AudioFileID inAudioFile,
                                          Boolean inUseCache,
                                          UInt32 * ioNumBytes,
                                          AudioStreamPacketDescription * outPacketDescriptions,
                                          SInt64 inStartingPacket,
                                          UInt32 * ioNumPackets,
                                          void * outBuffer);
 
 extern OSStatus AudioFileReadPackets (AudioFileID inAudioFile,
                                       Boolean inUseCache,
                                       UInt32 * outNumBytes,
                                       AudioStreamPacketDescription * outPacketDescriptions,
                                       SInt64 inStartingPacket,
                                       UInt32 * ioNumPackets,
                                       void * outBuffer);
 
 按帧读取的方法有两个，这两个方法看上去差不多，就连参数也几乎相同，但使用场景和效率上却有所不同，官方文档中如此描述这两个方法：
 AudioFileReadPacketData is memory efficient when reading variable bit-rate (VBR) audio data;
 AudioFileReadPacketData is more efficient than AudioFileReadPackets when reading compressed file formats that do not have packet tables, such as MP3 or ADTS. This function is a good choice for reading either CBR (constant bit-rate) or VBR data if you do not need to read a fixed duration of audio.
 Use AudioFileReadPackets only when you need to read a fixed duration of audio data, or when you are reading only uncompressed audio.
 只有当需要读取固定时长音频或者非压缩音频时才会用到AudioFileReadPackets，其余时候使用AudioFileReadPacketData会有更高的效率并且更省内存；
 下面来看看这些参数：
 第一、二个参数，同AudioFileReadBytes；
 第三个参数，对于AudioFileReadPacketData来说ioNumBytes这个参数在输入输出时都要用到，在输入时表示outBuffer的size，输出时表示实际读取了多少size的数据。而对AudioFileReadPackets来说outNumBytes只在输出时使用，表示实际读取了多少size的数据；
 第四个参数，帧信息数组指针，在输入前需要分配内存，大小必须足够存在ioNumPackets个帧信息（ioNumPackets * sizeof(AudioStreamPacketDescription)）；
 
 第五个参数，从第几帧开始读取数据；
 
 第六个参数，在输入时表示需要读取多少个帧，在输出时表示实际读取了多少帧；
 
 第七个参数，outBuffer数据指针，在输入前就需要分配好空间，这个参数看上去两个方法一样但其实并非如此。对于AudioFileReadPacketData来说只要分配近似帧大小 * 帧数的内存空间即可，方法本身会针对给定的内存空间大小来决定最后输出多少个帧，如果空间不够会适当减少出的帧数；而对于AudioFileReadPackets来说则需要分配最大帧大小(或帧大小上界) * 帧数的内存空间才行（最大帧大小和帧大小上界的区别等下会说）；这也就是为何第三个参数一个是输入输出双向使用的，而另一个只是输出时使用的原因。就这点来说两个方法中前者在使用的过程中要比后者更省内存；
 返回值，同AudioFileReadBytes；
 这两个方法读取后的数据为帧分离后的数据，可以直接用来播放或者解码。
 
 */
        status = AudioFileReadPacketData(_audioFileID, false, &ioNumBytes, outPacketDescriptions, _packetOffset, &ioNumPackets, outBuffer);
    }else
    {
        status = AudioFileReadPackets(_audioFileID, false, &ioNumBytes, outPacketDescriptions, _packetOffset, &ioNumPackets, outBuffer);
    }
    
    if (status != noErr) {
        *isEof = status == kAudioFileEndOfFileError;
        free(outBuffer);
        return nil;
    }
    if (ioNumBytes == 0) {
        *isEof = YES;
    }
    
    _packetOffset += ioNumBytes;
    
    if (ioNumPackets > 0) {
        NSMutableArray *parsedDataArray = [[NSMutableArray alloc] init];
        
        for (int i = 0; i < ioNumPackets; ++i) {
            
            AudioStreamPacketDescription packetDescription;
            
            if (outPacketDescriptions) {
                
                packetDescription = outPacketDescriptions[i];
                
            }else
            {
                packetDescription.mStartOffset = i * _format.mBytesPerPacket;
                packetDescription.mDataByteSize = _format.mBytesPerPacket;
                packetDescription.mVariableFramesInPacket = _format.mFramesPerPacket;
            }
            
            SJParsedAudioData *parsedData = [SJParsedAudioData parsedAudioDataWithBytes:outBuffer + packetDescription.mStartOffset packetDescription:packetDescription];
            
            if (parsedData) {
                [parsedDataArray addObject:parsedData];
            }
        }
        return parsedDataArray;
    }
    return nil;
}


- (void)seekToTime:(NSTimeInterval)time
{
    // 从第几帧开始读取音频数据
    _packetOffset = floor(time / _packetDurationn);
}



- (void)closeAudioFile
{
    if (self.available) {
        AudioFileClose(_audioFileID);
        _audioFileID = NULL;
    }
}

- (void)close
{
    [self closeAudioFile];
}

// 计算每个帧数据对应的时长
- (void)calculatePacketDuration
{
    if (_format.mSampleRate > 0) {
        _packetDurationn = _format.mFramesPerPacket / _format.mSampleRate;
    }
}

// 获取时长的最佳方法是从ID3信息中去读取，那样是最准确的。如果ID3信息中没有存，那就依赖于文件头中的信息去计算了。(音频数据的字节总量audioDataByteCount可以通过kAudioFileProperty_AudioDataByteCount获取,码率bitRate可以通过kAudioFileProperty_BitRate获取也可以通过Parse一部分数据后计算平均码率来得到。)
- (void)calculateDuration
{
    if (_fileSize > 0 && _bitRate > 0) {
        _duration = (_audioDataByteCount * 8.0) / _bitRate;
    }
}



#pragma -mark call back
/*
 下面来看一下AudioFile_GetSizeProc和AudioFile_ReadProc这两个读取功能相关的回调
 
 typedef OSStatus (*AudioFile_ReadProc)(void * inClientData,
                   SInt64 inPosition,
                   UInt32 requestCount,
                   void * buffer,
                   UInt32 * actualCount);
 
 第二个参数，需要读取第几个字节开始的数据；
 第三个参数，需要读取的数据长度；
 第四个参数，返回参数，是一个数据指针并且其空间已经被分配，我门需要做的是把数据memcpy到buffer中
 第五个参数，实际提供的数据长度，即memcpy到buffer中的数据长度。
 
 返回值，如果没有任何异常产生久返回noError。如果有异常可以根据异常类型选择需要的error常量返回（一般用不到其他返回值，返回noError就够了）；
 
 这里解释一下这个回调方法的工作方式。AudioFile需要数据时会调用回调方法，需要数据的时间点有2个：
 1.Open方法调用时，由于AudioFile的Open方法调用过程中就会对音频格式信息进行解析，只有符合要求的音频格式才能被成功打开否则Open方法就会返回错误码（换句话说，Open方法一旦调用成功就相当于AudioStreamFile在Parse后返回ReadyToProducePackets一样，只要Open成功就可以开始读取音频数据，详见第三篇），所以在Open方法调用的过程中就需要提供一部分音频数据来进行解析；
 2.Read相关方法调用时，通过回调提供数据时需要注意inPosition和requestCount参数，这两个参数指明了本次回调需要提供的数据范围是从inPosition开始requestCount个字节的数据。这里又可以分为两种情况：
 
 - (UInt32)availableDataLengthAtOffset:(SInt64)inPosition maxLength:(UInt32)requestCount
 
     有充足的数据：那么我们需要把这个范围内的数据拷贝到buffer中，并且给actualCount赋值requestCount，最后返回noError；
     数据不足：没有充足数据的话就只能把手头有的数据拷贝到buffer中，需要注意的是这部分被拷贝的数据必须是从inPosition开始的连续数据，拷贝完成后给actualCount赋值实际拷贝进buffer中的数据长度后返回noErr，这个过程可以用下面的代码来表示： 
 
 说到这里又需要分2种情况
 
 2.1. Open方法调用时的回调数据不足：AudioFile的Open方法会根据文件格式类型分几步进行数据读取以解析确定是否是一个合法的文件格式，其中每一步的inPosition和requestCount都不一样，如果某一步不成功就会直接进行下一步，如果几部下来都失败了，那么Open方法就会失败。简单的说就是在调用Open之前首先需要保证音频文件的格式信息完整，这就意味着AudioFile并不能独立用于音频流的读取，在流播放时首先需要使用AudioStreamFile来得到ReadyToProducePackets标志位来保证信息完整；
 
 2.2. Read方法调用时的回调数据不足：这种情况下inPosition和requestCount的数值与Read方法调用时传入的参数有关，数据不足对于Read方法本身没有影响，只要回调返回noErr，Read就成功，只是实际交给Read方法的调用方的数据会不足，那么就把这个问题的处理交给了Read的调用方；
 
*/
static OSStatus SJAudioFileReadCallBack(void *inClientData, SInt64 inPosition, UInt32 requestCount, void *buffer, UInt32 *actualCount)
{
    SJAudioFile *audioFile = (__bridge SJAudioFile *)(inClientData);
    
    *actualCount = [audioFile availableDataLengthAtOffset:inPosition maxLength:requestCount];
    
    if (*actualCount > 0) {
        NSData *data = [audioFile dataAtOffset:inPosition length:*actualCount];
        memcpy(buffer, [data bytes], [data length]);
    }
    
    return noErr;
}


- (UInt32)availableDataLengthAtOffset:(SInt64)inPosition maxLength:(UInt32)requestCount
{
    if ((inPosition + requestCount) > _fileSize) {
        
        if (inPosition > _fileSize) {
            return 0;
        }else
        {
            return (UInt32)(_fileSize - inPosition);
        }
    }else
    {
        return requestCount;
    }
}

- (NSData *)dataAtOffset:(SInt64)inPosition length:(UInt32)length
{
    [_fileHandler seekToFileOffset:inPosition];
    return [_fileHandler readDataOfLength:length];
}




static SInt64 SJAudioFileGetSizeCallBack(void *inClientData)
{
    SJAudioFile *audioFile = (__bridge SJAudioFile *)(inClientData);
    return audioFile.fileSize;
}

@end
