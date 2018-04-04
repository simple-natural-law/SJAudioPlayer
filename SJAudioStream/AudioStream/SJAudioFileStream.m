//
//  SJAudioFileStream.m
//  AudioStreamDemo
//
//  Created by zhangshijian on 15/12/14.
//  Copyright © 2015年 zhangshijian. All rights reserved.
//

#import "SJAudioFileStream.h"

#define BitRateEstimationMaxPackets 5000
#define BitRateEstimationMinPackets 50


@interface SJAudioFileStream ()
{
@private
    BOOL _discontinuous;
    
    AudioFileStreamID _audioFileStreamID;  // 文件流
    
    SInt64 _dataOffset;
    NSTimeInterval _packetDuration;
    
    UInt64 _processedPacketsCount;
    UInt64 _processedPacketsSizeTotal;
    
}

- (void)handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID;

- (void)handleAudioFileStreamPackets:(const void *)packets
                       numberOfBytes:(UInt32)numberOfBytes
                     numberOfPackets:(UInt32)numberOfPackets
                  packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions;

@end

#pragma -mark
// 在初始化完成之后，只要拿到文件数据就可以进行解析了。解析时调用方法：
/*
 extern OSStatus AudioFileStreamParseBytes(AudioFileStreamID inAudioFileStream,
                        UInt32 inDataByteSize,
                        const void* inData,
                        UInt32 inFlags);
 
 AudioFileStreamID: 初始化时返回的id
 inDataByteSize : 本次解析的数据长度
 inData : 本次解析的数据
 inFlags : 本次的解析和上一次的解析是否是连续的关系， 如果是连续的传入0， 否则传入
       kAudioFileStreamParseFlag_Discontinuity。
 
 何谓“连续” ：MP3的数据都以帧的形式存在的，解析时也需要以帧为单位解析。但在解码之前我们不可能知道每个帧的边界在第几个字节，所以就会出现这样的情况：我们传给AudioFileStreamParseBytes的数据在解析完成之后会有一部分数据余下来，这部分数据是接下去那一帧的前半部分，如果再次有数据输入需要继续解析时就必须要用到前一次解析余下来的数据才能保证帧数据完整，所以在正常播放的情况下传入0即可。目前知道的需要传入kAudioFileStreamParseFlag_Discontinuity的情况有两个，一个是在seek完毕之后显然seek后的数据和之前的数据完全无关；另一个是开源播放器AudioStreamer的作者@Matt Gallagher曾在自己的blog中提到过的：
 the Audio File Stream Services hit me with a nasty bug: AudioFileStreamParseBytes will crash when trying to parse a streaming MP3.
 In this case, if we pass the kAudioFileStreamParseFlag_Discontinuity flag to AudioFileStreamParseBytes on every invocation between receiving kAudioFileStreamProperty_ReadyToProducePackets and the first successful call to MyPacketsProc, then AudioFileStreamParseBytes will be extra cautious in its approach and won't crash.
 Matt发布这篇blog是在2008年，这个Bug年代相当久远了，而且原因未知，究竟是否修复也不得而知，而且由于环境不同（比如测试用的mp3文件和所处的iOS系统）无法重现这个问题，所以我个人觉得还是按照Matt的work around在回调得到kAudioFileStreamProperty_ReadyToProducePackets之后，在正常解析第一帧之前都传入kAudioFileStreamParseFlag_Discontinuity比较好。
 回到之前的内容，AudioFileStreamParseBytes方法的返回值表示当前的数据是否被正常解析，如果OSStatus的值不是noErr则表示解析不成功，其中错误码包括：
 enum
 {
  kAudioFileStreamError_UnsupportedFileType        = 'typ?',
  kAudioFileStreamError_UnsupportedDataFormat      = 'fmt?',
  kAudioFileStreamError_UnsupportedProperty        = 'pty?',
  kAudioFileStreamError_BadPropertySize            = '!siz',
  kAudioFileStreamError_NotOptimized               = 'optm',
  kAudioFileStreamError_InvalidPacketOffset        = 'pck?',
  kAudioFileStreamError_InvalidFile                = 'dta?',
  kAudioFileStreamError_ValueUnknown               = 'unk?',
  kAudioFileStreamError_DataUnavailable            = 'more',
  kAudioFileStreamError_IllegalOperation           = 'nope',
  kAudioFileStreamError_UnspecifiedError           = 'wht?',
  kAudioFileStreamError_DiscontinuityCantRecover   = 'dsc!'
 };
 
 注意AudioFileStreamParseBytes方法每一次调用都应该注意返回值，一旦出现错误就可以不必继续Parse了。
 
 在调用AudioFileStreamParseBytes方法进行解析时会首先读取格式信息，并同步的进入AudioFileStream_PropertyListenerProc回调方法
 */
