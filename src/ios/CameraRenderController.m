#import "CameraRenderController.h"
#import <CoreVideo/CVOpenGLESTextureCache.h>
#import <GLKit/GLKit.h>
#import <OpenGLES/ES2/glext.h>

@import MLKit;

@interface CameraRenderController()
@property(nonatomic, strong) MLKBarcodeScanner *barcodeDetector;
@end

@implementation CameraRenderController
@synthesize context = _context;
@synthesize delegate;

- (CameraRenderController *)init {
  if (self = [super init]) {
    self.renderLock = [[NSLock alloc] init];
  }

  //Parse Cordova settings.
  NSNumber *formats = 0;
  formats = _barcodeFormats;

  // Initialize barcode detector.
  // FIRVisionBarcodeDetectorOptions *options = [[FIRVisionBarcodeDetectorOptions alloc] initWithFormats: [formats intValue]];
  // FIRVision *vision = [FIRVision vision];
  // self.barcodeDetector = [vision barcodeDetectorWithOptions:options];

  // Define the options for a barcode detector.
  // [START config_barcode]
  MLKBarcodeFormat format = MLKBarcodeFormatAll;
  MLKBarcodeScannerOptions *barcodeOptions =
      [[MLKBarcodeScannerOptions alloc] initWithFormats:format];
  // [END config_barcode]

  // Create a barcode detector.
  // [START init_barcode]
  self.barcodeDetector = [MLKBarcodeScanner barcodeScannerWithOptions:barcodeOptions];
  // [END init_barcode]

  return self;
}

- (void)loadView {
  GLKView *glkView = [[GLKView alloc] init];
  [glkView setBackgroundColor:[UIColor blackColor]];
  [self setView:glkView];
}

- (void)viewDidLoad {
  [super viewDidLoad];

  self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

  if (!self.context) {
    NSLog(@"Failed to create ES context");
  }

  CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, self.context, NULL, &_videoTextureCache);
  if (err) {
    NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
    return;
  }

  GLKView *view = (GLKView *)self.view;
  view.context = self.context;
  view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
  view.contentMode = UIViewContentModeScaleToFill;

  glGenRenderbuffers(1, &_renderBuffer);
  glBindRenderbuffer(GL_RENDERBUFFER, _renderBuffer);

  self.ciContext = [CIContext contextWithEAGLContext:self.context];

  if (self.dragEnabled) {
    //add drag action listener
    NSLog(@"Enabling view dragging");
    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.view addGestureRecognizer:drag];
  }

  if (self.tapToFocus && self.tapToTakePicture){
    //tap to focus and take picture
    UITapGestureRecognizer *tapToFocusAndTakePicture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector (handleFocusAndTakePictureTap:)];
    [self.view addGestureRecognizer:tapToFocusAndTakePicture];

  } else if (self.tapToFocus){
    // tap to focus
    UITapGestureRecognizer *tapToFocusGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector (handleFocusTap:)];
    [self.view addGestureRecognizer:tapToFocusGesture];

  } else if (self.tapToTakePicture) {
    //tap to take picture
    UITapGestureRecognizer *takePictureTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTakePictureTap:)];
    [self.view addGestureRecognizer:takePictureTap];
  }

  self.view.userInteractionEnabled = self.dragEnabled || self.tapToTakePicture || self.tapToFocus;
}

- (void) viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(appplicationIsActive:)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(applicationEnteredForeground:)
                                               name:UIApplicationWillEnterForegroundNotification
                                             object:nil];

  dispatch_async(self.sessionManager.sessionQueue, ^{
      NSLog(@"Starting session");
      [self.sessionManager.session startRunning];
      });
}

- (void) viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];

  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:UIApplicationDidBecomeActiveNotification
                                                object:nil];

  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:UIApplicationWillEnterForegroundNotification
                                                object:nil];

  dispatch_async(self.sessionManager.sessionQueue, ^{
      NSLog(@"Stopping session");
      [self.sessionManager.session stopRunning];
      });
}

- (void) handleFocusAndTakePictureTap:(UITapGestureRecognizer*)recognizer {
  NSLog(@"handleFocusAndTakePictureTap");

  // let the delegate take an image, the next time the image is in focus.
  [self.delegate invokeTakePictureOnFocus];

  // let the delegate focus on the tapped point.
  [self handleFocusTap:recognizer];
}

- (void) handleTakePictureTap:(UITapGestureRecognizer*)recognizer {
  NSLog(@"handleTakePictureTap");
  [self.delegate invokeTakePicture];
}

- (void) handleFocusTap:(UITapGestureRecognizer*)recognizer {
  NSLog(@"handleTapFocusTap");

  if (recognizer.state == UIGestureRecognizerStateEnded)    {
    CGPoint point = [recognizer locationInView:self.view];
    [self.delegate invokeTapToFocus:point];
  }
}

- (void) onFocus{
  [self.delegate invokeTakePicture];
}

- (IBAction)handlePan:(UIPanGestureRecognizer *)recognizer {
        CGPoint translation = [recognizer translationInView:self.view];
        recognizer.view.center = CGPointMake(recognizer.view.center.x + translation.x,
                                             recognizer.view.center.y + translation.y);
        [recognizer setTranslation:CGPointMake(0, 0) inView:self.view];
}

- (void) appplicationIsActive:(NSNotification *)notification {
  dispatch_async(self.sessionManager.sessionQueue, ^{
      NSLog(@"Starting session");
      [self.sessionManager.session startRunning];
      });
}

