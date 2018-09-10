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

import UIKit

class PBSmartCardUtils: NSObject {
    static func errorMessageFrom(_ status: PBSmartcardStatus) -> String {
        switch (status) {
        case PBSmartcardStatusSuccess:
            return "No error was encountered.";
            
        case PBSmartcardStatusInvalidParameter:
            return "One or more of the supplied parameters could not be properly interpreted.";
            
        case PBSmartcardStatusSharingViolation:
            return "The smart card cannot be accessed because of other connections outstanding.";
            
        case PBSmartcardStatusNoSmartcard:
            return "The operation requires a Smart Card, but no Smart Card is currently in the device.";
            
        case PBSmartcardStatusProtocolMismatch:
            return "The requested protocols are incompatible with the protocol currently in use with the smart card.";
            
        case PBSmartcardStatusNotReady:
            return "The reader or smart card is not ready to accept commands.";
            
        case PBSmartcardStatusInvalidValue:
            return "One or more of the supplied parameters values could not be properly interpreted.";
            
        case PBSmartcardStatusReaderUnavailable:
            return "The reader is not currently available for use.";
            
        case PBSmartcardStatusUnexpected:
            return "An unexpected card error has occurred.";
            
        case PBSmartcardStatusUnsupportedCard:
            return "The reader cannot communicate with the card, due to ATR string configuration conflicts.";
            
        case PBSmartcardStatusUnresponsiveCard:
            return "The smart card is not responding to a reset.";
            
        case PBSmartcardStatusUnpoweredCard:
            return "Power has been removed from the smart card, so that further communication is not possible.";
            
        case PBSmartcardStatusResetCard:
            return "The smart card has been reset, so any shared state information is invalid.";
            
        case PBSmartcardStatusRemovedCard:
            return "The smart card has been removed, so further communication is not possible.";
            
        case PBSmartcardStatusProtocolNotIncluded:
            return "All necessary supported protocols are not defined in the plist file.";
            
        case PBSmartcardStatusInternalSessionLost:
            return "An internal session was terminated by iOS.";
            
        case PBSmartcardStatusNotSupported:
            return "The operation is not supported on your current version of iOS or with the current Tactivo firmware.";
            
        default:
            return "Unknown error";
        }
    }
}
