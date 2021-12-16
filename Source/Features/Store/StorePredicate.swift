//
//  StorePredicate.swift
//  MagicBell
//
//  Created by Joan Martin on 26/11/21.
//

import Foundation

/// The notificaiton store predicate
public struct StorePredicate: Hashable, Equatable {
    public enum Read: Int {
        case read
        case unread
        case unspecified
    }

    public enum Seen: Int {
        case seen
        case unseen
        case unspecified
    }

    public enum Archived: Int {
        case archived
        case unarchived
        case unspecified
    }

    public let read: Read
    public let seen: Seen
    public let archived: Archived
    public let categories: [String]
    public let topics: [String]

    /// Predicate default initializer
    /// - Parameters:
    ///   - read: The read status. Defaults to `.unspecified`.
    ///   - seen: The seen status. Defaults to `.unspecified`.
    ///   - archived: The archived status. Defaults to `.unspecified`.
    ///   - categories: The list of categories. Defaults to empty array.
    ///   - topics: The list of topics. Defaults to empty array.
    public init(read: StorePredicate.Read = .unspecified,
                seen: StorePredicate.Seen = .unspecified,
                archived: StorePredicate.Archived = .unspecified,
                categories: [String] = [],
                topics: [String] = []) {
        self.read = read
        self.seen = seen
        self.archived = archived
        self.categories = categories
        self.topics = topics
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(read.hashValue)
        hasher.combine(seen.hashValue)
        hasher.combine(archived.hashValue)
        hasher.combine(categories.hashValue)
        hasher.combine(topics.hashValue)
    }

    public static func == (lhs: StorePredicate, rhs: StorePredicate) -> Bool {
        if lhs.read != rhs.read {
            return false
        }
        if lhs.seen != rhs.seen {
            return false
        }
        if lhs.archived != rhs.archived {
            return false
        }
        if lhs.categories != rhs.categories {
            return false
        }
        if lhs.topics != rhs.topics {
            return false
        }
        return true
    }
}

extension StorePredicate {
    func match(_ notification: Notification) -> Bool {
        let validator = StorePredicateValidator(storePredicate: self)
        return validator.validateNotification(notification)
    }
}
