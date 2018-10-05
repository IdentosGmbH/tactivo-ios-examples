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

#import "VerifyFingerViewController.h"
#import "PBBiometry.h"
#import "PBReferenceDatabase.h"
#import "PBVerificationController.h"

@interface VerifyFingerViewController ()  {
    NSArray* timeouts;
    NSArray* falseAcceptRates;
}

@end

@implementation VerifyFingerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    timeouts = @[@3000, @7500, @0xFFFF];
    falseAcceptRates = @[[NSNumber numberWithInt:PBFalseAcceptRate100],
                         [NSNumber numberWithInt:PBFalseAcceptRate10000],
                         [NSNumber numberWithInt:PBFalseAcceptRate1000000]];
}

- (IBAction)verifyFinger:(id)sender {
    NSArray* enrolledFingers = [[PBReferenceDatabase sharedClass] getEnrolledFingers];
    
    if (enrolledFingers.count == 0) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"No enrolled fingers"
                                                                       message:@"Please enroll at least one finger to be able to verify."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK"
                                                                style:UIAlertActionStyleDefault
                                                              handler:nil];
        
        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];

        return;
    }
    
    PBVerificationController* verificationController = [[PBVerificationController alloc] initWithNibName:@"PBVerificationController"
                                                                                                  bundle:[NSBundle mainBundle]];
    verificationController.database = [PBReferenceDatabase sharedClass];
    verificationController.fingers = enrolledFingers;
    verificationController.delegate = self;
    
    verificationController.config.timeout = [timeouts[self.timeoutSegment.selectedSegmentIndex] intValue];
    verificationController.config.falseAcceptRate = [falseAcceptRates[self.securitySegment.selectedSegmentIndex] intValue];
    verificationController.verifyAgainstAllFingers = self.fingersSegment.selectedSegmentIndex == 0;
    
    UINavigationController* verificationNavigationController = [[UINavigationController alloc] initWithRootViewController:verificationController];

    [self.navigationController presentViewController:verificationNavigationController animated:YES completion:nil];
}

- (void)verificationController:(PBVerificationController*)verificationController verifiedFinger:(PBBiometryFinger*)finger {
    [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(popViewController) userInfo:nil repeats:FALSE];
}

- (void)popViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
