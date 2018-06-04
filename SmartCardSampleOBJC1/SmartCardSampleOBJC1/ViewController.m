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
#import "PBSmartCardUtils.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    accessory = [PBAccessory sharedClass];
    
    if ([accessory isConnected]) {
        [self printAccessoryStatus:@"Tactivo accessory present"];
    } else {
        [self printAccessoryStatus:@"Tactivo accessory absent"];
    }
    
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    
    [notificationCenter addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:NULL];
    [notificationCenter addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:NULL];
    
    // Listeners for accessory connection events
    [notificationCenter addObserver:self selector:@selector(accessoryDidConnect) name:PBAccessoryDidConnectNotification object:NULL];
    [notificationCenter addObserver:self selector:@selector(accessoryDidDisconnect) name:PBAccessoryDidDisconnectNotification object:NULL];
    
    smartcard = [[PBSmartcard alloc] init];
    
    [notificationCenter addObserver:self selector:@selector(cardInserted) name:@"PB_CARD_INSERTED" object:nil];
    [notificationCenter addObserver:self selector:@selector(cardRemoved) name:@"PB_CARD_REMOVED" object:nil];
    
    trigger = [[NSCondition alloc] init];
}

# pragma mark Application lifecycle events

- (void)applicationDidBecomeActive {
    [self printCardStatus:@""];
    [self printData:@""];
    
    cardThread = [[NSThread alloc] initWithTarget:self selector:@selector(doCard) object:NULL];
    [cardThread start];
}

- (void)applicationWillResignActive {
    [cardThread cancel];
    [trigger signal];
}

# pragma mark Accessory connection events

- (void)accessoryDidConnect {
    [self printAccessoryStatus:@"Tactivo accessory present"];
    [self printCardStatus:@""];
    [self printData:@""];
    
    [trigger signal];
}

- (void)accessoryDidDisconnect {
    [self printAccessoryStatus:@"Tactivo accessory absent"];
    [self printCardStatus:@""];
    [self printData:@""];
    
}

# pragma mark Card events

- (void) cardInserted {
    [trigger signal];
}

- (void) cardRemoved {
    [self printCardStatus:@"Insert smart card..."];
    [self printData:@""];
}

# pragma mark Card operations

