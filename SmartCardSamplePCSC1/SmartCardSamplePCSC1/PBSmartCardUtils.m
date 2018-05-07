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

#import "PBSmartCardUtils.h"

@implementation PBSmartCardUtils

+ (NSString*)errorMessageFrom:(NSNumber*)errorCode {
    switch ([errorCode unsignedIntValue])
    {
        case 0x00000000L:return @"SCARD_S_SUCCESS";
        case 0x80100001L:return @"SCARD_F_INTERNAL_ERROR";
        case 0x80100002L:return @"SCARD_E_CANCELLED";
        case 0x80100003L:return @"SCARD_E_INVALID_HANDLE";
        case 0x80100004L:return @"SCARD_E_INVALID_PARAMETER";
        case 0x80100005L:return @"SCARD_E_INVALID_TARGET";
        case 0x80100006L:return @"SCARD_E_NO_MEMORY";
        case 0x80100007L:return @"SCARD_F_WAITED_TOO_LONG";
        case 0x80100008L:return @"SCARD_E_INSUFFICIENT_BUFFER";
        case 0x80100009L:return @"SCARD_E_UNKNOWN_READER";
        case 0x8010000AL:return @"SCARD_E_TIMEOUT";
        case 0x8010000BL:return @"SCARD_E_SHARING_VIOLATION";
        case 0x8010000CL:return @"SCARD_E_NO_SMARTCARD";
        case 0x8010000DL:return @"SCARD_E_UNKNOWN_CARD";
        case 0x8010000EL:return @"SCARD_E_CANT_DISPOSE";
        case 0x8010000FL:return @"SCARD_E_PROTO_MISMATCH";
        case 0x80100010L:return @"SCARD_E_NOT_READY";
        case 0x80100011L:return @"SCARD_E_INVALID_VALUE";
        case 0x80100012L:return @"SCARD_E_SYSTEM_CANCELLED";
        case 0x80100013L:return @"SCARD_F_COMM_ERROR";
        case 0x80100014L:return @"SCARD_F_UNKNOWN_ERROR";
        case 0x80100015L:return @"SCARD_E_INVALID_ATR";
        case 0x80100016L:return @"SCARD_E_NOT_TRANSACTED";
        case 0x80100017L:return @"SCARD_E_READER_UNAVAILABLE";
        case 0x80100018L:return @"SCARD_P_SHUTDOWN";
        case 0x80100019L:return @"SCARD_E_PCI_TOO_SMALL";
        case 0x8010001AL:return @"SCARD_E_READER_UNSUPPORTED";
        case 0x8010001BL:return @"SCARD_E_DUPLICATE_READER";
        case 0x8010001CL:return @"SCARD_E_CARD_UNSUPPORTED";
        case 0x8010001DL:return @"SCARD_E_NO_SERVICE";
        case 0x8010001EL:return @"SCARD_E_SERVICE_STOPPED";
        case 0x8010001FL:return @"SCARD_E_UNEXPECTED";
        case 0x80100020L:return @"SCARD_E_ICC_INSTALLATION";
        case 0x80100021L:return @"SCARD_E_ICC_CREATEORDER";
        case 0x80100022L:return @"SCARD_E_UNSUPPORTED_FEATURE";
        case 0x80100023L:return @"SCARD_E_DIR_NOT_FOUND";
        case 0x80100024L:return @"SCARD_E_FILE_NOT_FOUND";
        case 0x80100025L:return @"SCARD_E_NO_DIR";
        case 0x80100026L:return @"SCARD_E_NO_FILE";
        case 0x80100027L:return @"SCARD_E_NO_ACCESS";
        case 0x80100028L:return @"SCARD_E_WRITE_TOO_MANY";
        case 0x80100029L:return @"SCARD_E_BAD_SEEK";
        case 0x8010002AL:return @"SCARD_E_INVALID_CHV";
        case 0x8010002BL:return @"SCARD_E_UNKNOWN_RES_MNG";
        case 0x8010002CL:return @"SCARD_E_NO_SUCH_CERTIFICATE";
        case 0x8010002DL:return @"SCARD_E_CERTIFICATE_UNAVAILABLE";
        case 0x8010002EL:return @"SCARD_E_NO_READERS_AVAILABLE";
        case 0x8010002FL:return @"SCARD_E_COMM_DATA_LOST";
        case 0x80100030L:return @"SCARD_E_NO_KEY_CONTAINER";
        case 0x80100031L:return @"SCARD_E_SERVER_TOO_BUSY";
        case 0x80100032L:return @"SCARD_E_PIN_CACHE_EXPIRED";
        case 0x80100033L:return @"SCARD_E_NO_PIN_CACHE";
        case 0x80100034L:return @"SCARD_E_READ_ONLY_CARD";
        case 0x80100065L:return @"SCARD_W_UNSUPPORTED_CARD";
        case 0x80100066L:return @"SCARD_W_UNRESPONSIVE_CARD";
        case 0x80100067L:return @"SCARD_W_UNPOWERED_CARD";
        case 0x80100068L:return @"SCARD_W_RESET_CARD";
        case 0x80100069L:return @"SCARD_W_REMOVED_CARD";
        case 0x8010006AL:return @"SCARD_W_SECURITY_VIOLATION";
        case 0x8010006BL:return @"SCARD_W_WRONG_CHV";
        case 0x8010006CL:return @"SCARD_W_CHV_BLOCKED";
        case 0x8010006DL:return @"SCARD_W_EOF";
        case 0x8010006EL:return @"SCARD_W_CANCELLED_BY_USER";
        case 0x8010006FL:return @"SCARD_W_CARD_NOT_AUTHENTICATED";
        case 0x80100070L:return @"SCARD_W_CACHE_ITEM_NOT_FOUND";
        case 0x80100071L:return @"SCARD_W_CACHE_ITEM_STALE";
        case 0x80100072L:return @"SCARD_W_CACHE_ITEM_TOO_BIG";
        default:return [NSString stringWithFormat:@"0x%08x", [errorCode unsignedIntValue]];
    }
}

@end
