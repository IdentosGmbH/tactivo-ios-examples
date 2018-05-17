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
#import "winscard.h"
#import "PBSmartCardUtils.h"

@interface ViewController ()

@end

@implementation ViewController

static SCARDCONTEXT globalContext;

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
    SCardCancel(globalContext);
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

# pragma mark Card operations

- (void)doCard {
    DWORD status;
    DWORD protocol;
    
    SCARDCONTEXT context;
    SCARD_READERSTATE readerState;
    char readerList[128];
    DWORD readerListLength;;
    SCARDHANDLE card = 0;
    SCARD_IO_REQUEST sendPCI;
    BYTE receiveBuffer[256];
    DWORD receiveLength;
    
    NSMutableString* errorText;
    
    errorText = [[NSMutableString alloc]initWithString:@""];
    
    // Initialize the framework.
    status = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &context);
    NSLog(@"SCardEstablishContext 0x%08x", status);
    
    if (status != SCARD_S_SUCCESS) {
        [self printCardStatus:@"SCardEstablishContext failed"];
        [self printData:[PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:status]]];
        goto finalize;
    }
    
    globalContext = context;
    
    [trigger lock];
    
    bool firstRun = true;
    
start: {
    if([cardThread isCancelled]) {
        goto finalize;
    }
    
    if(firstRun) {
        firstRun = false;
    } else {
        // Wait for a Tactivo to be connected.
        [trigger wait];
    }
    
    [self printCardStatus:@""];
    [self printData:@""];
    
    readerListLength = sizeof(readerList);
    memset(readerList, 0, readerListLength);
    
    status = SCardListReaders(context, NULL, (LPSTR)&readerList, &readerListLength);
    NSLog(@"SCardListReaders 0x%08x", status);
    
    if(status ==  SCARD_E_NO_READERS_AVAILABLE) {
        [self printCardStatus:@"Connect reader..."];
        goto start;
    } else if(status != SCARD_S_SUCCESS) {
        [errorText setString:@"SCardListReaders failed"];
        goto cleanup;
    }
}
    
