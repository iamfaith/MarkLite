//
//  SettingsViewController.swift
//  Markdown
//
//  Created by zhubch on 2017/6/23.
//  Copyright © 2017年 zhubch. All rights reserved.
//

import UIKit
import Alamofire
import RxSwift

class SettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var versionLabel: UILabel!

    var textField: UITextField?
    
    let impactFeedbackSwitch = UISwitch()
    let displayOptionSwitch = UISwitch()
    let darkAppIconSwitch = UISwitch()

    var items: [(String,[(String,String,Selector)])] {
        var section = [
    ("NightMode",Configure.shared.darkOption.value.displayName,#selector(darkMode)),
            ("Theme","",#selector(theme)),
            ("ImpactFeedback","",#selector(impactFeedback))
            ]
        if UIApplication.shared.supportsAlternateIcons {
            section.insert(("DarkAppIcon","",#selector(darkAppIcon)), at: 0)
        }
        var status: String = "SubscribeNow"
        if Configure.shared.isPro {
            status = /"Expire" + " " + Configure.shared.expireDate.readableDate()
        }

        var items = [
            ("共享",[("FileSharing","",#selector(webdav))]),
            ("功能",[
                ("ImageStorage",Configure.shared.imageStorage.displayName,#selector(imageStorage)),
                ("FileOpenOption",Configure.shared.openOption.displayName,#selector(fileOpenOption)),
                ("ShowExtensionName","",#selector(displayOption)),
                ]),
            ("外观",section),
            ("支持一下",[
                ("Contact","",#selector(feedback))
                ])
        ]
        if Configure.shared.expireDate.timeIntervalSinceNow <= 3600 * 24 * 31  {
            items.insert(("高级帐户",[("Premium",status,#selector(premium))]), at: 0)
        }
        return items;
    }
    
    let bag = DisposeBag()
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Configure.shared.theme.value == .white ? .default : .lightContent
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        versionLabel.text = "Markdown v\(Configure.shared.currentVerion ?? "1.7.0")"
        
        self.title = /"Settings"
        navBar?.setTintColor(.navTint)
        navBar?.setBackgroundColor(.navBar)
        navBar?.setTitleColor(.navTitle)
        tableView.setBackgroundColor(.tableBackground)
        tableView.setSeparatorColor(.primary)

        displayOptionSwitch.setTintColor(.tint)
        impactFeedbackSwitch.setTintColor(.tint)
        darkAppIconSwitch.setTintColor(.tint)

        darkAppIconSwitch.isOn = Configure.shared.darkAppIcon
        displayOptionSwitch.isOn = Configure.shared.showExtensionName
        impactFeedbackSwitch.isOn = Configure.shared.impactFeedback

        darkAppIconSwitch.addTarget(self, action: #selector(darkAppIcon(_:)), for: .valueChanged)
        displayOptionSwitch.addTarget(self, action: #selector(displayOption(_:)), for: .valueChanged)
        impactFeedbackSwitch.addTarget(self, action: #selector(impactFeedback(_:)), for: .valueChanged)

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    }
    
    @objc func close() {
        impactIfAllow()
        self.navigationController?.dismiss(animated: true, completion: nil)
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items[section].1.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = BaseTableViewCell(style: .value1, reuseIdentifier: nil)

        let item = items[indexPath.section].1[indexPath.row]
        cell.textLabel?.text = /(item.0)
        cell.detailTextLabel?.text = /(item.1)
        cell.needUnlock = item.0 == "FileSharing" && Configure.shared.isPro == false

        if item.0 == "ShowExtensionName" {
            cell.addSubview(displayOptionSwitch)
            cell.accessoryType = .none
            displayOptionSwitch.snp.makeConstraints { maker in
                maker.centerY.equalToSuperview()
                maker.right.equalToSuperview().offset(-20)
            }
        } else if item.0 == "ImpactFeedback" {
            cell.addSubview(impactFeedbackSwitch)
            cell.accessoryType = .none
            impactFeedbackSwitch.snp.makeConstraints { maker in
                maker.centerY.equalToSuperview()
                maker.right.equalToSuperview().offset(-20)
            }
        } else if item.0 == "DarkAppIcon" {
            cell.addSubview(darkAppIconSwitch)
            cell.accessoryType = .none
            darkAppIconSwitch.snp.makeConstraints { maker in
                maker.centerY.equalToSuperview()
                maker.right.equalToSuperview().offset(-20)
            }
        } else {
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let item = items[indexPath.section].1[indexPath.row]
        if item.0 == "ShowExtensionName" || item.0 == "ImpactFeedback" || item.0 == "DarkAppIcon" {
            return
        }
        perform(item.2)
        impactIfAllow()
    }
}

extension SettingsViewController {
    
    func doIfPro(_ task: (() -> Void)) {
        if Configure.shared.isPro {
            task()
            return
        }
        showAlert(title: /"PremiumOnly", message: /"PremiumTips", actionTitles: [/"SubscribeNow",/"Cancel"], textFieldconfigurationHandler: nil) { (index) in
            if index == 0 {
                self.premium()
            }
        }
    }
    
    @objc func premium() {
        let sb = UIStoryboard(name: "Settings", bundle: Bundle.main)
        let vc = sb.instantiateVC(PurchaseViewController.self)!
        pushVC(vc)
    }
        
    @objc func feedback() {
        showAlert(title: /"Contact", message: /"ContactMessage", actionTitles: [/"Cancel",/"Email"]) { index in
            if index == 1 {
                UIApplication.shared.open(URL(string: emailUrl)!, options: [:], completionHandler: nil)
            }
        }
    }
    
    @objc func darkMode() {
        let items = [DarkModeOption.dark,.light,.system]
        let index = items.index{ Configure.shared.darkOption.value == $0 }

        let wraper = OptionsWraper(selectedIndex: index, editable: false, title: /"NightMode", items: items) {
            Configure.shared.darkOption.value = $0 as! DarkModeOption
        }
        let vc = OptionsViewController()
        vc.options = wraper
        pushVC(vc)
    }
    
    @objc func displayOption(_ sender: UISwitch) {
        Configure.shared.showExtensionName = sender.isOn
        NotificationCenter.default.post(name: NSNotification.Name("DisplayOptionChanged"), object: nil)
    }
    
    @objc func impactFeedback(_ sender: UISwitch) {
        Configure.shared.impactFeedback = sender.isOn
    }
    
    @objc func darkAppIcon(_ sender: UISwitch) {
        let name = sender.isOn ? "icon_logo_dark" : nil
        UIApplication.shared.setAlternateIconName(name) { error in
            if error == nil {
                Configure.shared.darkAppIcon = sender.isOn
            }
        }
    }
    
    @objc func webdav() {
        doIfPro {
            if NetworkReachabilityManager()?.isReachableOnEthernetOrWiFi ?? false {
                self.performSegue(withIdentifier: "webdav", sender: nil)
            } else {
                ActivityIndicator.showError(withStatus: /"ConnectWifiTips")
            }
        }
    }
    
    @objc func theme() {
        let items = [Theme.white,.black,.pink,.green,.blue,.purple,.red]
        let index = items.index{ Configure.shared.theme.value == $0 }

        let wraper = OptionsWraper(selectedIndex: index, editable: false, title: /"Theme", items: items) {
            Configure.shared.theme.value = $0 as! Theme
        }
        let vc = OptionsViewController()
        vc.options = wraper
        pushVC(vc)
    }
    
    @objc func imageStorage() {
        let items = [ImageStorageOption.ask,.local,.remote]
        let index = items.index{ Configure.shared.imageStorage == $0 }

        let wraper = OptionsWraper(selectedIndex: index, editable: false, title: /"ImageStorage", items: items) {
            Configure.shared.imageStorage = $0 as! ImageStorageOption
        }
        let vc = OptionsViewController()
        vc.options = wraper
        pushVC(vc)
    }
    
    @objc func fileOpenOption() {
        let items = [FileOpenOption.edit,.preview]
        let index = items.index{ Configure.shared.openOption == $0 }

        let wraper = OptionsWraper(selectedIndex: index, editable: false, title: /"FileOpenOption", items: items) {
            Configure.shared.openOption = $0 as! FileOpenOption
        }
        let vc = OptionsViewController()
        vc.options = wraper
        pushVC(vc)
    }

}
