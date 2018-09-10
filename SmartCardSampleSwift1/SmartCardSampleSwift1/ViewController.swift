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

class ViewController: UIViewController {

    @IBOutlet weak var accessoryStatusLabel: UILabel!
    @IBOutlet weak var cardStatusLabel: UILabel!
    @IBOutlet weak var dataTextView: UITextView!
    
    var smartcard: PBSmartcard!
    
    var trigger: NSCondition!
    
    var cardThread: Thread!
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        let accessory = PBAccessory.sharedClass();

        guard let connected = accessory?.isConnected else {
            printAccessoryStatus("Failed to get accessory status");
            return;
        }
        
        if (connected) {
            printAccessoryStatus("Tactivo accessory present");
        } else {
            printAccessoryStatus("Tactivo accessory absent");
        }
        
        // Add observers for accessory connection
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryDidConnect), name: .PBAccessoryDidConnect, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryDidDisconnect), name: .PBAccessoryDidDisconnect, object: nil);
        
        // Add observers for card events
        NotificationCenter.default.addObserver(self, selector: #selector(cardInserted), name: .cardInserted, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(cardRemoved), name: .cardRemoved, object: nil);
        
        // Add observers for app foreground/background events
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: .UIApplicationDidBecomeActive, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive), name: .UIApplicationWillResignActive, object: nil);

        smartcard = PBSmartcard();
        trigger = NSCondition();
    }
    
    // MARK: Application lifecycle events

    @objc func applicationDidBecomeActive() {
        printCardStatus("");
        printData("");
        
        cardThread = Thread(target: self, selector: #selector(doCard), object: nil);
        cardThread.start();
    }
    
    @objc func applicationWillResignActive() {
        cardThread.cancel();
        trigger.signal();
    }
    
    // MARK: Accessory connection events
    
    @objc func accessoryDidConnect() {
        printAccessoryStatus("Tactivo accessory present");
        printCardStatus("");
        printData("");
        
        trigger.signal();
    }
    
    @objc func accessoryDidDisconnect() {
        printAccessoryStatus("Tactivo accessory present");
        printCardStatus("");
        printData("");
    }
    
    // MARK: Card events
    
    @objc func cardInserted() {
        trigger.signal();
    }
    
    @objc func cardRemoved() {
        printCardStatus("Insert smart card...");
        printData("");
    }
    
    // MARK: Card operations
    
    @objc func doCard() {
        var status: PBSmartcardStatus;
        
        status = smartcard.open();
        
        if status != PBSmartcardStatusSuccess {
            printData(PBSmartCardUtils.errorMessageFrom(status));
        }
        
        if smartcard.getSlotStatus() == PBSmartcardSlotStatusEmpty {
            printCardStatus("Insert smart card...");
        }
        
        var firstRun = true;
        
        while !cardThread.isCancelled {
            if firstRun {
                firstRun = false;
                trigger.lock();
            } else {
                trigger.wait();
                
                if cardThread.isCancelled {
                    disconnectCard(status);
                    continue;
                }
            }
            
            status = smartcard.connect(PBSmartcardProtocolTx);
            print("Connect: \(status)");
            
            if status == PBSmartcardStatusNoSmartcard {
                printCardStatus("Insert smart card...");
                continue;
            }
            
            if status != PBSmartcardStatusSuccess {
                disconnectCard(status);
                continue;
            }
            
            guard let atr = smartcard.getATR() else {
                disconnectCard(status);
                continue;
            }
            
            var atrString = "ATR: ";
            
            for item in atr {
                guard let number = item as? Int else {
                    return
                }
                atrString += String(format: "%02x ", number);
            }
            
            printCardStatus(atrString);
            
            switch (smartcard.getCurrentProtocol()) {
            case PBSmartcardProtocolT0:
                printData("Connected using T=0\n");
                break;
            case PBSmartcardProtocolT1:
                printData("Connected using T=1\n");
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
            var command: [UInt8] = [0x80, 0xCA, 0x9F, 0x7F, 0x00];
            var commandPointer = UnsafeMutablePointer(mutating: command);
            var commandLength = UInt16(MemoryLayout<UInt8>.size * command.count);
            
            var response: [UInt8] = Array(repeating: 0, count: 255);
            var responsePointer = UnsafeMutablePointer(mutating: response);
            var responseLength = UInt16(MemoryLayout<UInt8>.size * response.count);
            
            // Send the command APDU and get the response from the card.
            status = smartcard.transmit(commandPointer, withCommandLength: commandLength, andResponseBuffer: responsePointer, andResponseLength: &responseLength);
            
            // Check if the command was succefully sent to the card.
            if status != PBSmartcardStatusSuccess {
                disconnectCard(status);
                continue;
            }
            
            if responsePointer[Int(responseLength - 2)] == 0x6C {
                // On return responseLength holds the number of bytes returned by the card. Re-send the command with correct Le.
                command[4] = responsePointer[Int(responseLength - 1)];
                commandPointer = UnsafeMutablePointer(mutating: command);
                commandLength = UInt16(MemoryLayout<UInt8>.size * command.count);
                
                response = Array(repeating: 0, count: 255);
                responsePointer = UnsafeMutablePointer(mutating: response);
                responseLength = UInt16(MemoryLayout<UInt8>.size * response.count);
                
                status = smartcard.transmit(commandPointer, withCommandLength: commandLength, andResponseBuffer: responsePointer, andResponseLength: &responseLength);
                
                if status != PBSmartcardStatusSuccess {
                    disconnectCard(status);
                    continue;
                }
            } else if responsePointer[Int(responseLength - 2)] == 0x61 {
                // On return responseLength holds the number of bytes returned by the card. Read the remaining data with GET RESPONSE.
                let getResponse: [UInt8] = [0x00, 0xC0, 0x00, 0x00, responsePointer[Int(responseLength - 1)]]
                commandPointer = UnsafeMutablePointer(mutating: getResponse);
                commandLength = UInt16(MemoryLayout<UInt8>.size * getResponse.count);
                
                response = Array(repeating: 0, count: 255);
                responsePointer = UnsafeMutablePointer(mutating: response);
                responseLength = UInt16(MemoryLayout<UInt8>.size * response.count);
                
                status = smartcard.transmit(commandPointer, withCommandLength: commandLength, andResponseBuffer: responsePointer, andResponseLength: &responseLength);
                
                if status != PBSmartcardStatusSuccess {
                    disconnectCard(status);
                    continue;
                }
            }
            
            var data = "";
            
            // Parse the result if the card responded successfully to the CPLC command.
            if (responsePointer[Int(responseLength - 2)] == 0x90 && responsePointer[Int(responseLength - 1)] == 0x00)
            {
                // We do not validate the data in this example - we assume that it is correct...
                // Jump to the data
                responsePointer += 3;
                
                data += String(format:"IC fabricator = %02X%02X\n", responsePointer[0], responsePointer[1]);
                data += String(format:"IC type = %02X%02X\n", responsePointer[2], responsePointer[3]);
                data += String(format:"OS ID = %02X%02X\n", responsePointer[4], responsePointer[5]);
                data += String(format:"OS release date = %02X%02X\n", responsePointer[6], responsePointer[7]);
                data += String(format:"OS release level = %02X%02X\n",responsePointer[8],responsePointer[9]);
                data += String(format:"IC fabrication date = %02X%02X\n",responsePointer[10],responsePointer[11]);
                data += String(format:"IC serial number = %02X%02X%02X%02X\n",responsePointer[12],responsePointer[13],responsePointer[14],responsePointer[15]);
                data += String(format:"IC batch ID = %02X%02X\n", responsePointer[16],responsePointer[17]);
                data += String(format:"IC module fabrictor = %02X%02X\n", responsePointer[18],responsePointer[19]);
                data += String(format:"IC module package date = %02X%02X\n", responsePointer[20],responsePointer[21]);
                data += String(format:"ICC manufacturer = %02X%02X\n", responsePointer[22],responsePointer[23]);
                data += String(format:"ICC embedding date = %02X%02X\n", responsePointer[24],responsePointer[25]);
                data += String(format:"IC pre-personalizer = %02X%02X\n", responsePointer[26],responsePointer[27]);
                data += String(format:"IC pre-perso. equipment date = %02X%02X\n", responsePointer[28],responsePointer[29]);
                data += String(format:"IC pre-perso. equipment ID = %02X%02X%02X%02X\n", responsePointer[31],responsePointer[32],responsePointer[33],responsePointer[34]);
                data += String(format:"IC personzalizer = %02X%02X\n", responsePointer[35],responsePointer[36]);
                data += String(format:"IC perso. date = %02X%02X\n", responsePointer[37],responsePointer[38]);
                data += String(format:"IC perso. equipment ID = %02X%02X%02X%02X\n",responsePointer[39],responsePointer[41],responsePointer[42],responsePointer[43]);
            }
            else
            {
                data = String(format: "Card responds with status word 0x%02X%02X on the CPLC request. This smart card does not appear to support Global Platform.", responsePointer[Int(responseLength - 2)], responsePointer[Int(responseLength - 1)]);
                // The card responded to the CPLC with an error or warning. See ISO7816-4 for details on the different status words (SW).
            }
            
            appendData(data);
            
            disconnectCard(status);
        }
        
        status = smartcard.close();
        
        print("Close smartcard: \(status)");
        
        trigger.unlock();
        
        printCardStatus("");
        printData("");
    }
    
    func disconnectCard(_ status: PBSmartcardStatus) {
        if status != PBSmartcardStatusSuccess {
            printData(PBSmartCardUtils.errorMessageFrom(status));
        }
        
        // Unpower the card to to reduce battery drain.
        let newStatus = smartcard.disconnect(PBSmartcardDispositionUnpowerCard);
        
        print("Disconnect: \(newStatus)");
    }
    
    // MARK: Utility methods to set text for labels
    
    @objc func printAccessoryStatus(_ text: String) {
        if !Thread.isMainThread {
            performSelector(onMainThread: #selector(printAccessoryStatus), with: text, waitUntilDone: false);
            return;
        }
        
        accessoryStatusLabel.text = text;
    }
    
    @objc func printCardStatus(_ text: String) {
        if !Thread.isMainThread {
            performSelector(onMainThread: #selector(printCardStatus), with: text, waitUntilDone: false);
            return;
        }
        
        cardStatusLabel.text = text;
    }
    
    @objc func printData(_ text: String) {
        if !Thread.isMainThread {
            performSelector(onMainThread: #selector(printData), with: text, waitUntilDone: false);
            return;
        }
        
        dataTextView.text = text;
    }
    
    @objc func appendData(_ text: String) {
        if !Thread.isMainThread {
            performSelector(onMainThread: #selector(appendData), with: text, waitUntilDone: false);
            return;
        }
        
        dataTextView.text = dataTextView.text + text;
    }
}