again: {
    // Set the current state to unaware to make the initial call to SCardGetStatusChange return immediately - this allows us to get the current state.
    readerState.dwCurrentState = SCARD_STATE_UNAWARE;
    
    // Use the first found reader.
    readerState.szReader = readerList;
    
    // Get the current state of the reader.
    status = SCardGetStatusChange(context, INFINITE, &readerState, 1);
    NSLog(@"SCardGetStatusChange 0x%08x", status);
    
    if (status != SCARD_S_SUCCESS) {
        [errorText setString:@"SCardGetStatusChange failed"];
        goto cleanup;
    }
    
    readerState.dwCurrentState = readerState.dwEventState;
    
    // Wait until a card is inserted or an error occurs.
    while((readerState.dwCurrentState & SCARD_STATE_PRESENT) == FALSE) {
        [self printCardStatus:@"Insert smart card..."];
        
        // Wait for the state to change.
        status = SCardGetStatusChange(context, INFINITE, &readerState, 1);
        
        NSLog(@"SCardGetStatusChange 0x%08x", status);
        
        if (status == SCARD_E_TIMEOUT || status == SCARD_E_READER_UNAVAILABLE) {
            // This is not considered an error. SCardGetStatusChange can return SCARD_E_READER_UNAVAILABLE if called just as iOS decides to end the underlying EASession. The app need to be aware that this situation can happen and more frequently than unplugging the USB cable of a smart card reader on a PC/Mac. In this example we just continue the loop as usual.
        } else if (status != SCARD_S_SUCCESS) {
            [errorText setString:@"SCardGetStatusChange failed"];
            goto cleanup;
        } else {
            // Update the current state with the event state to allow us to exit the loop.
            readerState.dwCurrentState = readerState.dwEventState;
        }
    }
    
    status = SCardConnect(context, readerState.szReader, SCARD_SHARE_EXCLUSIVE, SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, &card, &protocol);
    
    NSLog(@"SCardConnect 0x%08x", status);
    
    // If the card doesn't answer or if the card was just removed, just continue
    if (status == SCARD_W_UNRESPONSIVE_CARD || status == SCARD_E_NO_SMARTCARD) {
        [self printCardStatus:@"Remove smart card..."];
        [self printData:@"SCardConnect failed"];
        [self appendData:[PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:status]]];
        goto retry;
    } else if (status != SCARD_S_SUCCESS) {
        [errorText setString:@"SCardConnect failed"];
        goto cleanup;
    }
    
    // Set the protocol control information based on the selected protocol.
    switch (protocol) {
        case SCARD_PROTOCOL_T0:
            sendPCI = *SCARD_PCI_T0;
            [self printData:@"Connected using T=0\n"];
            break;
            
        case SCARD_PROTOCOL_T1:
            sendPCI = *SCARD_PCI_T1;
            [self printData:@"Connected using T=1\n"];
            break;
            
        default:
            sendPCI = *SCARD_PCI_RAW;
            break;
    }
    
    // We can re-use the card communication buffer to retrieve the ATR. Since we only want to know the ATR we use NULL on the other parameters.
    receiveLength = sizeof(receiveBuffer);
    
    status = SCardStatus(card, NULL, NULL, NULL, NULL, receiveBuffer, &receiveLength);
    
    NSLog(@"SCardStatus 0x%08x", status);
    
    if (status != SCARD_S_SUCCESS) {
        [errorText setString:@"SCardTransmit failed on SCardStatus"];
        goto cleanup;
    }
    
    NSMutableString* atr = [[NSMutableString alloc]initWithString:@"ATR: "];
    
    for(int i = 0; i < receiveLength; i++) {
        [atr appendString:[NSString stringWithFormat:@"%02X ", receiveBuffer[i]]];
    }
    
    [self printCardStatus:atr];
    
    // See www.globalplatform.org for more information about this command.
    // CLA = 0x80
    // INS = 0xCa
    // P1  = 0x9F
    // P2  = 0x7F
    // Le  = 0x00
    unsigned char get_cplc_command[] = { 0x80, 0xCA, 0x9F, 0x7F, 0x00 };
    
    // On input receive_length holds the size of the receive buffer.
    receiveLength = sizeof(receiveBuffer);
    
    status = SCardTransmit(card, &sendPCI, get_cplc_command, sizeof(get_cplc_command), NULL, receiveBuffer, &receiveLength);
    
    NSLog(@"SCardTransmit 0x%08x", status);
    
    // Ccard was removed during tranceive. Not a hard error so we just restart the loop.
    if (status == SCARD_W_REMOVED_CARD){
        goto retry;
    } else if (status != SCARD_S_SUCCESS) {
        [errorText setString:@"SCardTransmit failed on CPLC (w/ Le 0)"];
        goto cleanup;
    }
    
    if (receiveBuffer[receiveLength-2] == 0x6C) {
        // Re-send the command with correct Le reported by the card in SW2.
        get_cplc_command[4] = receiveBuffer[receiveLength-1];
        receiveLength = sizeof(receiveBuffer);
        
        status = SCardTransmit(card, &sendPCI, get_cplc_command, sizeof(get_cplc_command), NULL, receiveBuffer, &receiveLength);
        
        NSLog(@"SCardTransmit 0x%08x", status);
        
        // Ccard was removed during tranceive. Not a hard error so we just restart the loop.
        if (status == SCARD_W_REMOVED_CARD) {
            goto retry;
        } else if (status != SCARD_S_SUCCESS) {
            [errorText setString:@"SCardTransmit failed on CPLC (w/ Le > 0)"];
            goto cleanup;
        }
    } else if (receiveBuffer[receiveLength-2] == 0x6C) {
        unsigned char get_response[] = { 0x00, 0xC0, 0x00, 0x00, 0x00 };
        // SW 2 contains the number of bytes remaining
        get_response[4] = receiveBuffer[receiveLength-1];
        receiveLength = sizeof(receiveBuffer);
        
        status = SCardTransmit(card, &sendPCI, get_response, sizeof(get_response), NULL, receiveBuffer, &receiveLength);
        
        NSLog(@"SCardTransmit 0x%08x", status);
        
        // Card was removed during tranceive. Nnot a hard error so we just restart the loop.
        if (status == SCARD_W_REMOVED_CARD) {
            goto retry;
        } else if (status != SCARD_S_SUCCESS) {
            [errorText setString:@"SCardTransmit failed on GET RESPONSE"];
            goto cleanup;
        }
    }
    
    NSMutableString* cplc = [[NSMutableString alloc]init];
    
    if (receiveBuffer[receiveLength-2] == 0x90 && receiveBuffer[receiveLength-1] == 0x00) {
        // We do not validate the data in this example - we assume that it is correct...
        unsigned char* p = receiveBuffer + 3; // jump directly to data
        
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
        // The card responded to the CPLC with an error or warning. See ISO7816-4 for details on the different status words (SW)
        [cplc appendString:@"Card responds with status word 0x"];
        [cplc appendString:[NSString stringWithFormat:@"%02X%02X",receiveBuffer[receiveLength-2], receiveBuffer[receiveLength-1]]];
        [cplc appendString:@" on the CPLC request. This smart card does not appear to support Global Platform."];
    }
    
    [self appendData:cplc];
}
    
