/*
 * Copyright (c) 2018 Identos GmbH
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the Precise Biometrics AB nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
 * OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 *
 */

#import "ViewController.h"
#import <UserNotifications/UserNotifications.h>
#import "winscard.h"
#import "PBSmartCardUtils.h"

@interface ViewController ()

@end

@implementation ViewController


// Controls the length of the operation (0-255) in seconds.
static unsigned char OPERATION_DURATION = 10;

// Uncomment the line below to perform the lengthy operation with an actual card. Unfortunately there are no generic and/or easy commands that can be sent to any card that also take a long time to return. The Siemens Nixdorf PCSC Group reference test card implement functionality to respond after a predefined number of seconds.

// #define USE_SIEMENS_PCSC_CARD

- (void)viewDidLoad {
    [super viewDidLoad];
    
    accessory = [PBAccessory sharedClass];
    
    if ([accessory isConnected]) {
        [self accessoryDidConnect];
    } else {
        [self accessoryDidDisconnect];
    }
    
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    // Listeners for accessory connection events
    [notificationCenter addObserver:self selector:@selector(accessoryDidConnect) name:PBAccessoryDidConnectNotification object:NULL];
    [notificationCenter addObserver:self selector:@selector(accessoryDidDisconnect) name:PBAccessoryDidDisconnectNotification object:NULL];
}

# pragma mark Accessory connection events

- (void)accessoryDidConnect {
    [self printData:@"Tactivo accessory present"];
    [self enableStartButton];
}

- (void)accessoryDidDisconnect {
    [self printData:@"Tactivo accessory absent"];
    [self disableStartButton];
}

# pragma mark Card operations

- (IBAction)startOperation:(id)sender {
    [self disableStartButton];
    [NSThread detachNewThreadSelector:@selector(operation) toTarget:self withObject:NULL];
}

- (void)operation {
    DWORD ret;
    SCARDCONTEXT context = -1;
    SCARD_READERSTATE readerState;
    SCARDHANDLE card = -1;
    
    UIBackgroundTaskIdentifier backgroundTask = UIBackgroundTaskInvalid;
    
    // Tell iOS that we want to be able to continue operate even when the app is in the background.
    backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        // Call SCardCancel to force a pending SCardGetStatusChange operation to return immediately
        SCardCancel(context);
        // The expiration handler is called when the expiration handler expires, usually a couple of seconds before the system terminates the app. The amount if time remaining for background execution can be get with [[UIApplication sharedApplication] backgroundTimeRemaining]]. The amount of time is usually set to 600 seconds when the app is put in the background. It does not seem to be possible to reset or renew the timer when in background mode. The timer is automatically reset every time the app is put in the foreground. See the Apple reference documentation for 'beginBackgroundTaskWithExpirationHandler' for further details on background execution.
    }];
    
    // iOS may reject our request.
    if (backgroundTask == UIBackgroundTaskInvalid) {
        [self printData:@"beginBackgroundTaskWithExpirationHandler failed!"];
        goto done;
    }
    
    ret = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &context);
    
    if(ret != SCARD_S_SUCCESS) {
        [self printData:[NSString stringWithFormat:@"SCardEstablishContext::%@", [PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:ret]]]];
        goto done;
    }
    
    // Disable (auto background management is enabled by default)
    BYTE value = 0;
    
    // Make sure that the library & iOS keeps the underlying EASession to the Tactivo alive when the app is put in the background by disabling the automatic background handling with the vendor specific attribute & SCardSetAttrib.
    ret = SCardSetAttrib(0, SCARD_ATTR_AUTO_BACKGROUND_HANDLING, (LPCBYTE)&value, sizeof(value));
    
    if(ret != SCARD_S_SUCCESS) {
        [self printData:[NSString stringWithFormat:@"SCardSetAttrib::%@", [PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:ret]]]];
        goto done;
    }
    
    
    readerState.dwCurrentState = SCARD_STATE_UNAWARE;
    
    // We already "know" the reader name (if any). Note that the reader name may change with future versions of the hardware and/or the library. The correct way is to query the reader name with SCardListReaders().
    readerState.szReader = "Precise Smart Card Reader";
    
    // get the initial state of the card slot.
    ret = SCardGetStatusChange(context, 100, &readerState, 1);
    
    if (ret != SCARD_S_SUCCESS) {
        [self printData:[NSString stringWithFormat:@"SCardGetStatusChange::%@", [PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:ret]]]];
        goto done;
    }
    
    readerState.dwCurrentState = readerState.dwEventState;
    
    // Prompt the user to insert a card if not already inserted.
    if (readerState.dwCurrentState < SCARD_STATE_PRESENT) {
        [self printData:@"Insert smart card..."];
    }
    
    // We use a while loop here since timing issues in the ExternalAccessory framework may cause the initial dwEventState to return SCARD_STATE_UNKNOWN.
    while ((readerState.dwCurrentState & SCARD_STATE_PRESENT) == 0) {
        ret = SCardGetStatusChange(context, INFINITE, &readerState, 1);
        
        if (ret != SCARD_S_SUCCESS) {
            [self printData: [NSString stringWithFormat:@"SCardGetStatusChange::%@", [PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:ret]]]];
            goto done;
        }
        
        readerState.dwCurrentState = readerState.dwEventState;
    }
    
