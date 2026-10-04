//
//  PomodoroWidgetMacBundle.swift
//  PomodoroWidgetMac
//
//  Created by Tomas Rossi on 12/10/2026.
//

import WidgetKit
import SwiftUI

@main
struct PomodoroWidgetMacBundle: WidgetBundle {
    var body: some Widget {
        PomodoroWidgetMac()
        PomodoroWidgetMacControl()
    }
}