retry: {
    status = SCardDisconnect(card, SCARD_UNPOWER_CARD);
    NSLog(@"SCardDisconnect 0x%08x", status);
    
    // Get the current state of the reader. Here we wait for an "infinite" amount of time instead of 10 seconds as before, both ways are applicable.
    readerState.dwCurrentState = SCARD_STATE_UNAWARE;
    status = SCardGetStatusChange(context, INFINITE, &readerState, 1);
    
    NSLog(@"SCardGetStatusChange 0x%08x", status);
    
    if (status != SCARD_S_SUCCESS) {
        [errorText setString:@"SCardGetStatusChange failed"];
        goto cleanup;
    }
    
    if (readerState.dwEventState &  SCARD_STATE_PRESENT) {
        
        readerState.dwCurrentState = readerState.dwEventState;
        status = SCardGetStatusChange(context, INFINITE, &readerState, 1);
        NSLog(@"SCardGetStatusChange 0x%08x", status);
        
        if (status == SCARD_E_TIMEOUT || status == SCARD_E_READER_UNAVAILABLE) {
            // This is not considered an error. SCardGetStatusChange can return SCARD_E_READER_UNAVAILABLE if called just as iOS decides to end the underlying EASession. The app need to be aware that this situation can happen and more frequently than unplugging the USB cable of a smart card reader on a PC/Mac. In this example we just continue the loop as usual.
        } else if (status != SCARD_S_SUCCESS) {
            [errorText setString:@"SCardGetStatusChange failed"];
            goto cleanup;
        }
    }
    
    [self printCardStatus:@""];
    [self printData:@""];
    
    goto again;
}
    
cleanup: {
    NSLog(@"cleanup:\n");
    [self printCardStatus:@""];
    [self printData:errorText];
    [self appendData:[PBSmartCardUtils errorMessageFrom:[NSNumber numberWithUnsignedInt:status]]];
    
    status = SCardDisconnect(card, SCARD_UNPOWER_CARD);
    
    NSLog(@"SCardDisconnect 0x%08x", status);
    
    goto start;
}
    
finalize:{
    status = SCardDisconnect(card, SCARD_UNPOWER_CARD);
    
    NSLog(@"SCardDisconnect 0x%08x", status);
    
    status = SCardReleaseContext(context);
    
    NSLog(@"SCardReleaseContext 0x%08x", status);
    // We ignore the return codes when disconnecting form the card and releasing the context since there isn't much to do if these functions return an error.
    [trigger unlock];
}
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