static void SJAudioFileStreamPropertyListener(void *inClientData, AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags)
{
    SJAudioFileStream *audioFileStream = (__bridge SJAudioFileStream *)inClientData;
    [audioFileStream handleAudioFileStreamProperty:inPropertyID];
}


/*
 读取格式信息完成之后继续调用AudioFileStreamParseBytes方法可以对帧进行分离，并同步的进入AudioFileStream_PacketsProc回调方法。
 回调的定义:
 typedef void (*AudioFileStream_PacketsProc)(void * inClientData,
                        UInt32 inNumberBytes,
                        UInt32 inNumberPackets,
                        const void * inInputData,
                        AudioStreamPacketDescription * inPacketDescriptions);
 inNumberBytes :　本次处理的数据大小
 inNumberPackets　：　本次总共处理了多少帧（即代码里的ｐａｃｋｅｔ）
 inInputData : 本次处理的所有数据
 AudioStreamPacketDescription : 数组，存储了每一帧数据是从第几个字节开始的，这一帧总共多少字节。
 
 AudioStreamPacketDescription结构:
 这里的mVariableFramesInPacket是指实际的数据帧只有VBR的数据才能用到（像MP3这样的压缩数据一个帧里会有好几个数据帧）
 struct  AudioStreamPacketDescription
 {
  SInt64  mStartOffset;
  UInt32  mVariableFramesInPacket;
  UInt32  mDataByteSize;
 };
 
 */

static void SJAudioFileStreamPacketsCallBack(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescription)
{
    SJAudioFileStream *audioFileStream = (__bridge SJAudioFileStream *)inClientData;
    [audioFileStream handleAudioFileStreamPackets:inInputData numberOfBytes:inNumberBytes numberOfPackets:inNumberPackets packetDescriptions:inPacketDescription];
}

#pragma -mark
@implementation SJAudioFileStream

@synthesize fileType = _fileType;
@synthesize readyToProducePackets = _readyToProducePackets;
@dynamic available;
@synthesize duration = _duration;
@synthesize bitRate = _bitRate;
@synthesize format = _format;
@synthesize maxPacketSize = _maxPacketSize;
@synthesize audioDataByteCount = _audioDataByteCount;


#pragma -mark
- (instancetype)initWithFileType:(AudioFileTypeID)fileType fileSize:(unsigned long long)fileSize error:(NSError **)error
{
    self = [super init];
    if (self) {
        _discontinuous = NO;
        _fileType = fileType;
        _fileSize = fileSize;
        [self openAudioFileStreamWithFileTypeHint:_fileType error:error];
    }
    return self;
}

- (void)dealloc
{
    [self closeAudioFlieStream];
}

