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
#import "PBSmartCardUtils.h"

@interface ViewController ()

@end

@implementation ViewController

// Used for the simulated operation.
#define SIMULATION_IDLE     0
#define SIMULATION_OK       1
#define SIMULATION_CANCEL   2

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
    
    // Listener for accessory connection events
    [notificationCenter addObserver:self selector:@selector(accessoryDidConnect) name:PBAccessoryDidConnectNotification object:NULL];
    [notificationCenter addObserver:self selector:@selector(accessoryDidDisconnect) name:PBAccessoryDidDisconnectNotification object:NULL];
    
    smartcard = [[PBSmartcard alloc] init];
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
    PBSmartcardStatus result;

    UIBackgroundTaskIdentifier backgroundTask = UIBackgroundTaskInvalid;
    
    // Tell iOS that we want to be able to continue operate even when the app is in the background.
    backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        // The expiration handler is called when the expiration handler expires, usually a couple of seconds before the system terminates the app. The amount if time remaining for background execution can be get with [[UIApplication sharedApplication] backgroundTimeRemaining]]. The amount of time is usually set to 600 seconds when the app is put in the background. It does not seem to be possible to reset or renew the timer when in background mode. The timer is automatically reset every time the app is put in the foreground. See the Apple reference documentation for 'beginBackgroundTaskWithExpirationHandler' for further details on background execution.
    }];
    
    // iOS may reject our request.
    if (backgroundTask == UIBackgroundTaskInvalid) {
        [self printData:@"beginBackgroundTaskWithExpirationHandler failed!"];
        goto done;
    }
    
    // Open the reader/card object to enable card notifications.
    result = [smartcard openWithDisabledBackgroundManagement];
    
    if (result != PBSmartcardStatusSuccess) {
        [self printData:[NSString stringWithFormat:@"Failed to open card: %@", [PBSmartCardUtils errorMessageFrom:result]]];
        
        // Returned when openWithDisabledBackgroundManagement is used on iOS version < 5.0.0 as background execution does not work with the EAAccessory framework with earlier versions of iOS.
        if (result == PBSmartcardStatusNotSupported) {
            [self printData:@"Running Tactivo in the background requires iOS 5.0 or later."];
        }
        
        goto done;
    }

#ifdef USE_SIEMENS_PCSC_CARD
    
    // Connect to the card using the first protocol offered by the card.
    result = [smartcard connect:PBSmartcardProtocolTx];
    
    if (result != PBSmartcardStatusSuccess) {
        [self printData:[NSString stringWithFormat:@"Failed to connect: %@", [self errorToText:result]]];
        goto done;
    }
    
    unsigned char select_wf[] = { 0x00, 0xa4, 0x08, 0x04, 0x04, 0x3e, 0x00, 0x00, 0x01 };
    unsigned char received_data[255] = { 0 };
    unsigned short received_data_length;
    
    // In input received_data_length holds the size of the receive buffer.
    received_data_length = sizeof(received_data);
    
    // Send the command APDU and get the response from the card.
    result = [smartcard transmit:select_wf withCommandLength:sizeof(select_wf) andResponseBuffer:received_data andResponseLength:&received_data_length];
    
    // Check if the command was successfully sent to the card.
    if(result != PBSmartcardStatusSuccess) {
        [self printData:[NSString stringWithFormat:@"Failed to transmit command: %@", [self errorToText:result]]];
        goto done;
    }
    
    if (received_data[received_data_length-2] != 0x90) {
        [self printData: [NSString stringWithFormat:@"Select SW:0x%02x%02x (probably not a Siemens Nixdorf PCSC test card", received_data[received_data_length-2], received_data[received_data_length-1]]];
        goto done;
    }
    
    unsigned char read_file[] = { 0x00, 0xb0, 0x00, 0x00, 0x00 };
    // Le controls the time for the on-card operation, 1 second per read byte.
    read_file[4] = seconds;
    
    
    // On input received_data_length holds the size of the receive buffer.
    received_data_length = sizeof(received_data);
    
    
    [self printData:[NSString stringWithFormat:@"Issuing a %d seconds command to the card", seconds]];
    
    [self printData:@"Minimize app and allow operation to finish on it's own or cancel the operation by removing the smart card from the reader or by disconnecting the Tactivo accessory"];
    
    // Send the command APDU and get the response from the card.
    result = [smartcard transmit:read_file withCommandLength:sizeof(read_file) andResponseBuffer:received_data andResponseLength:&received_data_length];
    
    // check if the command was successfully sent to the card
    if(result != PBSmartcardStatusSuccess) {
        [self printData:[NSString stringWithFormat:@"Failed to transmit command:%@", [self errorToText:result]]];
        goto done;
    }
    
    if (received_data[received_data_length-2] != 0x90) {
        [self printData:[NSString stringWithFormat:@"Read WF SW = 0x%02x%02x", received_data[received_data_length-2], received_data[received_data_length-1]]];
        goto done;
    }
    
    [self printData:@"On-card operation OK"];
    
#else
    
    simulation = SIMULATION_IDLE;
    
    [self printData:[NSString stringWithFormat:@"Starting a %d seconds operation", OPERATION_DURATION]];
    
    [self printData:@"Minimize app and allow operation to finish on it's own or cancel the operation by changing the smart card reader slot state or by disconnecting the Tactivo accessory"];
    
    // Let the main thread handle the timer..
    [self performSelectorOnMainThread:@selector(startSimulatedOperation) withObject:nil waitUntilDone:TRUE];
    
    PBSmartcardSlotStatus slot = [smartcard getSlotStatus];
    
    while (simulation == SIMULATION_IDLE) {
        // Allow ios & accessory to get the initial slot value before canceling. Timing issues with the external accessory framework may cause the initial value to report 'unknown' slot status.
        if (slot == PBSmartcardSlotStatusUnknown) {
            slot = [smartcard getSlotStatus];
        } else {
            // If the slot state changed, cancel the fake operation.
            if (slot != [smartcard getSlotStatus]) {
                simulation = SIMULATION_CANCEL;
            } else {
                [NSThread sleepForTimeInterval:0.1f];
            }
        }
    }
    
    // Disable the timer.
    [timer invalidate];
    timer = NULL;
    
    if (simulation == SIMULATION_CANCEL) {
        [self printData:@"Simulated on-card operation cancelled"];
    } else if (simulation == SIMULATION_OK) {
        [self printData:@"Simulated on-card operation OK"];
    } else {
        [self printData:@"Simulated simulation terminated"];
    }

#endif

done:
    if([smartcard getSlotStatus] > PBSmartcardSlotStatusEmpty) {
        // Unpower the card to to reduce battery drain.
        [smartcard disconnect:PBSmartcardDispositionUnpowerCard];
    }
    
    // Close the reader object
    [smartcard close];
    
    // Enable the test button again
    [self performSelectorOnMainThread:@selector(enableStartButton) withObject:nil waitUntilDone:FALSE];
    
    // Tell iOS that we are done with our background execution to allow the app to be put in regular background mode (suspended).
    if(backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:backgroundTask];
    }
    
    backgroundTask = UIBackgroundTaskInvalid;
}

- (void)startSimulatedOperation {
    timer = [NSTimer scheduledTimerWithTimeInterval:OPERATION_DURATION target:self selector:@selector(completeSimulatedOperation) userInfo:nil repeats:FALSE];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
}

- (void)completeSimulatedOperation {
    simulation = SIMULATION_OK;
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
        
        UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:@"OperationFinished" content:content trigger:trigger];
        
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];
    }
}

@end
