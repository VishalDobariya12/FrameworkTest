//
//  Testing.swift
//  FrameworkTest
//
//  Created by mac on 12/01/24.
//

import Foundation
//import SVProgressHUD

public class Testing {
    
    //MARK: - Properties
    public static let shared = Testing()
    
    public func sumValue(v1: Int, v2: Int) -> Int {
       return v1 + v2
    }
    
    public func showLoader() {
        
//        SVProgressHUD.show(withStatus: "LOADING")
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
//            SVProgressHUD.dismiss()
//        }
        
    }
    
}
