#import <AVFoundation/AVFoundation.h>
#import <sqlite3.h>
#import <notify.h>
#import <UIKit/UIKit.h>

static AVSpeechSynthesizer *synthesizer = nil;

// 读取 sms.db 最后一条收到的短信
static NSString *getLatestMessageText() {
    sqlite3 *db;
    NSString *dbPath = @"/private/var/mobile/Library/SMS/sms.db";

    if (sqlite3_open_v2([dbPath UTF8String], &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        NSLog(@"[SMSReader] 打开数据库失败: %s", sqlite3_errmsg(db));
        sqlite3_close(db);
        return nil;
    }

    NSString *query = @"SELECT text FROM message WHERE is_from_me = 0 ORDER BY ROWID DESC LIMIT 1;";
    sqlite3_stmt *stmt;
    NSString *result = nil;

    if (sqlite3_prepare_v2(db, [query UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *text = sqlite3_column_text(stmt, 0);
            if (text) {
                result = [NSString stringWithUTF8String:(const char *)text];
            }
        }
        sqlite3_finalize(stmt);
    } else {
        NSLog(@"[SMSReader] SQL 准备失败: %s", sqlite3_errmsg(db));
    }
    sqlite3_close(db);
    return result;
}

// 提取验证码并朗读
static void checkAndSpeakVerificationCode() {
    NSString *body = getLatestMessageText();
    if (body.length == 0) {
        NSLog(@"[SMSReader] 未读取到短信内容（可能被沙箱拦截）");
        return;
    }

    NSLog(@"[SMSReader] 最新短信: %@", body);

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\b\\d{4,8}\\b" options:0 error:nil];
    NSArray *matches = [regex matchesInString:body options:0 range:NSMakeRange(0, body.length)];

    if (matches.count == 0) {
        NSLog(@"[SMSReader] 未匹配到验证码");
        return;
    }

    NSTextCheckingResult *match = matches.firstObject;
    NSString *code = [body substringWithRange:match.range];

    // 去重：10 秒内相同验证码不重复朗读
    static NSString *lastCode = nil;
    static NSTimeInterval lastTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

    if ([code isEqualToString:lastCode] && (now - lastTime) < 10.0) {
        NSLog(@"[SMSReader] 重复验证码，跳过");
        return;
    }
    lastCode = code;
    lastTime = now;

    if (!synthesizer) {
        synthesizer = [[AVSpeechSynthesizer alloc] init];
    }

    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:
        [NSString stringWithFormat:@"验证码，%@", code]];
    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
    utterance.rate = 0.45;

    [synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    [synthesizer speakUtterance:utterance];
    NSLog(@"[SMSReader] 已朗读验证码: %@", code);
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    NSLog(@"[SMSReader] SpringBoard 已加载，开始监听短信");

    // 监听短信数据库变化通知
    int token;
    notify_register_dispatch("com.apple.SMSDatabaseChanged", &token, dispatch_get_main_queue(), ^(int t) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            checkAndSpeakVerificationCode();
        });
    });

    // 兜底：如果上面的通知名不对，用轮询方式检测新短信
    static NSTimeInterval lastCheck = 0;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
        NSString *dbPath = @"/private/var/mobile/Library/SMS/sms.db";
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:dbPath error:nil];
        NSTimeInterval modTime = [attrs[NSFileModificationDate] timeIntervalSince1970];
        if (modTime > lastCheck) {
            lastCheck = modTime;
            checkAndSpeakVerificationCode();
        }
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
}

%end