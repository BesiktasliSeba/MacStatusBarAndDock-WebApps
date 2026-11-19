//
//  LocalizationBundle.swift
//  Reynard
//
//  Created by Minh Ton on 23/8/26.
//

import Foundation
import ObjectiveC

final class LocalizationBundle: Bundle, @unchecked Sendable {
    static func activate() {
        object_setClass(Bundle.main, LocalizationBundle.self)
    }
    
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        // In site mode the app's own name replaces "Reynard" in every string it shows.
        return SiteMode.appNamed(resolvedString(forKey: key, value: value, table: tableName))
    }
    
    private func resolvedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let localizedString = super.localizedString(forKey: key, value: value, table: tableName)
        guard localizedString.isEmpty else {
            return localizedString
        }
        
        guard let value, !value.isEmpty else {
            return key
        }
        
        return value
    }
}
