//
//  SubApp.swift
//  Refactorator
//
//  Created by John Holdsworth on 21/12/2016.
//  Copyright © 2016 John Holdsworth. All rights reserved.
//

import Foundation

class Integration {

    init(appDelegate: AppDelegate, count: Int) {
        if count % 10 == 0 {
            DispatchQueue.global().async {
                func appVersion( from dict: [String: Any]? ) -> Double? {
                    return dict == nil ? -1 : (dict?["CFBundleShortVersionString"] as AnyObject).doubleValue
                }
                let localVersion = appVersion(from: Bundle.main.infoDictionary)!
                let url = "https://raw.githubusercontent.com/johnno1962/RefactoratorApp/master/Refactorator/Info.plist"
                let currentVersion = appVersion(from: NSDictionary(contentsOf: URL(string: url)!) as? [String: Any])
                if currentVersion != nil && currentVersion! > localVersion {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Refactorator"
                        alert.informativeText = "An update is available for Refactorator, please download a new copy"
                        alert.runModal()
                        appDelegate.help(sender: nil)
                    }
                }
            }
        }

        if appDelegate.state.project == nil {
            appDelegate.state.setup()
        }
    }

}

extension AppDelegate {

    @IBAction func help(sender: NSMenuItem!) {
        state.open(url: "http://johnholdsworth.com/refactorator.html?index=\(myIndex)")
    }

    @IBAction func donate(sender: NSMenuItem!) {
        state.open(url: "http://johnholdsworth.com/cgi-bin/refactorator.cgi?index=\(myIndex)")
    }

}

let colors = String(data: Data(base64Encoded: "QWxpY2VCbHVlOkFudGlxdWVXaGl0ZTpBcXVhOkFxdWFtYXJpbmU6QXp1cmU6QmVpZ2U6QmlzcXVlOkJsYWNrOkJsYW5jaGVkQWxtb25kOkJsdWU6Qmx1ZVZpb2xldDpCcm93bjpCdXJseVdvb2Q6Q2FkZXRCbHVlOkNoYXJ0cmV1c2U6Q2hvY29sYXRlOkNvcmFsOkNvcm5mbG93ZXJCbHVlOkNvcm5zaWxrOkNyaW1zb246Q3lhbjpEYXJrQmx1ZTpEYXJrQ3lhbjpEYXJrR29sZGVuUm9kOkRhcmtHcmF5OkRhcmtHcmV5OkRhcmtHcmVlbjpEYXJrS2hha2k6RGFya01hZ2VudGE6RGFya09saXZlR3JlZW46RGFya09yYW5nZTpEYXJrT3JjaGlkOkRhcmtSZWQ6RGFya1NhbG1vbjpEYXJrU2VhR3JlZW46RGFya1NsYXRlQmx1ZTpEYXJrU2xhdGVHcmF5OkRhcmtTbGF0ZUdyZXk6RGFya1R1cnF1b2lzZTpEYXJrVmlvbGV0OkRlZXBQaW5rOkRlZXBTa3lCbHVlOkRpbUdyYXk6RGltR3JleTpEb2RnZXJCbHVlOkZpcmVCcmljazpGbG9yYWxXaGl0ZTpGb3Jlc3RHcmVlbjpGdWNoc2lhOkdhaW5zYm9ybzpHaG9zdFdoaXRlOkdvbGQ6R29sZGVuUm9kOkdyYXk6R3JleTpHcmVlbjpHcmVlblllbGxvdzpIb25leURldzpIb3RQaW5rOkluZGlhblJlZDpJbmRpZ286SXZvcnk6S2hha2k6TGF2ZW5kZXI6TGF2ZW5kZXJCbHVzaDpMYXduR3JlZW46TGVtb25DaGlmZm9uOkxpZ2h0Qmx1ZTpMaWdodENvcmFsOkxpZ2h0Q3lhbjpMaWdodEdvbGRlblJvZFllbGxvdzpMaWdodEdyYXk6TGlnaHRHcmV5OkxpZ2h0R3JlZW46TGlnaHRQaW5rOkxpZ2h0U2FsbW9uOkxpZ2h0U2VhR3JlZW46TGlnaHRTa3lCbHVlOkxpZ2h0U2xhdGVHcmF5OkxpZ2h0U2xhdGVHcmV5OkxpZ2h0U3RlZWxCbHVlOkxpZ2h0WWVsbG93OkxpbWU6TGltZUdyZWVuOkxpbmVuOk1hZ2VudGE6TWFyb29uOk1lZGl1bUFxdWFNYXJpbmU6TWVkaXVtQmx1ZTpNZWRpdW1PcmNoaWQ6TWVkaXVtUHVycGxlOk1lZGl1bVNlYUdyZWVuOk1lZGl1bVNsYXRlQmx1ZTpNZWRpdW1TcHJpbmdHcmVlbjpNZWRpdW1UdXJxdW9pc2U6TWVkaXVtVmlvbGV0UmVkOk1pZG5pZ2h0Qmx1ZTpNaW50Q3JlYW06TWlzdHlSb3NlOk1vY2Nhc2luOk5hdmFqb1doaXRlOk5hdnk6T2xkTGFjZTpPbGl2ZTpPbGl2ZURyYWI6T3JhbmdlOk9yYW5nZVJlZDpPcmNoaWQ6UGFsZUdvbGRlblJvZDpQYWxlR3JlZW46UGFsZVR1cnF1b2lzZTpQYWxlVmlvbGV0UmVkOlBhcGF5YVdoaXA6UGVhY2hQdWZmOlBlcnU6UGluazpQbHVtOlBvd2RlckJsdWU6UHVycGxlOlJlYmVjY2FQdXJwbGU6UmVkOlJvc3lCcm93bjpSb3lhbEJsdWU6U2FkZGxlQnJvd246U2FsbW9uOlNhbmR5QnJvd246U2VhR3JlZW46U2VhU2hlbGw6U2llbm5hOlNpbHZlcjpTa3lCbHVlOlNsYXRlQmx1ZTpTbGF0ZUdyYXk6U2xhdGVHcmV5OlNub3c6U3ByaW5nR3JlZW46U3RlZWxCbHVlOlRhbjpUZWFsOlRoaXN0bGU6VG9tYXRvOlR1cnF1b2lzZTpWaW9sZXQ6V2hlYXQ6V2hpdGU6V2hpdGVTbW9rZTpZZWxsb3c6WWVsbG93R3JlZW4=")!, encoding: .utf8 )!.components(separatedBy: ":")
