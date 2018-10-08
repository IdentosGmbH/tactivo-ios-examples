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

class VerifyFingerViewController: UIViewController, PBVerificationDelegate {

    @IBOutlet weak var timeoutSegment: UISegmentedControl!
    @IBOutlet weak var securitySegment: UISegmentedControl!
    @IBOutlet weak var fingersSegment: UISegmentedControl!
    
    let timeouts: [UInt16] = [3000, 7500, 0xFFFF];
    let falseAcceptRates = [PBFalseAcceptRate100, PBFalseAcceptRate10000, PBFalseAcceptRate1000000];
    
    @IBAction func verifyFinger(_ sender: Any) {
        guard let database = PBReferenceDatabase.sharedClass() else {
            print("Failed to get database");
            return;
        }
        
        guard let enrolledFingers = database.getEnrolledFingers() else {
            print("Failed to get enrolled fingers");
            return;
        }
        
        if (enrolledFingers.count == 0) {
            let alert = UIAlertController(title: "No enrolled fingers", message: "Please enroll at least one finger to be able to verify.", preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
            self.present(alert, animated: true, completion: nil);
            
            return;
        }
        
        let verificationController = PBVerificationController(nibName: "PBVerificationController", bundle: Bundle.main);
        verificationController.database = PBReferenceDatabase.sharedClass();
        verificationController.fingers = enrolledFingers;
        verificationController.delegate = self;
        
        verificationController.config.timeout = timeouts[self.timeoutSegment.selectedSegmentIndex];
        verificationController.config.falseAcceptRate = falseAcceptRates[self.securitySegment.selectedSegmentIndex];
        verificationController.verifyAgainstAllFingers = self.fingersSegment.selectedSegmentIndex == 0;
        
        let verificationNavigationController = UINavigationController(rootViewController: verificationController);
        
        self.navigationController?.present(verificationNavigationController, animated: true, completion: nil);
    }
    
    func verificationVerifiedFinger(_ finger: PBBiometryFinger!) {
        Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(popViewController), userInfo: nil, repeats: false);
    }
    
    @objc func popViewController() {
        self.dismiss(animated: true, completion: nil);
    }
}