- (void)doCard {
    PBSmartcardStatus status;
    
    [self printCardStatus:@""];
    [self printData:@""];
    
    // Open the reader/card object to enable card notifications.
    status = [smartcard open];
    
    if (status != PBSmartcardStatusSuccess) {
        [self printData: [PBSmartCardUtils errorMessageFrom:status]];
        return;
    }
    
    if ([smartcard getSlotStatus] == PBSmartcardSlotStatusEmpty) {
        [self printCardStatus:@"Insert smart card..."];
    }
    
    bool firstRun = true;
    
    while (![cardThread isCancelled]) {
        if (firstRun) {
            firstRun = false;
            [trigger lock];
        } else {
            [trigger wait];
            
            if ([cardThread isCancelled]){
                [self disconnectCard:status];
                continue;
            }
        }
        
        // Connect to the card using the first protocol offered by the card.
        status = [smartcard connect:PBSmartcardProtocolTx];
        NSLog(@"Connect = %d", status);
        
        if (status == PBSmartcardStatusNoSmartcard) {
            [self printCardStatus:@"Insert smart card..."];
            continue;
        }
        
        if (status != PBSmartcardStatusSuccess) {
            [self disconnectCard:status];
            continue;
        }
        
        NSMutableString* atr = [[NSMutableString alloc]init];
        [atr appendString:@"ATR: "];
        
        // After a successful connect the ATR is stored in the ATR property as an array of NSNumbers. Convert the values and put on screen.
        for (int i = 0; i < [[smartcard getATR] count]; i++) {
            NSNumber* num = [[smartcard getATR] objectAtIndex:i];
            [atr appendString:[NSString stringWithFormat:@"%02x", [num unsignedCharValue]]];
        }
        
        [self printCardStatus:atr];
        
        // the protocol property is also set according to the selected card protocol.
        switch ([smartcard getCurrentProtocol]) {
            case PBSmartcardProtocolT0:
                [self printData:@"Connected using T=0\n"];
                break;
                
            case PBSmartcardProtocolT1:
                [self printData:@"Connected using T=1\n"];
                break;
                
            default:
                break;
        }
        
        // Try to read the CPLC data from the card (should work if the card supports Global Platform).
        // See www.globalplatform.org for more information about this command.
        // CLA = 0x80
        // INS = 0xCa
        // P1  = 0x9F
        // P2  = 0x7F
        // Le  = 0x00
        unsigned char get_cplc_command[] = { 0x80, 0xCA, 0x9F, 0x7F, 0x00 };
        unsigned char received_data[255] = { 0 };
        unsigned short received_data_length;
        
        NSLog(@"%s", get_cplc_command);
        
        // On input received_data_length holds the size of the receive buffer.
        received_data_length = sizeof(received_data);
        
        // Send the command APDU and get the response from the card.
        status = [smartcard transmit:get_cplc_command withCommandLength:sizeof(get_cplc_command) andResponseBuffer:received_data andResponseLength:&received_data_length];
        
        NSLog(@"Transmit = %d", status);
        
        // Check if the command was succefully sent to the card.
        if (status != PBSmartcardStatusSuccess) {
            [self disconnectCard:status];
            continue;
        }
        
        // Then check the response from the card
        if (received_data[received_data_length-2] == 0x6C) {
            // On return received_data_length holds the number of bytes returned by the card. Re-send the command with correct Le.
            get_cplc_command[4] = received_data[received_data_length-1];
            received_data_length = sizeof(received_data);
            
            status = [smartcard transmit:get_cplc_command withCommandLength:sizeof(get_cplc_command) andResponseBuffer:received_data andResponseLength:&received_data_length];
            
            NSLog(@"Transmit = %d", status);
            
            // Check if the command was succefully sent to the card
            if (status != PBSmartcardStatusSuccess) {
                [self disconnectCard:status];
                continue;
            }
        } else if (received_data[received_data_length-2] == 0x61) {
            // On return received_data_length holds the number of bytes returned by the card. Read the remaining data with GET RESPONSE.
            unsigned char get_response[] = { 0x00, 0xC0, 0x00, 0x00, 0x00 };
            get_response[4] = received_data[received_data_length-1];
            received_data_length = sizeof(received_data);
            
            status = [smartcard transmit:get_cplc_command withCommandLength:sizeof(get_cplc_command) andResponseBuffer:received_data andResponseLength:&received_data_length];
            
            NSLog(@"Transmit = %d", status);
            
            // Check if the command was successfully sent to the card.
            if (status != PBSmartcardStatusSuccess) {
                [self disconnectCard:status];
                continue;
            }
        }
        
        NSMutableString* cplc = [[NSMutableString alloc]init];
        
        // Parse the result if the card responded succesfully to the CPLC command.
        if (received_data[received_data_length-2] == 0x90 && received_data[received_data_length-1] == 0x00) {
            // We do not validate the data in this example - we assume that it is correct...
            unsigned char* p = received_data + 3; // jump directly to data
            
            [cplc appendString:[NSString stringWithFormat:@"IC fabricator = %02X%02X\n",p[0],p[1]]];
            [cplc appendString:[NSString stringWithFormat:@"IC type = %02X%02X\n",p[2],p[3]]];
            [cplc appendString:[NSString stringWithFormat:@"OS ID = %02X%02X\n",p[4],p[5]]];
            [cplc appendString:[NSString stringWithFormat:@"OS release date = %02X%02X\n",p[6],p[7]]];
            [cplc appendString:[NSString stringWithFormat:@"OS release level = %02X%02X\n",p[8],p[9]]];
            [cplc appendString:[NSString stringWithFormat:@"IC fabrication date = %02X%02X\n",p[10],p[11]]];
            [cplc appendString:[NSString stringWithFormat:@"IC serial number = %02X%02X%02X%02X\n",p[12],p[13],p[14],p[15]]];
            [cplc appendString:[NSString stringWithFormat:@"IC batch ID = %02X%02X\n", p[16],p[17]]];
            [cplc appendString:[NSString stringWithFormat:@"IC module fabrictor = %02X%02X\n", p[18],p[19]]];
            [cplc appendString:[NSString stringWithFormat:@"IC module package date = %02X%02X\n", p[20],p[21]]];
            [cplc appendString:[NSString stringWithFormat:@"ICC manufacturer = %02X%02X\n", p[22],p[23]]];
            [cplc appendString:[NSString stringWithFormat:@"ICC embedding date = %02X%02X\n", p[24],p[25]]];
            [cplc appendString:[NSString stringWithFormat:@"IC pre-personalizer = %02X%02X\n", p[26],p[27]]];
            [cplc appendString:[NSString stringWithFormat:@"IC pre-perso. equipment date = %02X%02X\n", p[28],p[29]]];
            [cplc appendString:[NSString stringWithFormat:@"IC pre-perso. equipment ID = %02X%02X%02X%02X\n", p[31],p[32],p[33],p[34]]];
            [cplc appendString:[NSString stringWithFormat:@"IC personzalizer = %02X%02X\n", p[35],p[36]]];
            [cplc appendString:[NSString stringWithFormat:@"IC perso. date = %02X%02X\n", p[37],p[38]]];
            [cplc appendString:[NSString stringWithFormat:@"IC perso. equipment ID = %02X%02X%02X%02X\n",p[39],p[41],p[42],p[43]]];
        } else {
            // The card responded to the CPLC with an error or warning. See ISO7816-4 for details on the different status words (SW).
            [cplc appendString:@"Card responds with status word 0x"];
            [cplc appendString:[NSString stringWithFormat:@"%02X%02X",received_data[received_data_length-2], received_data[received_data_length-1]]];
            [cplc appendString:@" on the CPLC request. This smart card does not appear to support Global Platform."];
        }
        
        [self appendData:cplc];
        
        [self disconnectCard:status];
    }
    
    status = [smartcard close];
    NSLog(@"Close = %d", status);
    
    [trigger unlock];
    
    [self printCardStatus:@""];
    [self printData:@""];
}

- (void)disconnectCard:(PBSmartcardStatus)status {
    if(status != PBSmartcardStatusSuccess) {
        [self printData: [PBSmartCardUtils errorMessageFrom:status]];
    }
    
    // Unpower the card to to reduce battery drain.
    PBSmartcardStatus newStatus = [smartcard disconnect:PBSmartcardDispositionUnpowerCard];
    
    NSLog(@"Disconnect = %d", newStatus);
}

# pragma mark Utility methods to set text for labels

- (void)printAccessoryStatus:(NSString *)status {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(printAccessoryStatus:) withObject:status waitUntilDone:FALSE];
        return;
    }
    
    self.accessoryStatusLabel.text = status;
}

- (void)printCardStatus:(NSString *)status {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(printCardStatus:) withObject:status waitUntilDone:FALSE];
        return;
    }
    
    self.cardStatusLabel.text = status;
}

- (void)printData:(NSString *)data {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(printData:) withObject:data waitUntilDone:FALSE];
        return;
    }
    
    self.dataTextView.text = data;
}

- (void)appendData:(NSString *)data {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(appendData:) withObject:data waitUntilDone:FALSE];
        return;
    }
    
    self.dataTextView.text = [self.dataTextView.text stringByAppendingString:data];
}

@end
