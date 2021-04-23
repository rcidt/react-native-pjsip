#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>

#import "PjSipCall.h"
#import "PjSipUtil.h"

@implementation PjSipCall

+ (instancetype)itemConfig:(int)id callSetupId:(NSString*)callSetupId {
    return [[self alloc] initWithId:id callSetupId:callSetupId];
}

+ (instancetype)itemConfig:(int)id{
    return [[self alloc] initWithId:id callSetupId:@""];
}

- (id)initWithId:(int)id callSetupId:(NSString*)callSetupId {
    self = [super init];
    
    if (self) {
        self.id = id;
        self.callSetupId = callSetupId;
        self.isHeld = false;
        self.isMuted = false;
    }
    
    return self;
}

#pragma mark - Actions

- (void) hangup {
    pj_status_t status = pjsua_call_hangup(self.id, 0, NULL, NULL);
    
    if (status != PJ_SUCCESS) {
        NSLog(@"Failed to hangup a call (%d)", status);
    }
}

- (void) decline {
    pjsua_call_hangup(self.id, PJSIP_SC_DECLINE, NULL, NULL);
}

- (void)answer {
    // TODO: Add parameters to answer with
    // TODO: Put on hold previous call
    
    pjsua_msg_data msgData;
    pjsua_msg_data_init(&msgData);
    pjsua_call_setting  callOpt;
    pjsua_call_setting_default(&callOpt);
    
    // TODO: Audio/Video count configuration!
    callOpt.aud_cnt = 1;
    callOpt.vid_cnt = 0;
    
    pjsua_call_answer2(self.id, &callOpt, 200, NULL, &msgData);
}

- (void)reInvite {
    pjsua_call_reinvite(self.id, PJSUA_CALL_REINIT_MEDIA | PJSUA_CALL_UPDATE_CONTACT | PJSUA_CALL_UPDATE_VIA, NULL);
}

- (void)hold {
    if (self.isHeld) {
        return;
    }
    
    self.isHeld = true;

    [self disconnectMicrophone];
    [self disconnectSoundDevice];
    pjsua_call_set_hold(self.id, NULL);
}

- (void)unhold {
    if (!self.isHeld) {
        return;
    }
    
    [self connectMicrophone];
    [self connectSoundDevice];
    
    // TODO: May be check whether call is answered before releasing from hold
    pjsua_call_reinvite(self.id, PJSUA_CALL_UNHOLD, NULL);
    
    self.isHeld = false;
    
    if (self.isMuted) {
        [self disconnectMicrophone];
    }
}

- (void)mute {
    [self disconnectMicrophone];
    self.isMuted = true;
}

- (void)unmute {
    [self connectMicrophone];
    self.isMuted = false;
}

- (void)xfer:(NSString*) destination {
    pj_str_t value = pj_str((char *) [destination UTF8String]);
    pjsua_call_xfer(self.id, &value, NULL);
}

- (void)xferReplaces:(int) destinationCallId {
    pjsua_call_xfer_replaces(self.id, destinationCallId, 0, NULL);
}

- (void)redirect:(NSString*) destination {
    pjsua_msg_data msgData;
    pjsip_generic_string_hdr my_hdr;
    pj_str_t hname = pj_str("Contact");
    pj_str_t hvalue = pj_str((char *) [destination UTF8String]);
    pjsua_msg_data_init(&msgData);
    pjsip_generic_string_hdr_init2(&my_hdr, &hname, &hvalue);
    pj_list_push_back(&msgData.hdr_list, &my_hdr);

    pjsua_call_setting callOpt;
    pjsua_call_setting_default(&callOpt);
    pjsua_call_answer2(self.id, &callOpt, PJSIP_SC_MOVED_TEMPORARILY, NULL, &msgData);
}

- (void)dtmf:(NSString*) digits {
    // TODO: Fallback for "The RFC 2833 payload format did not work".
    
    pj_str_t value = pj_str((char *) [digits UTF8String]);
    pjsua_call_dial_dtmf(self.id, &value);
}

