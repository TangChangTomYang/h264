//
//  ViewController.m
//  H264Demo
//
//  Created by yangrui on 2017/12/26.
//  Copyright © 2017年 yangrui. All rights reserved.
//

#import "ViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>

@interface ViewController ()<AVCaptureAudioDataOutputSampleBufferDelegate>


@property(nonatomic, strong)UILabel *cLabel;

@property(nonatomic, strong)AVCaptureSession *cCaptureSession;
@property(nonatomic, strong)AVCaptureDeviceInput *cCaptureDeviceInput;
@property(nonatomic, strong)AVCaptureVideoDataOutput *cCaptureDataOutout;
/** 展示摄像头的内容 */
@property(nonatomic, strong)AVCaptureVideoPreviewLayer *cPreviewLayer;



@end

@implementation ViewController{

    int _frameID;// 每一帧图像都有一个ID
    dispatch_queue_t _cCaptureQueue;//捕捉队列
    dispatch_queue_t _cEncodeQueue;// 编码队列
    VTCompressionSessionRef _cEncodingSession; //编码会话
    CMFormatDescriptionRef _format; // 编码格式
    NSFileManager *_fileMgr; // 文件操作
    
    
    NSFileHandle *_fileHandle;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
     NSString *path = @"";
    _fileHandle = [NSFileHandle  fileHandleForWritingAtPath:path];
    
    
    
    _cLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 200, 100)];
    _cLabel.text = @"H264编码demo";
    _cLabel.textColor = [UIColor redColor];
    [self.view addSubview:_cLabel];
    
    
    UIButton *cBtn = [[UIButton alloc] initWithFrame:CGRectMake(200, 20, 200, 100)];
    [cBtn setTitle:@"play" forState:UIControlStateNormal];
    [cBtn setTitleColor:[UIColor whiteColor]  forState:UIControlStateNormal];
    [cBtn setBackgroundColor:[UIColor orangeColor]];
    [cBtn addTarget:self action:@selector(cBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cBtn];
    
}

-(void)cBtnClick:(UIButton *)btn{
    
    
    if (self.cCaptureSession == nil || self.cCaptureSession.isRunning == NO) {
        
        [btn setTitle:@"Stop" forState:UIControlStateNormal];
        
        [self startCapture];
        
    }
    else {
        [btn setTitle:@"play" forState:UIControlStateNormal];
        [self stopCapture];
    
    }

}


/** 开始捕捉 */
-(void)startCapture{
    //1. 创建会话
    self.cCaptureSession = [[AVCaptureSession alloc] init];
    
    // 2. 设置会话的分辨率
    self.cCaptureSession.sessionPreset = AVCaptureSessionPreset640x480;
    
    // 子队列
    _cCaptureQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _cEncodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    
    
    // 3.获取当前所有的摄像头设备,并从中找到前摄
    AVCaptureDevice *inputCamera = nil;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *dev in devices) {
        
        // 拿到前置摄像头
        if ([dev position] == AVCaptureDevicePositionFront) {
            inputCamera = dev;
            break;
        }
    }

    //4. 设置捕捉设备的 设备输入(从前摄输入)
    self.cCaptureDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:inputCamera error:nil];


    //5.添加 输入到会话当中
    if ([self.cCaptureSession canAddInput:self.cCaptureDeviceInput]) {
        
        [self.cCaptureSession addInput:self.cCaptureDeviceInput];
    }

    // 添加输出(设置输出)
    self.cCaptureDataOutout = [[AVCaptureVideoDataOutput alloc] init];
    [self.cCaptureDataOutout setAlwaysDiscardsLateVideoFrames:NO];
    [self.cCaptureDataOutout setVideoSettings: @{(id)kCVPixelBufferPixelFormatTypeKey :@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) }];
    // 设置输出代理 ()
    [self.cCaptureDataOutout setSampleBufferDelegate:self queue:_cCaptureQueue];
    
    if ([self.cCaptureSession canAddOutput:self.cCaptureDataOutout]) {
        [self.cCaptureSession addOutput:self.cCaptureDataOutout];
    }
    
    AVCaptureConnection *connection = [self.cCaptureDataOutout connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    self.cPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.cCaptureSession];
    [self.cPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    [self.cPreviewLayer setFrame:self.view.bounds];
    [self.view.layer addSublayer:self.cPreviewLayer];
    
    
    NSString *filePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/YR_video.h264"];
    
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    BOOL createFile = [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];

    if(!createFile){
        NSLog(@"创建文件失败");
    }
    else{
        NSLog(@"创建文件 成功");
    }
    
    NSLog(@"filePath : %@",filePath);
    
    
    // 初始化videoToolBox
    [self initVideoToolBox];
    
    //开始捕捉
    [self.cCaptureSession startRunning];
    
}

