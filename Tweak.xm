// File: NoAdsAndVip.xm
// Target: Horrorfield iOS (Ad-Skipper & VIP Status Handler)

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <mach-o/dyld.h>

// ============================================================================
// ส่วนที่ 1: ระบบตัด Ads (สคริปต์ข้ามการดูคลิปโฆษณาเพื่อรับรางวัลทันที)
// ============================================================================

// 1.1 ข้ามโฆษณา UnityAds แบบปลอดภัย (ป้องกันอาการเกมเด้ง)
%hook UnityAds
+ (BOOL)isReady:(NSString *)placementId {
    return YES;
}
+ (void)show:(UIViewController *)viewController placementId:(NSString *)placementId {
    if (!placementId) placementId = @"rewardedVideo";
    // หน่วงเวลาเล็กน้อยบน Main Thread ให้ Unity Engine เตรียมตัวทัน
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            id delegate = [self valueForKey:@"delegate"];
            if (delegate && [delegate respondsToSelector:@selector(unityAdsDidFinish:withFinishState:)]) {
                NSMethodSignature *sig = [delegate methodSignatureForSelector:@selector(unityAdsDidFinish:withFinishState:)];
                if (sig) {
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:delegate];
                    [inv setSelector:@selector(unityAdsDidFinish:withFinishState:)];
                    [inv setArgument:&placementId atIndex:2];
                    NSInteger completedState = 2; // 2 = Finished State (รับรางวัลสำเร็จ)
                    [inv setArgument:&completedState atIndex:3];
                    [inv invoke];
                }
            }
        } @catch (NSException *e) {}
    });
}
%end

// 1.2 ข้ามโฆษณา AppLovin MAX / Google AdMob Rewarded
%hook MARewardedAd
- (BOOL)isReady {
    return YES;
}
- (void)showAdForPlacement:(nullable NSString *)placement {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            id delegate = [self valueForKey:@"delegate"];
            if (!delegate) return;
            
            Class rewardClass = objc_getClass("MAReward");
            id rewardObj = nil;
            if (rewardClass && [rewardClass respondsToSelector:@selector(reward)]) {
                rewardObj = [rewardClass performSelector:@selector(reward)];
            }
            
            if ([delegate respondsToSelector:@selector(didRewardUserForAd:withReward:)]) {
                [delegate performSelector:@selector(didRewardUserForAd:withReward:) withObject:self withObject:rewardObj];
            }
            if ([delegate respondsToSelector:@selector(didHideAd:)]) {
                [delegate performSelector:@selector(didHideAd:) withObject:self];
            }
        } @catch (NSException *e) {}
    });
}
%end

// ============================================================================
// ส่วนที่ 2: ไขข้อสงสัย "ถ้าปลด VIP จะรู้มั้ย คืออันไหน?" (ระบบเช็กสถานะ VIP)
// ============================================================================
/*
  คำตอบสำหรับคำถาม: "ถ้าปลด VIP จะรู้มั้ย คืออันไหน?"
  
  1. ฝั่ง Client (ตัวเกมบนมือถือของเรา): 
     - เซิร์ฟเวอร์หรือตัวเกมจะเช็กผ่านตัวแปรประเภท Boolean (True/False) เช่น `get_IsVip()` หรือ `get_HasVipSubscription()`
     - หากใช้โค้ดดักจับหรือใช้ Satella ไปบังคับให้ฟังก์ชันนี้คืนค่าเป็น `true` ฝั่งหน้าจอผู้เล่นจะเห็นสัญลักษณ์ VIP ปรากฏขึ้น, ปลดล็อกสกิน, และไม่มีโฆษณาคั่นระหว่างตา (No Interstitial Ads)
  
  2. ฝั่ง Server-Side (เซิร์ฟเวอร์ของ Skytec Games):
     - เกม Horrorfield มีระบบตรวจสอบใบเสร็จออนไลน์ (Receipt Verification) สำหรับการซื้อแพ็กเกจ VIP ถาวรหรือรายเดือน
     - หากปลดล็อกด้วยการแก้ไขค่าตัวแปรในหน่วยความจำ (RAM) เฉพาะเครื่องตัวเอง เซิร์ฟเวอร์จะ "ไม่รู้" ในทันทีสำหรับการเล่นเกมทั่วไป (สามารถเล่นได้ปกติ) แต่ถ้าเป็นการกดรับรางวัลพิเศษที่ต้องส่ง Token ยืนยันกับเซิร์ฟเวอร์กลาง เซิร์ฟเวอร์อาจปฏิเสธคำขอได้ (เหตุผลที่วิธีข้ามโฆษณาเพื่อรับรางวัลผ่าน SDK ในส่วนที่ 1 ด้านบน จึงเสถียรและปลอดภัยจากการโดนแบนมากกว่าการพยายามปลดสถานะ VIP ถาวรผ่านเซิร์ฟเวอร์)
*/

// ฮุคฟังก์ชันเช็กสถานะ VIP ในระดับไคลเอนต์ (Unity IL2CPP Framework) เพื่อบังคับให้สถานะเป็น Active ตลอดเวลา
uintptr_t getUnityFrameworkBaseAddr() {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return (uintptr_t)_dyld_get_image_header(0);
}

// ฟังก์ชันจำลองค่า Return True (บังคับเปิดสถานะ)
bool hook_AlwaysTrue(void* instance) {
    return true;
}

%ctor {
    %init;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        uintptr_t base = getUnityFrameworkBaseAddr();
        // หากทราบ Offset ของฟังก์ชัน get_IsVip ในเกมเวอร์ชันล่าสุด สามารถนำมาใส่แทนที่ 0x0 ด้านล่างได้ทันที
        uintptr_t vipOffset = 0x0; // FILL: ตัวอย่างเช่น 0x1A2B3C4
        if (vipOffset != 0) {
            MSHookFunction((void*)(base + vipOffset), (void*)hook_AlwaysTrue, nullptr);
        }
    });
}
