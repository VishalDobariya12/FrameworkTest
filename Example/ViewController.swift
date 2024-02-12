//
//  ViewController.swift
//  Example
//
//  Created by mac on 12/01/24.
//

import UIKit
import FrameworkTest

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("SUM", Testing.shared.sumValue(v1: 10, v2: 20))
        Testing.shared.showLoader()
    }


}