-(void)initVideoToolBox{
    
    dispatch_sync(_cEncodeQueue, ^{
        
        _frameID = 0;// 帧ID,每一帧都有一个ID 
        int width = 480, height = 640;
        // 创建一个压缩视频帧的会话
        // 宽度以像素为单位,当宽高不合理,系统会自动改变你的宽高
       OSStatus status = VTCompressionSessionCreate(NULL,
                                                    width,
                                                    height,
                                                    kCMVideoCodecType_H264,
                                                    NULL,
                                                    NULL,
                                                    NULL,
                                                    VTDidCompressionOutputCallback,//回调函数
                                                    (__bridge void *)self,
                                                    &_cEncodingSession);
        
        
        
        NSLog(@"H264 VTComPressionSessionCreate: %d", (int)status);
        
        if (status != 0) {
            NSLog(@"H264 不能创建 H264 session");
            return ;
        }
        
        // 设置实时编码输出 (设置参数都是用这个方法)
        VTSessionSetProperty(_cEncodingSession, //编码的会话
                             kVTCompressionPropertyKey_RealTime,// 编码属性的key (实时编码)
                             kCFBooleanTrue);// 属性的值
        VTSessionSetProperty(_cEncodingSession,
                             kVTCompressionPropertyKey_ProfileLevel,//编码的水平
                             kVTProfileLevel_H264_Baseline_AutoLevel);// 自动level
        
        
        // 设置关键帧(GOPSize)间隔,GOP太小图像模糊(应为共同数据太少),一遍情况下设置10
        int frameInterval = 10;
        CFNumberRef frameIntervalRef = CFNumberCreate(kCFAllocatorDefault,  kCFNumberIntType,&frameInterval);
        VTSessionSetProperty(_cEncodingSession,
                             kVTCompressionPropertyKey_MaxKeyFrameInterval,// 关键帧间隔
                             frameIntervalRef);
        
        
        // 设置期望帧率(不是实际帧率)
        int fps = 10;
        CFNumberRef fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
        VTSessionSetProperty(_cEncodingSession,
                             kVTCompressionPropertyKey_ExpectedFrameRate,
                             fpsRef);
        
       
        // 设置码率\ 上限 \单位是bps
        int bitRate = width * height * 3 * 4 * 8;
        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
        VTSessionSetProperty(_cEncodingSession,
                             kVTCompressionPropertyKey_AverageBitRate,// 解码的速率,码率越高越清晰,文件越大
                             bitRateRef);
        
        
        // 设置码率\ 均值 \单位是byte(极高码率)
        int bigRateLimit = width * height * 3 * 4 ;
        CFNumberRef bigRateLimitf = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bigRateLimit);
        VTSessionSetProperty(_cEncodingSession,
                             kVTCompressionPropertyKey_DataRateLimits,//
                             bigRateLimitf);
        
        
        // 开始(准备   )编码
        /** 将我们的编码参数放大编码器中,(准备编码) */
        VTCompressionSessionPrepareToEncodeFrames(_cEncodingSession);
        
        
    });
    
}
#pragma mark- AVCaptureAudioDataOutputSampleBufferDelegate
/** 捕捉到媒体数据(音频\视频) */
- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection{
    
    
    /** 如何区分是音频还是视频, 在AAC 编码会将 */
    
    dispatch_sync(_cEncodeQueue, ^{
        [self encode:sampleBuffer];
    });
    
}

/** 编码前CMSampleBuffer
 CMTime             // 时间戳
 CMVideoFormatDesc  // 图像存储格式
 CVPixelBuffer      //编码前或者解码后数据
 */


/** 编码后CMSampleBuffer
 CMTime             // 时间戳
 CMVideoFormatDesc  // 图像存储格式
 CMBlockBuffer      // 编码后数据
 */
//编码
-(void)encode:(CMSampleBufferRef)sampleBuffer{
    
    //1. 拿到每一帧未编码的数据(其实我们的数据就是一帧一帧图片组成的)
    CVImageBufferRef imageBufferRef  = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    
    //2. 设置每一帧的时间
   CMTime presentionTimeStamp = CMTimeMake(_frameID++, 1000);  // CMTime 是一个影片时间, 1000 表示1秒被划分成了多少个单位,_frameID++ 表示的是当前有多少个划分的时间单位
    
    //3.标记 同步编码0, 异步编码其他
    VTEncodeInfoFlags flag =  0;
    ;
    
    //编码
    OSStatus status = VTCompressionSessionEncodeFrame(_cEncodingSession, // 编码的会话
                                    imageBufferRef,                      // 编码数据,这里是图片数据
                                    presentionTimeStamp,                 // 编码的帧时间(编码时间轴)
                                    kCMTimeInvalid,                      // 编码的帧的时间展示
                                    NULL,                                // 帧的属性
                                    NULL,                                // 帧的参考值
                                    &flag);                              // 标记是同步还是异步编码
    
    
    if(status != noErr){// 不成功
        // 释放资源
        VTCompressionSessionInvalidate(_cEncodingSession);
        CFRelease(_cEncodingSession);
        _cEncodingSession = NULL;
    }
    
    
    //编码成功,不代表所有的数据都编码完成,只代表当前的数据编码成功
    
    
}


#pragma mark- 函数回调 (编码完成回调)
/** 压缩文件输出回调函数 (编码完成回调)*/
/**
 SPS:序列参数集合(Sequence Parameter Sets)
 PPS:图像参数集合(Picture Parameter Sets) */
