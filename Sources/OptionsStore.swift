//
//  OptionsStore.swift
//  SwiftFormat
//
//  Created by Vincent Bernier on 22-02-18.
//  Copyright © 2018 Nick Lockwood.
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/SwiftFormat
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

struct SavedOption {
    var argumentValue: String
    let descriptor: FormatOptions.Descriptor
}

extension SavedOption: Comparable {
    static func < (lhs: SavedOption, rhs: SavedOption) -> Bool {
        if lhs == rhs {
            return lhs.argumentValue < rhs.argumentValue
        }

        return lhs.descriptor.name < rhs.descriptor.name
    }

    static func == (lhs: SavedOption, rhs: SavedOption) -> Bool {
        return lhs.descriptor.id == rhs.descriptor.id &&
            lhs.descriptor.name == rhs.descriptor.name
    }
}

extension SavedOption {
    private static let mapping: [String: FormatOptions.Descriptor] = {
        let options = FormatOptions.Descriptor.formats + FormatOptions.Descriptor.files + FormatOptions.Descriptor.deprecated
        var dic = [String: FormatOptions.Descriptor]()
        options.forEach { dic[$0.id] = $0 }
        return dic
    }()

    fileprivate init(_ rep: OptionsStore.OptionRepresentation) {
        argumentValue = rep.arg
        descriptor = SavedOption.mapping[rep.id]!
    }
}

struct OptionsStore {
    fileprivate typealias OptionID = String
    fileprivate typealias ArgumentValue = String
    fileprivate typealias OptionRepresentation = (id: OptionID, arg: ArgumentValue)
    private typealias OptionStoreRepresentation = [OptionID: ArgumentValue]

    private let optionsKey = "format-options"
    private let store: UserDefaults

    private static var defaultStore: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: UserDefaults.groupDomain) else {
            fatalError("The UserDefaults Store is invalid")
        }
        return defaults
    }()

    init(_ store: UserDefaults = OptionsStore.defaultStore) {
        self.store = store
        setupDefaultValuesIfNeeded()
    }

    var formatOptions: FormatOptions {
        let allOptions = options
        var formatOptions = FormatOptions()
        allOptions.forEach { try! $0.descriptor.toOptions($0.argumentValue, &formatOptions) }
        return formatOptions
    }

    var options: [SavedOption] {
        return load().map(SavedOption.init)
    }

    func save(_ option: SavedOption) {
        save((id: option.descriptor.id, arg: option.argumentValue))
    }
}

// MARK: - Business Rules

extension OptionsStore {
    private func setupDefaultValuesIfNeeded() {
        if store.value(forKey: optionsKey) == nil {
            resetOptionsToDefaults()
        } else {
            addNewOptonsIfNeeded()
        }
    }

    private func resetOptionsToDefaults() {
        let options = FormatOptions.Descriptor.formats.map { (id: $0.id, arg: $0.defaultArgument) }
        clear()
        save(options)
    }

    private func addNewOptonsIfNeeded() {
        let allDescriptor = FormatOptions.Descriptor.formats
        var options = load()
        var idsToRemove = Set<String>(options.keys)

        for descriptor in allDescriptor {
            if idsToRemove.remove(descriptor.id) == nil {
                //  new option
                options[descriptor.id] = descriptor.defaultArgument
            }
        }

        for id in idsToRemove {
            //  obsolete options to remove
            options[id] = nil
        }

        save(options)
    }
}

// MARK: - Store Interactions

extension OptionsStore {
    private func clear() {
        store.set(nil, forKey: optionsKey)
    }

    private func load() -> OptionStoreRepresentation {
        guard let options = store.value(forKey: optionsKey) as? OptionStoreRepresentation else {
            return OptionStoreRepresentation()
        }
        return options
    }

    private func save(_ option: OptionRepresentation) {
        save([option])
    }

    /// Save the provided rules
    /// Will only override the options in the params
    private func save(_ options: [OptionRepresentation]) {
        var savedOptions = load()
        options.forEach { savedOptions[$0.id] = $0.arg }
        save(savedOptions)
    }

    /// Will replace the options with the param
    private func save(_ options: OptionStoreRepresentation) {
        store.set(options, forKey: optionsKey)
    }
}