- (void)errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError
{
    if (status != noErr && outError != NULL)
    {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
}

#pragma -mark open & close
- (BOOL)openAudioFileStreamWithFileTypeHint:(AudioFileTypeID)fileTypeHint error:(NSError *__autoreleasing *)error
{
    //第一步，自然是要生成一个AudioFileStream的实例：
    
    // 用来读取采样率、码率、时长等基本信息以及分离音频帧。
    // 根据Apple的描述AudioFileStreamer用在流播放中，当然不仅限于网络流，本地文件同样可以用它来读取信息和分离音频帧。AudioFileStreamer的主要数据是文件数据而不是文件路径，所以数据的读取需要使用者自行实现，
    /*
     支持的文件格式有：
     MPEG-1 Audio Layer 3, used for .mp3 files
     MPEG-2 ADTS, used for the .aac audio data format
     AIFC
     AIFF
     CAF
     MPEG-4, used for .m4a, .mp4, and .3gp files
     NeXT
     WAVE
     上述格式是iOS、MacOSX所支持的音频格式，这类格式可以被系统提供的API解码，如果想要解码其他的音频格式（如OGG、APE、FLAC）就需要自己实现解码器了。
    */
    
    // 和之前的AudioSession的初始化方法一样是一个上下文对象
    
    /*
     extern OSStatus AudioFileStreamOpen (void * inClientData,
                          AudioFileStream_PropertyListenerProc inPropertyListenerProc,
                          AudioFileStream_PacketsProc inPacketsProc,
                          AudioFileTypeID inFileTypeHint,
                          AudioFileStreamID * outAudioFileStream);
     
     第一个参数和之前的AudioSession的初始化方法一样是一个上下文对象；
     第二个参数AudioFileStream_PropertyListenerProc是歌曲信息解析的回调，每解析出一个歌曲信息都会进行一次回调；
     第三个参数AudioFileStream_PacketsProc是分离帧的回调，每解析出一部分帧就会进行一次回调；
     第四个参数AudioFileTypeID是文件类型的提示，这个参数来帮助AudioFileStream对文件格式进行解析。这个参数在文件信息不完整（例如信息有缺陷）时尤其有用，它可以给与AudioFileStream一定的提示，帮助其绕过文件中的错误或者缺失从而成功解析文件。所以在确定文件类型的情况下建议各位还是填上这个参数，如果无法确定可以传入0.
     第五个参数是返回的AudioFileStream实例对应的AudioFileStreamID，这个ID需要保存起来作为后续一些方法的参数使用；
     
     返回值用来判断是否成功初始化（OSStatus == noErr）。
     */
    OSStatus status = AudioFileStreamOpen((__bridge void * _Nullable)(self), SJAudioFileStreamPropertyListener, SJAudioFileStreamPacketsCallBack, fileTypeHint, &_audioFileStreamID);
    
    if (status != noErr) {
        _audioFileStreamID = NULL;
    }
    
    [self errorForOSStatus:status error:error];
    return status == noErr;
}

// 关闭AudioFileStream
- (void)closeAudioFlieStream
{
    if (self.available) {
        AudioFileStreamClose(_audioFileStreamID);
        _audioFileStreamID = NULL;
    }
}


- (void)close
{
    [self closeAudioFlieStream];
}


- (BOOL)available
{
    return _audioFileStreamID != NULL;
}

#pragma -mark
- (void)handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID
{
    // AudioFileStreamPropertyID （对 AudioFileStream常量 获取某个属性时调用）
    
    // 一旦解析到音频数据的开头，流的所有属性就是已知的了
    if (propertyID == kAudioFileStreamProperty_ReadyToProducePackets) {
        _readyToProducePackets = YES;
        _discontinuous = YES;
        
        UInt32 sizeOfUInt32 = sizeof(_maxPacketSize);
        
        /*
        extern OSStatus
        AudioFileStreamGetProperty(
                                   AudioFileStreamID					inAudioFileStream,
                                   AudioFileStreamPropertyID			inPropertyID,
                                   UInt32 *							ioPropertyDataSize,
                                   void *								outPropertyData)
         该方法用来获取某个属性对应的数据。
         第一个参数为：文件流ID
         第二个参数为：属性
         
         CF_ENUM(AudioFileStreamPropertyID)
         {
         kAudioFileStreamProperty_ReadyToProducePackets			=	'redy',
         kAudioFileStreamProperty_FileFormat						=	'ffmt',
         kAudioFileStreamProperty_DataFormat						=	'dfmt',
         kAudioFileStreamProperty_FormatList						=	'flst',
         kAudioFileStreamProperty_MagicCookieData				=	'mgic',
         kAudioFileStreamProperty_AudioDataByteCount				=	'bcnt',
         kAudioFileStreamProperty_AudioDataPacketCount			=	'pcnt',
         kAudioFileStreamProperty_MaximumPacketSize				=	'psze',
         kAudioFileStreamProperty_DataOffset						=	'doff',
         kAudioFileStreamProperty_ChannelLayout					=	'cmap',
         kAudioFileStreamProperty_PacketToFrame					=	'pkfr',
         kAudioFileStreamProperty_FrameToPacket					=	'frpk',
         kAudioFileStreamProperty_PacketToByte					=	'pkby',
         kAudioFileStreamProperty_ByteToPacket					=	'bypk',
         kAudioFileStreamProperty_PacketTableInfo				=	'pnfo',
         kAudioFileStreamProperty_PacketSizeUpperBound  			=	'pkub',
         kAudioFileStreamProperty_AverageBytesPerPacket			=	'abpp',
         kAudioFileStreamProperty_BitRate						=	'brat',
         kAudioFileStreamProperty_InfoDictionary                 =   'info'
         };
         
         第三个参数
         第四个参数
        */
        
        // kAudioFileStreamProperty_PacketSizeUpperBound (文件中理论上最大数据包的大小)
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &_maxPacketSize);
        
        // 如果获取属性失败 或者 最大数据包的大小为0
        if (status != noErr || _maxPacketSize == 0) {
            // kAudioFileStreamProperty_MaximumPacketSize (文件中包含的数据包的最大尺寸)
            status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &_maxPacketSize);
            
            if (status != noErr || _maxPacketSize == 0) {
                
                _maxPacketSize = kDefaultBufferSize;
            }
            
        }
        
        // 执行代理
        if (_delegate && [_delegate respondsToSelector:@selector(audioFileStreamReadyToProducePackets:)]) {
            [_delegate audioFileStreamReadyToProducePackets:self];
        }
        
    }// kAudioFileStreamProperty_DataOffset(表示音频数据在整个音频文件中的offset（因为大多数音频文件都会有一个文件头之后才使真正的音频数据），这个值在seek时会发挥比较大的作用，音频的seek并不是直接seek文件位置而seek时间（比如seek到2分10秒的位置），seek时会根据时间计算出音频数据的字节offset然后需要再加上音频数据的offset才能得到在文件中的真正offset。 SInt64)
    else if (propertyID == kAudioFileStreamProperty_DataOffset)
    {
        UInt32 offsetSize = sizeof(_dataOffset);
        AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataOffset, &offsetSize, &_dataOffset);
        _audioDataByteCount = _fileSize - _dataOffset;
        
        // 计算音频持续时长
        [self calculateDuration];
    }// kAudioFileStreamProperty_DataFormat (AudioStreamBasicDescription类 用来描述音频数据的格式)
    else if (propertyID == kAudioFileStreamProperty_DataFormat)
    {
        UInt32 asbdSize = sizeof(_format);
        AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataFormat, &asbdSize, &_format);
        // 计算数据包间隔时长
        [self calculatePacketDuration];
    }// kAudioFileStreamProperty_FormatList (为了支持包括AAC SBR格式编码的数据流可以被解码到多个目的地的格式，此属性返回包含这些格式的AudioFormatListItems数组（见AudioFormat.h）。默认行为是与kAudioFileStreamProperty_DataFormat属性返回相同的AudioStreamBasicDescription的一个AudioFormatListItem。)
    else if (propertyID == kAudioFileStreamProperty_FormatList)
    {
        /*
        extern OSStatus
        AudioFileStreamGetPropertyInfo(
                                       AudioFileStreamID				inAudioFileStream,
                                       AudioFileStreamPropertyID		inPropertyID,
                                       UInt32 * __nullable				outPropertyDataSize,
                                       Boolean * __nullable			outWritable)
         该方法用来获取某个属性对应的数据的大小(outDataSize)以及该属性是否可以被write（isWriteable） 
         AudioFileStreamGetProperty 用来获取属性对应的数据.
         对于一些大小可变的属性需要先使用 AudioFileStreamGetPropertyInfo 获取数据大小 才能获取数据(例如formatList)，而有些确定类型单个属性则不必先调用AudioFileGetPropertyInfo直接调用AudioFileGetProperty即可（比如BitRate）
        */
        Boolean outWriteable;
        UInt32 formatListSize;
        OSStatus status = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, &outWriteable);
        if (status == noErr) {
            // 获取formatlist
            AudioFormatListItem *formatlist = malloc(formatListSize);
            OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, formatlist);
            if (status == noErr) {
                
                UInt32 supportedFormatsSize;
                status = AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize);
                if (status != noErr) {
                    // 错误处理
                    free(formatlist);
                    return;
                }
                
                UInt32 supportedFormatCount = supportedFormatsSize / sizeof(OSType);
                OSType *supportedFormats = (OSType *)malloc(supportedFormatsSize);
                status = AudioFormatGetProperty(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatCount, supportedFormats);
                
                if (status != noErr) {
                    // 错误处理
                    free(formatlist);
                    free(supportedFormats);
                    return;
                }
                
                // 选择需要的格式
                for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i += sizeof(AudioFormatListItem)) {
                    AudioStreamBasicDescription format = formatlist[i].mASBD;
                    for (UInt32 j = 0; j < supportedFormatCount; ++j) {
                        
                        if (format.mFormatID == supportedFormats[j]) {
                            
                            _format = format;
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
}

- (void)handleAudioFileStreamPackets:(const void *)packets
                       numberOfBytes:(UInt32)numberOfBytes
                     numberOfPackets:(UInt32)numberOfPackets
                  packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions
{
    if (_discontinuous) {
        _discontinuous = NO;
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
        
        if (_processedPacketsCount < BitRateEstimationMaxPackets) {
            _processedPacketsSizeTotal += parsedData.packetDescription.mDataByteSize;
            _processedPacketsCount += 1;
            [self calculateBitRate];
            [self calculateDuration];
        }
        
    }
    
    [_delegate audioFileStream:self audioDataParsed:parsedDataArray];
    
    if (deletePackDesc)
    {
        free(packetDescriptions);
    }
}

#pragma -mark
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
    OSStatus status = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if (status != noErr) {
        return nil;
    }
    
    void *cookieData = malloc(cookieSize);
    status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if (status != noErr) {
        return nil;
    }
    NSData *cookie = [NSData dataWithBytes:cookieData length:cookieSize];
    free(cookieData);
    return cookie;
}

- (BOOL)parseData:(NSData *)data error:(NSError **)error
{
    
    if (self.readyToProducePackets && _packetDuration == 0) {
        [self errorForOSStatus:-1 error:error];
        return NO;
    }
    OSStatus status = AudioFileStreamParseBytes(_audioFileStreamID, (UInt32)[data length], [data bytes], _discontinuous ? kAudioFileStreamParseFlag_Discontinuity : 0);
    [self errorForOSStatus:status error:error];
    return status == noErr;
}

/*
 seek : 拖动到xx分xx秒，而实际操作时我们需要操作的是文件，就是要从第几个字节开始读取音频数据。对于原始的PCM数据来说，每一个PCM帧都是固定长度的，对应的播放时长也是固定的。但一旦转换成压缩后的音频数据就会因为编码形式的不同而不同了，对于CBR（固定码率）而言每个帧中所包含的PCM数据帧是恒定的，所以每一帧对应的播放时长也是恒定的；而VBR（可变码率）则不同，为了保证数据最优并且文件大小最小，VBR的每一帧中所包含的PCM数据帧是不固定对，这就导致在流播放的情况下VBR的数据想要做seek并不容易。这里只讨论CBR下的seek
 
 double seekToTime ＝ ...; // 需要seek到哪个时间，秒为单位
 Uint64 audioDataByteCount = ...; // 通过kAudioFileStreamProperty_AudioDataByteCount获取的值
 Sint64 dataOffset = ...; // 通过kAudioFileStreamProperty_DataOffset获取的值
 double duration = ...; // 通过公式(AudioDataByteCount * 8) / BitRate 计算得到时长
 
 按照seekByteOffset读取对应的数据继续使用 AudioFileStreamParseByte 方法来进行解析
 如果是网络流可以通过设置range头来获取字节，本地文件的话直接seek就好。 ⚠ 调用 AudioFileStreamParseByte 方法时注意刚seek完第一次parse数据需要加参数 kAudioFileStreamParseFlag_Discontinuity。
 
 */
- (SInt64)seekToTime:(NSTimeInterval *)time
{
    // 近似seekOffset = 数据偏移 + seekToTime对应的近似字节数
    SInt64 approximateSeekoffset = _dataOffset + (*time / _duration) * _audioDataByteCount;
    
    // floor() 向下取整  计算packet位置
    SInt64 seekToPacket = floor(*time / _packetDuration);
    SInt64 seekByteOffset;
    UInt32 ioFlags = 0;
    SInt64 outDataByteOffset;
    /*
     使用AudioStreamSeek计算精确的字节偏移和时间
     AudioStreamSeek 可以用来寻找某一个帧（packet）对应的字节偏移（byte offset）：如果ioFlags里有kAudioFileStreamFlag_OffsetIsEstimated 说明给出的outDataByteOffset是估算的，并不准确，那么还是应该用第一步计算出来的approximateSeekOffset来做seek； 如果ioFlags里没有 kAudioFileStreamFlag_OffsetIsEstimated 说明给出了准确的outDataByteOffset， 就是输入的seekToPacket对应的字节偏移量，可以根据outDataByteOffset来计算出精确的seekOffset 和 seekToTime；
     */
    OSStatus status = AudioFileStreamSeek(_audioFileStreamID, seekToPacket, &outDataByteOffset, &ioFlags);
    if (status == noErr && !(ioFlags & kAudioFileStreamSeekFlag_OffsetIsEstimated))
    {
        // 如果AudioFileStreamSeek方法找到了准确的帧字节偏移，就需要修正一下时间
        *time -= ((approximateSeekoffset - _dataOffset) - outDataByteOffset) * 8.0 / _bitRate;
        
        seekByteOffset = outDataByteOffset + _dataOffset;
    }else
    {
        _discontinuous = YES;
        seekByteOffset = approximateSeekoffset;
    }
    return seekByteOffset;
}



#pragma -mark
// 计算码率
- (void)calculateBitRate
{
    if (_packetDuration && _processedPacketsCount > BitRateEstimationMinPackets && _processedPacketsCount <= BitRateEstimationMaxPackets)
    {
        double averagePacketByteSize = _processedPacketsSizeTotal / _processedPacketsCount;
        _bitRate = 8.0 * averagePacketByteSize / _packetDuration;
    }

}

// 获取时长的最佳方法是从ID3信息中去读取，那样是最准确的。如果ID3信息中没有存，那就依赖于文件头中的信息去计算了。(音频数据的字节总量audioDataByteCount可以通过kAudioFileStreamProperty_AudioDataByteCount获取，码率bitRate可以通过kAudioFileStreamProperty_BitRate获取也可以通过Parse一部分数据后计算平均码率来得到。)
- (void)calculateDuration
{
    if (_fileSize > 0 && _bitRate > 0) {
        _duration = (_audioDataByteCount * 8.0) / _bitRate;
    }
}


// 利用之前parse得到的音频格式信息来计算PacketDuration。（每个帧数据对应的时长）
- (void)calculatePacketDuration
{
    if (_format.mSampleRate > 0) {
        _packetDuration = _format.mFramesPerPacket / _format.mSampleRate;
    }
}



@end