void VTDidCompressionOutputCallback(void * CM_NULLABLE outputCallbackRefCon,
                                    void * CM_NULLABLE sourceFrameRefCon,
                                    OSStatus status,
                                    VTEncodeInfoFlags infoFlags,
                                    CM_NULLABLE CMSampleBufferRef sampleBuffer ){
    
    if(status != 0){
        return;
    }
 
    if(! CMSampleBufferDataIsReady(sampleBuffer)){
        return;
    }
    
    // 将编码完成的数据(散的数据) 形成H264文件
    
    ViewController *encoder = (__bridge ViewController *)outputCallbackRefCon;
//    UIViewController *encoder = (__bridge UIViewController *)outputCallbackRefCon;
    
    
    //判断是否为关键帧
    CFArrayRef achmentsArrayref = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    CFDictionaryRef achmentsDicRef = CFArrayGetValueAtIndex(achmentsArrayref, 0);
    bool isKeyFrame = CFDictionaryContainsKey(achmentsDicRef, kCMSampleAttachmentKey_NotSync);
    
    if (isKeyFrame) {
        //图象存储方式
        CMFormatDescriptionRef formatRef =  CMSampleBufferGetFormatDescription(sampleBuffer);
        
        // sps
        size_t  spsParameterSetSize , spsParamererSetCount;
        const uint8_t *spsParameterSet;
        OSStatus spsStatuscode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatRef,             //图象序列格式
                                                                                 1,                     //
                                                                                 &spsParameterSet,         //
                                                                                 &spsParameterSetSize,     //
                                                                                 &spsParamererSetCount,    //
                                                                                 0);                    //
        
        if(spsStatuscode == noErr){ // 获取sps 成功
            // pps(图象序列集合)
            size_t  ppsParameterSetSize , ppsParamererSetCount;
            const uint8_t *ppsParameterSet;
            OSStatus ppsStatuscode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatRef,             //图象序列格式
                                                                                     1,                     //
                                                                                     &ppsParameterSet,         //
                                                                                     &ppsParameterSetSize,     //
                                                                                     &ppsParamererSetCount,    //
                                                                                     0);                    //
            if (ppsStatuscode == noErr) {// 获取pps 成功
                // 将sps 和pps 写入文件
                NSData *spsData = [NSData dataWithBytes:spsParameterSet length:spsParameterSetSize];
                NSData *ppsData = [NSData dataWithBytes:ppsParameterSet length:ppsParameterSetSize];
            
                if (encoder) {
                    
                    [encoder gotSpsData:spsData ppsData:ppsData];
                }
            
            }
            
            
            
        }
    }
    
    //取其他数据
    CMBlockBufferRef dataBufferRef  = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length , totalLength;
    char *dataPointer;
    OSStatus  getDataPointerStatus = CMBlockBufferGetDataPointer(dataBufferRef, 0, &length, &totalLength, &dataPointer);
    
    if (getDataPointerStatus == noErr) {// 成功
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;
        
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            uint32_t NALUnitLength = 0;
            
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength); // 大端 小端模式的装换
            NSData *data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            [encoder gotEncodedData:data isKeyFrame:YES];
        }
        
    }
    
    
}

//
-(void)gotSpsData:(NSData *)spsData ppsData:(NSData *)ppsData{
    const char bytes[] = "\x00\x00\x00\x01"; // 前面几个数据都是固定的 00 00 00 01
    size_t length = sizeof(bytes) -1 ; // 为什么长度要减一,因为C语言字符串最后一个字符是结尾字符 \0,因此要减去
    NSData *byteHeader = [[NSData alloc] initWithBytes:bytes length:length]; // 将固定的头bytes 转换成data
   
   
    
    // 不论是sps 还是pps还是其他数据在最前面都有一个 头数据 00 00 00 01
    [_fileHandle writeData:byteHeader];
    [_fileHandle writeData:spsData];
    
    [_fileHandle writeData:byteHeader];
    [_fileHandle writeData:ppsData];
    
    
}

//
-(void)gotEncodedData:(NSData *)data isKeyFrame:(BOOL)iskeyFrame{
    
    const char bytes[] = "\x00\x00\x00\x01"; // 前面几个数据都是固定的 00 00 00 01
    size_t length = sizeof(bytes) -1 ; // 为什么长度要减一,因为C语言字符串最后一个字符是结尾字符 \0,因此要减去
    NSData *byteHeader = [[NSData alloc] initWithBytes:bytes length:length]; // 将固定的头bytes 转换成data
    
    
    
    // 不论是sps 还是pps还是其他数据在最前面都有一个 头数据 00 00 00 01
    [_fileHandle writeData:byteHeader];
    [_fileHandle writeData:data];
    
}

/** 停止捕捉 */
-(void)stopCapture{
    
}



/** H264解码的方式
 1. openGL ES
 2. AVSampleBufferDisplayer
 3. FFmpeg
 4. videoToolBox 硬解码
 */

/** 编码一般用硬编码,解码一般用软解码 */









































@end
