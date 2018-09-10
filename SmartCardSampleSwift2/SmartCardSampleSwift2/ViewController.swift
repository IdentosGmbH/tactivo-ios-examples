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
import UserNotifications

enum SimulationStatus {
    case idle
    case ok
    case cancel
}

class ViewController: UIViewController {
    
    // Controls the length of the operation (0-255) in seconds.
    let cardOperationDuration = 10;
    
    // Toggle the line below to perform the lengthy operation with an actual card. Unfortunately there are no generic and/or easy commands that can be sent to any card that also take a long time to return. The Siemens Nixdorf PCSC Group reference test card implement functionality to respond after a predefined number of seconds.
    let useSiemensPcscCard = false;
    
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var dataTextView: UITextView!
    
    var smartcard: PBSmartcard!

    var simulation: SimulationStatus!
    
    var backgroundTask: UIBackgroundTaskIdentifier!
    
    var timer: Timer!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let accessory = PBAccessory.sharedClass();
        
        guard let connected = accessory?.isConnected else {
            printData("Failed to get accessory status");
            return;
        }
        
        if (connected) {
            accessoryDidConnect();
        } else {
            accessoryDidDisconnect();
        }
        
        // Add observers for accessory connection
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryDidConnect), name: .PBAccessoryDidConnect, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryDidDisconnect), name: .PBAccessoryDidDisconnect, object: nil);
        
        smartcard = PBSmartcard();
    }

    // MARK: Accessory connection events
    
    @objc func accessoryDidConnect() {
        printData("Tactivo accessory present");
        enableStartButton();
    }
    
    @objc func accessoryDidDisconnect() {
        printData("Tactivo accessory absent");
        disableStartButton();
    }
    
    // MARK: Card operations
    
    @IBAction func startOperation(_ sender: Any) {
        disableStartButton();
        Thread.detachNewThreadSelector(#selector(operation), toTarget: self, with: nil);
    }
    
    @objc func operation() {
        var result: PBSmartcardStatus;
        
        backgroundTask = UIBackgroundTaskInvalid;
        
        backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            // The expiration handler is called when the expiration handler expires, usually a couple of seconds before the system terminates the app. The amount if time remaining for background execution can be get with [[UIApplication sharedApplication] backgroundTimeRemaining]]. The amount of time is usually set to 600 seconds when the app is put in the background. It does not seem to be possible to reset or renew the timer when in background mode. The timer is automatically reset every time the app is put in the foreground. See the Apple reference documentation for 'beginBackgroundTaskWithExpirationHandler' for further details on background execution.
        });
        
        if (backgroundTask == UIBackgroundTaskInvalid) {
            done();
            return;
        }
        
        result = smartcard.openWithDisabledBackgroundManagement();
        
        if (result != PBSmartcardStatusSuccess) {
            printData("Failed to open card: \(PBSmartCardUtils.errorMessageFrom(result))");
            
            // Returned when openWithDisabledBackgroundManagement is used on iOS version < 5.0.0 as background execution does not work with the EAAccessory framework with earlier versions of iOS.
            if result == PBSmartcardStatusNotSupported {
                printData("Running Tactivo in the background requires iOS 5.0 or later.");
            }
            
            done();
            return;
        }
        
        if (useSiemensPcscCard) {
            // Connect to the card using the first protocol offered by the card.
            result = smartcard.connect(PBSmartcardProtocolTx);
            
            if (result != PBSmartcardStatusSuccess) {
                printData("Failed to connect: \(PBSmartCardUtils.errorMessageFrom(result))");
                done();
                return;
            }
            
            var command: [UInt8] = [ 0x00, 0xa4, 0x08, 0x04, 0x04, 0x3e, 0x00, 0x00, 0x01 ];
            var commandPointer = UnsafeMutablePointer(mutating: command);
            var commandLength = UInt16(MemoryLayout<UInt8>.size * command.count);
            
            var response: [UInt8] = Array(repeating: 0, count: 255);
            var responsePointer = UnsafeMutablePointer(mutating: response);
            var responseLength = UInt16(MemoryLayout<UInt8>.size * response.count);
            
            
            // Send the command APDU and get the response from the card.
            result = smartcard.transmit(commandPointer, withCommandLength: commandLength, andResponseBuffer: responsePointer, andResponseLength: &responseLength);
            
            // Check if the command was successfully sent to the card.
            if (result != PBSmartcardStatusSuccess) {
                printData("Failed to transmit command: \(PBSmartCardUtils.errorMessageFrom(result))");
                done();
                return;
            }
            
            if (responsePointer[Int(responseLength - 2)] != 0x90) {
                printData("This card is probably not a Siemens Nixdorf PCSC test card");
                done();
                return;
            }
            
            command = [ 0x00, 0xb0, 0x00, 0x00, 0x00 ];
            // Le controls the time for the on-card operation, 1 second per read byte.
            command[4] = UInt8(cardOperationDuration);
            commandPointer = UnsafeMutablePointer(mutating: command);
            commandLength = UInt16(MemoryLayout<UInt8>.size * command.count);
            
            response = Array(repeating: 0, count: 255);
            responsePointer = UnsafeMutablePointer(mutating: response);
            responseLength = UInt16(MemoryLayout<UInt8>.size * response.count);
            
            printData("Issuing a \(cardOperationDuration) seconds command to the card");
            
            printData("Minimize app and allow operation to finish on it's own or cancel the operation by removing the smart card from the reader or by disconnecting the Tactivo accessory");
            
            // Send the command APDU and get the response from the card.
            result = smartcard.transmit(commandPointer, withCommandLength: commandLength, andResponseBuffer: responsePointer, andResponseLength: &responseLength);
            
            // check if the command was successfully sent to the card
            if(result != PBSmartcardStatusSuccess) {
                printData("Failed to transmit command: \(PBSmartCardUtils.errorMessageFrom(result))");
                done();
                return;
            }
            
            if (responsePointer[Int(responseLength - 2)] != 0x90) {
                printData("On-card operation failed");
                done();
                return;
            }
            
            printData("On-card operation OK");
        } else {
            simulation = .idle;
            printData("Starting a \(cardOperationDuration) seconds operation");
            
            printData("Minimize app and allow operation to finish on it's own or cancel the operation by removing the smart card from the reader or by disconnecting the Tactivo accessory");

            // Let the main thread handle the timer...
            performSelector(onMainThread: #selector(startSimulatedOperation), with: nil, waitUntilDone: true);
            
            var slot = smartcard.getSlotStatus();
            
            while (simulation == .idle) {
                // Allow ios & accessory to get the initial slot value before canceling. Timing issues with the external accessory framework may cause the initial value to report 'unknown' slot status.
                if (slot == PBSmartcardSlotStatusUnknown) {
                    slot = smartcard.getSlotStatus();
                } else {
                    // If the slot state changed, cancel the fake operation.
                    if (slot != smartcard.getSlotStatus()) {
                        simulation = .cancel;
                    } else {
                        Thread.sleep(forTimeInterval: 0.1);
                    }
                }
            }
            
            // Disable the timer.
            timer.invalidate();
            timer = nil;
            
            if (simulation == .cancel) {
                printData("Simulated on-card operation cancelled");
            } else if (simulation == .ok) {
                printData("Simulated on-card operation OK");
            } else {
                printData("Simulated simulation terminated");
            }
            
            done();
        }
    }
    
    func done() {
        if (smartcard.getSlotStatus() == PBSmartcardSlotStatusPresent || smartcard.getSlotStatus() == PBSmartcardSlotStatusPresentConnected) {
            smartcard.disconnect(PBSmartcardDispositionUnpowerCard)
        }
        
        smartcard.close();
        
        performSelector(onMainThread: #selector(enableStartButton), with: nil, waitUntilDone: false);
        
        if (backgroundTask != UIBackgroundTaskInvalid) {
            UIApplication.shared.endBackgroundTask(backgroundTask);
        }
        
        backgroundTask = UIBackgroundTaskInvalid;
    }
    
    @objc func startSimulatedOperation() {
        timer = Timer.scheduledTimer(timeInterval: Double(cardOperationDuration), target: self, selector: #selector(completeSimulatedOperation), userInfo: nil, repeats: false);
        
        RunLoop.main.add(timer, forMode: .defaultRunLoopMode);
    }
    
    @objc func completeSimulatedOperation() {
        simulation = .ok;
    }
    
    @objc func enableStartButton() {
        startButton.isEnabled = true;
    }
    
    func disableStartButton() {
        startButton.isEnabled = false;
    }

    @objc func printData(_ text: String) {
        if !Thread.isMainThread {
            performSelector(onMainThread: #selector(printData), with: text, waitUntilDone: false);
            return;
        }
        
        dataTextView.text = dataTextView.text + "\(text)\n";
        
        if (UIApplication.shared.applicationState == .background) {
            print("Sending from background");
            
            let content = UNMutableNotificationContent();
            content.title = "Operation finished";
            content.body = text;
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false);
            let request = UNNotificationRequest(identifier: "OperationFinished", content: content, trigger: trigger);
            
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil);
        }
    }
}