- (void)disconnectMicrophone {
    pjsua_call_info info;
    pjsua_call_get_info(self.id, &info);
    
    @try {
        if( info.conf_slot != 0 ) {
            NSLog(@"WC_SIPServer microphone disconnected from call");
            pjsua_conf_disconnect(0, info.conf_slot);
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Unable to mute microphone: %@", exception);
    }
}

- (void)connectMicrophone {
    pjsua_call_info info;
    pjsua_call_get_info(self.id, &info);
    
    @try {
        if( info.conf_slot != 0 ) {
            NSLog(@"WC_SIPServer microphone reconnected to call");
            pjsua_conf_connect(0, info.conf_slot);
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Unable to un-mute microphone: %@", exception);
    }
}

- (void)disconnectSoundDevice {
    pjsua_call_info info;
    pjsua_call_get_info(self.id, &info);
    
    @try {
        if( info.conf_slot != 0 ) {
            NSLog(@"WC_SIPServer audio disconnected from call");
            pjsua_conf_adjust_tx_level(info.conf_slot, 0.0);
            pjsua_conf_adjust_rx_level(info.conf_slot, 0.0);
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Unable disconnect audio device: %@", exception);
    }
}

- (void)connectSoundDevice {
    pjsua_call_info info;
    pjsua_call_get_info(self.id, &info);
    
    @try {
        if( info.conf_slot != 0 ) {
            NSLog(@"WC_SIPServer audio connected from call");
            pjsua_conf_adjust_tx_level(info.conf_slot, 1.0);
            pjsua_conf_adjust_rx_level(info.conf_slot, 1.0);
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Unable connect audio device: %@", exception);
    }
}

#pragma mark - Callback methods

- (void)onStateChanged:(pjsua_call_info)info {
    // Ignore
}

/**
 * The action may connect the call to sound device, to file, or
 * to loop the call.
 */
- (void)onMediaStateChanged:(pjsua_call_info)info {
    pjsua_call_media_status status = info.media_status;
    
    if (status == PJSUA_CALL_MEDIA_ACTIVE || status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
        pjsua_conf_connect(info.conf_slot, 0);
        pjsua_conf_connect(0, info.conf_slot);
    }
}

#pragma mark - Extra

- (NSDictionary *)toJsonDictionary:(bool) isSpeaker {
    pjsua_call_info info;
    pjsua_call_get_info(self.id, &info);
    
    // -----
    int connectDuration = -1;
    
    if (info.state == PJSIP_INV_STATE_CONFIRMED ||
        info.state == PJSIP_INV_STATE_DISCONNECTED) {
        connectDuration = info.connect_duration.sec;
    }

    return @{
        @"id": @(self.id),
        @"callId": [PjSipUtil toString:&info.call_id],
        @"accountId": @(info.acc_id),
        @"callSetupId": self.callSetupId,
        
        @"localContact": [PjSipUtil toString:&info.local_contact],
        @"localUri": [PjSipUtil toString:&info.local_info],
        @"remoteContact": [PjSipUtil toString:&info.remote_contact],
        @"remoteUri": [PjSipUtil toString:&info.remote_info],
        @"state": [PjSipUtil callStateToString:info.state],
        @"stateText": [PjSipUtil toString:&info.state_text],
        @"connectDuration": @(connectDuration),
        @"totalDuration": @(info.total_duration.sec),
        
        @"lastStatusCode": [PjSipUtil callStatusToString:info.last_status],
        @"lastReason": [PjSipUtil toString:&info.last_status_text],
        
        @"held": @(self.isHeld),
        @"muted": @(self.isMuted),
        @"speaker": @(isSpeaker),
        
        @"remoteOfferer": @(info.rem_offerer),
        @"remoteAudioCount": @(info.rem_aud_cnt),
        @"remoteVideoCount": @(info.rem_vid_cnt),
        
        @"audioCount": @(info.setting.aud_cnt),
        @"videoCount": @(info.setting.vid_cnt),
        
        @"media": [self mediaInfoToJsonArray:info.media count:info.media_cnt],
        @"provisionalMedia": [self mediaInfoToJsonArray:info.prov_media count:info.prov_media_cnt]
    };
}

- (NSArray *)mediaInfoToJsonArray: (pjsua_call_media_info[]) info count:(int) count {
    NSMutableArray * result = [NSMutableArray array];
    
    for (int i = 0; i < count; i++) {
        [result addObject:[self mediaToJsonDictionary:info[i]]];
    }
    
    return result;
}

- (NSDictionary *)mediaToJsonDictionary:(pjsua_call_media_info) info {
    return @{
        @"dir": [PjSipUtil mediaDirToString:info.dir],
        @"type": [PjSipUtil mediaTypeToString:info.type],
        @"status": [PjSipUtil mediaStatusToString:info.status],
        @"audioStream": @{
            @"confSlot": @(info.stream.aud.conf_slot)
        },
        @"videoStream": @{
            @"captureDevice": @(info.stream.vid.cap_dev),
            @"windowId": @(info.stream.vid.win_in),
        }
    };
}

@end
