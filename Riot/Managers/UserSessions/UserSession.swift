// 
// Copyright 2021 New Vector Ltd
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

/// UserSessionProtocol represents a user session regardless of the communication protocol
protocol UserSessionProtocol {
    var userId: String { get }
}

/// UserSession represents a Matrix user session
/// Note: UserSessionProtocol can be renamed UserSession and UserSession -> MatrixUserSession if we keep this abstraction.
@objcMembers
class UserSession: NSObject, UserSessionProtocol {
        
    // MARK: - Properties
    
    // MARK: Public
    
    let account: MXKAccount
    
    var userId: String {
        guard let userId = self.account.mxCredentials.userId else {
            fatalError("[UserSession] identifier: account.mxCredentials.userId should be defined")
        }
        return userId
    }
    
    var matrixSession: MXSession? {
        return account.mxSession
    }
    
    // MARK: - Setup
    
    init(account: MXKAccount) {
        self.account = account
        super.init()
    }
}