#ifdef USE_SIEMENS_PCSC_CARD
    
    // We use the Siemens Nixdorf test card from PCSC workgroup to start an operation on the card that will return after 'seconds' seconds.
    
    SCARD_IO_REQUEST sendPCI;
    BYTE receive_buffer[256];
    DWORD receive_length;
    DWORD protocol;
    
    ret = SCardConnect(context, readerState.szReader, SCARD_SHARE_EXCLUSIVE, SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, &card, &protocol);
    
    if (ret != SCARD_S_SUCCESS) {
        [self printData:[NSString stringWithFormat:@"SCardConnect::%@", [PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:ret]]]];
        goto done;
    }
    
    switch (protocol)
    {
        case SCARD_PROTOCOL_T0:
            sendPCI = *SCARD_PCI_T0;
            break;
        case SCARD_PROTOCOL_T1:
            sendPCI = *SCARD_PCI_T1;
            break;
        default:
            sendPCI = *SCARD_PCI_RAW;
            break;
    }
    
    // select the test file on the card
    unsigned char select_wf[] = { 0x00, 0xa4, 0x08, 0x04, 0x04, 0x3e, 0x00, 0x00, 0x01 };
    
    receive_length = sizeof(receive_buffer);
    
    ret = SCardTransmit(card, &sendPCI, select_wf, sizeof(select_wf), NULL, receive_buffer, &receive_length);
    
    if (ret != SCARD_S_SUCCESS) {
        [self printData: [NSString stringWithFormat:@"SCardTransmit::%@", [PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:ret]]]];
        goto done;
    }
    
    if (receive_buffer[receive_length-2] != 0x90) {
        [self printData: [NSString stringWithFormat:@"Select SW:0x%02x%02x (probably not a Siemens Nixdorf PCSC test card", receive_buffer[receive_length-2], receive_buffer[receive_length-1]]];
        goto done;
    }
    
    unsigned char read_file[] = { 0x00, 0xb0, 0x00, 0x00, 0x00 };
    
    // Le controls the time for the on-card operation, 1 second per read byte.
    read_file[4] = OPERATION_DURATION;
    
    receive_length = sizeof(receive_buffer);
    
    [self printData:[NSString stringWithFormat:@"Issuing a %d seconds command to the card", OPERATION_DURATION]];
    
    [self printData:@"Minimize app and allow operation to finish on it's own or cancel the operation by removing the smart card from the reader or by disconnecting the Tactivo accessory."];
    
    ret = SCardTransmit(card, &sendPCI, read_file, sizeof(read_file), NULL, receive_buffer, &receive_length);
    
    if (ret != SCARD_S_SUCCESS) {
        [self printData: [NSString stringWithFormat:@"SCardTransmit::%@", [PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:ret]]]];
        goto done;
    }
    
    if (receive_buffer[receive_length-2] != 0x90) {
        [self printData:[NSString stringWithFormat:@"Read WF SW = 0x%02x%02x", receive_buffer[receive_length-2], receive_buffer[receive_length-1]]];
        
        goto done;
    }
    
    [self printData:@"On-card operation OK."];
    
#else
    
    // Change the value of 'seconds' to change the length of the operation.
    // The Infineon smart card can be put to work for up to 255 seconds before
    // returning.
    [self printData:[NSString stringWithFormat:@"Starting a %d seconds operation", OPERATION_DURATION]];
    
    [self printData:@"Minimize app and allow operation to finish on it's own or cancel the operation by removing the smart card from the reader or by disconnecting the Tactivo accessory."];
    
    // We simulate a lengthy on-card operation with SCardGetStatusChange.
    // The function will return after 'seconds' seconds.
    ret = SCardGetStatusChange(context,OPERATION_DURATION * 1000, &readerState, 1);
    
    if( ret == SCARD_E_TIMEOUT) {
        // timeout = simulated operation for 'seconds' executed successfully.
        [self printData:@"Simulated on-card operation has executed successfully."];
    } else if (ret == SCARD_S_SUCCESS) {
        // SCardGetStatusChange returned due to its actual purpose, a change of
        // the card state.
        [self printData:@"Simulated on-card operation aborted when card was removed."];
    } else if (ret != SCARD_S_SUCCESS) {
        [self printData:[NSString stringWithFormat:@"SCardGetStatusChange::%@", [PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:ret]]]];
    }
#endif
    
done:
    if (card != -1) {
        ret = SCardDisconnect(card, SCARD_UNPOWER_CARD);
        
        if (ret != SCARD_S_SUCCESS) {
            
            [self printData:[NSString stringWithFormat:@"SCardDisconnect::%@", [PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:ret]]]];
        }
    }
    
    if(context != -1) {
        // SCardReleaseContext will ultimately close the ExternalAccessory session to the accessory and power off any card in the reader (unless already powered off).
        ret = SCardReleaseContext(context);
        
        if (ret != SCARD_S_SUCCESS) {
            
            [self printData:[NSString stringWithFormat:@"SCardReleaseContext::%@", [PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:ret]]]];
        }
        
        context = -1;
    }
    
    [self performSelectorOnMainThread:@selector(enableStartButton) withObject:nil waitUntilDone:NO];
    
    // Tell iOS that we are done with our background execution to allow the app to be put in regular background mode (suspended).
    if(backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:backgroundTask];
    }
    
    backgroundTask = UIBackgroundTaskInvalid;
}

- (void)enableStartButton {
    self.startButton.enabled = YES;
}

- (void)disableStartButton {
    self.startButton.enabled = NO;
}

# pragma mark Utility methods to set text for labels
- (void)printData:(NSString *)data {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(printData:) withObject:data waitUntilDone:FALSE];
        return;
    }
    
    self.dataTextView.text = [self.dataTextView.text stringByAppendingString:[NSString stringWithFormat:@"%@\n", data]];
    
    if ([[UIApplication sharedApplication]applicationState] == UIApplicationStateBackground) {
        NSLog(@"Sending from background");
        
        UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
        content.title = @"Operation finished";
        content.body = data;
        
        UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO];
        
        // Create the request object.
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:@"OperationFinished" content:content trigger:trigger];
        
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
    }
}

@end
