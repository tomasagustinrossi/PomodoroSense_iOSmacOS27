//
//  Clipboard.swift
//  PomodoroSense
//
//  Created by Tomas Rossi on 09/10/2026.
//


import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum Clipboard {
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #endif
    }
}