- (void) applicationEnteredForeground:(NSNotification *)notification {
  dispatch_async(self.sessionManager.sessionQueue, ^{
      NSLog(@"Stopping session");
      [self.sessionManager.session stopRunning];
      });
}

- (UIImageOrientation)
  imageOrientationFromDeviceOrientation:(UIDeviceOrientation)deviceOrientation
                         cameraPosition:(AVCaptureDevicePosition)cameraPosition {
  switch (deviceOrientation) {
    case UIDeviceOrientationPortrait:
      return cameraPosition == AVCaptureDevicePositionFront ? UIImageOrientationLeftMirrored
                                                            : UIImageOrientationRight;

    case UIDeviceOrientationLandscapeLeft:
      return cameraPosition == AVCaptureDevicePositionFront ? UIImageOrientationDownMirrored
                                                            : UIImageOrientationUp;
    case UIDeviceOrientationPortraitUpsideDown:
      return cameraPosition == AVCaptureDevicePositionFront ? UIImageOrientationRightMirrored
                                                            : UIImageOrientationLeft;
    case UIDeviceOrientationLandscapeRight:
      return cameraPosition == AVCaptureDevicePositionFront ? UIImageOrientationUpMirrored
                                                            : UIImageOrientationDown;
    case UIDeviceOrientationUnknown:
    case UIDeviceOrientationFaceUp:
    case UIDeviceOrientationFaceDown:
      return UIImageOrientationUp;
  }
}

-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
  AVCaptureDevicePosition cameraPosition = AVCaptureDevicePositionBack;

   MLKVisionImage *image = [[MLKVisionImage alloc] initWithBuffer:sampleBuffer];
  image.orientation = [self imageOrientationFromDeviceOrientation:UIDevice.currentDevice.orientation cameraPosition:cameraPosition];

  [self.barcodeDetector processImage:image
                   completion:^(NSArray<MLKBarcode *> *_Nullable barcodes,
                               NSError *_Nullable error) {
  if (error != nil) {
    // Error handling
    NSLog(@"ERROR IN SCANNING");
    return;
  }

  if (barcodes.count > 0) {
    // Recognized barcodes
    NSLog(@"hey we are in success");
  }
}];
  // if ([self.renderLock tryLock]) {
  //   CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
  //   CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];


  //   CGFloat scaleHeight = self.view.frame.size.height/image.extent.size.height;
  //   CGFloat scaleWidth = self.view.frame.size.width/image.extent.size.width;

  //   CGFloat scale, x, y;
  //   if (scaleHeight < scaleWidth) {
  //     scale = scaleWidth;
  //     x = 0;
  //     y = ((scale * image.extent.size.height) - self.view.frame.size.height ) / 2;
  //   } else {
  //     scale = scaleHeight;
  //     x = ((scale * image.extent.size.width) - self.view.frame.size.width )/ 2;
  //     y = 0;
  //   }

  //   // scale - translate
  //   CGAffineTransform xscale = CGAffineTransformMakeScale(scale, scale);
  //   CGAffineTransform xlate = CGAffineTransformMakeTranslation(-x, -y);
  //   CGAffineTransform xform =  CGAffineTransformConcat(xscale, xlate);

  //   CIFilter *centerFilter = [CIFilter filterWithName:@"CIAffineTransform"  keysAndValues:
  //     kCIInputImageKey, image,
  //     kCIInputTransformKey, [NSValue valueWithBytes:&xform objCType:@encode(CGAffineTransform)],
  //     nil];

  //   CIImage *transformedImage = [centerFilter outputImage];

  //   // crop
  //   CIFilter *cropFilter = [CIFilter filterWithName:@"CICrop"];
  //   CIVector *cropRect = [CIVector vectorWithX:0 Y:0 Z:self.view.frame.size.width W:self.view.frame.size.height];
  //   [cropFilter setValue:transformedImage forKey:kCIInputImageKey];
  //   [cropFilter setValue:cropRect forKey:@"inputRectangle"];
  //   CIImage *croppedImage = [cropFilter outputImage];

  //   //fix front mirroring
  //   if (self.sessionManager.defaultCamera == AVCaptureDevicePositionFront) {
  //     CGAffineTransform matrix = CGAffineTransformTranslate(CGAffineTransformMakeScale(-1, 1), 0, croppedImage.extent.size.height);
  //     croppedImage = [croppedImage imageByApplyingTransform:matrix];
  //   }

  //   self.latestFrame = croppedImage;

  //   CGFloat pointScale;
  //   if ([[UIScreen mainScreen] respondsToSelector:@selector(nativeScale)]) {
  //     pointScale = [[UIScreen mainScreen] nativeScale];
  //   } else {
  //     pointScale = [[UIScreen mainScreen] scale];
  //   }
  //   CGRect dest = CGRectMake(0, 0, self.view.frame.size.width*pointScale, self.view.frame.size.height*pointScale);

  //   [self.ciContext drawImage:croppedImage inRect:dest fromRect:[croppedImage extent]];
  //   [self.context presentRenderbuffer:GL_RENDERBUFFER];
  //   [(GLKView *)(self.view)display];
  //   [self.renderLock unlock];
  // }
}

- (void)viewDidUnload {
  [super viewDidUnload];

  if ([EAGLContext currentContext] == self.context) {
    [EAGLContext setCurrentContext:nil];
  }
  self.context = nil;
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Release any cached data, images, etc. that aren't in use.
}

- (BOOL)shouldAutorotate {
  return YES;
}

-(void) willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
  [self.sessionManager updateOrientation:[self.sessionManager getCurrentOrientation:toInterfaceOrientation]];
}

@end
