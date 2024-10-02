//
// By downloading or using this software made available by MagicBell, Inc.
// ("MagicBell") or any documentation that accompanies it (collectively, the
// "Software"), you and the company or entity that you represent (collectively,
// "you" or "your") are consenting to be bound by and are becoming a party to this
// License Agreement (this "Agreement"). You hereby represent and warrant that you
// are authorized and lawfully able to bind such company or entity that you
// represent to this Agreement.  If you do not have such authority or do not agree
// to all of the terms of this Agreement, you may not download or use the Software.
//
// For more information, read the LICENSE file.
//

import Harmony
import Foundation

///
/// The NotificationStore class represents a collection of MagicBell notifications.
///
// swiftlint:disable type_body_length
// swiftlint:disable file_length
public class NotificationStore: Collection, StoreRealTimeObserver {
    private let pageSize = 50

    private let fetchStorePageInteractor: FetchStorePageInteractor
    private let actionNotificationInteractor: ActionNotificationInteractor
    private let deleteNotificationInteractor: DeleteNotificationInteractor

    /// The predicate of the store
    public let predicate: StorePredicate

    private let userQuery: UserQuery
    private(set) var notifications: [Notification] = []

    /// Total number of notifications
    public private(set) var totalCount: Int = 0
    /// Total number of unread notifications
    public private(set) var unreadCount: Int = 0
    /// Total number of unseen notifications
    public private(set) var unseenCount: Int = 0

    /// Whether there are more items or not when paginating forwards
    public private(set) var hasNextPage = true

    private let logger: Logger
    private var nextPage: Int = 1

    init(predicate: StorePredicate,
         userQuery: UserQuery,
         fetchStorePageInteractor: FetchStorePageInteractor,
         actionNotificationInteractor: ActionNotificationInteractor,
         deleteNotificationInteractor: DeleteNotificationInteractor,
         logger: Logger) {
        self.predicate = predicate
        self.userQuery = userQuery
        self.fetchStorePageInteractor = fetchStorePageInteractor
        self.actionNotificationInteractor = actionNotificationInteractor
        self.deleteNotificationInteractor = deleteNotificationInteractor
        self.logger = logger
    }

    private var contentObservers = NSHashTable<AnyObject>.weakObjects()
    private var countObservers = NSHashTable<AnyObject>.weakObjects()

    private func setTotalCount(_ value: Int, notifyObservers: Bool = false) {
        let oldValue = totalCount
        totalCount = value
        if oldValue != totalCount && notifyObservers {
            forEachCountObserver { $0.store(self, didChangeTotalCount: totalCount) }
        }
    }

    private func setUnreadCount(_ value: Int, notifyObservers: Bool = false) {
        let oldValue = unreadCount
        unreadCount = value
        if oldValue != unreadCount && notifyObservers {
            forEachCountObserver { $0.store(self, didChangeUnreadCount: unreadCount) }
        }
    }

    private func setUnseenCount(_ value: Int, notifyObservers: Bool = false) {
        let oldValue = unseenCount
        unseenCount = value
        if oldValue != unseenCount && notifyObservers {
            forEachCountObserver { $0.store(self, didChangeUnseenCount: unseenCount) }
        }
    }

    private func setHasNextPage(_ value: Bool) {
        let oldValue = hasNextPage
        hasNextPage = value
        if oldValue != hasNextPage {
            forEachContentObserver { $0.store(self, didChangeHasNextPage: hasNextPage) }
        }
    }

    /// Number of notifications loaded in the store
    public var count: Int {
        return notifications.count
    }

    public subscript(index: Int) -> Notification {
        return notifications[index]
    }

    // MARK: - Collection

    public var startIndex: Int { return notifications.startIndex }
    public var endIndex: Int { return notifications.endIndex }

    public func index(after i: Int) -> Int {
        return notifications.index(after: i)
    }

    // MARK: - Public Methods

    /// Add a content observer. Observers are stored in a HashTable with weak references.
    /// - Parameter observer: The observer
    public func addContentObserver(_ observer: NotificationStoreContentObserver) {
        contentObservers.add(observer)
    }

    /// Removes a content observer.
    /// - Parameter observer: The observer
    public func removeContentObserver(_ observer: NotificationStoreContentObserver) {
        contentObservers.remove(observer)
    }

    /// Add a count observer. Observers are stored in a HashTable with weak references.
    /// - Parameter observer: The observer
    public func addCountObserver(_ observer: NotificationStoreCountObserver) {
        countObservers.add(observer)
    }

    /// Removes a count observer.
    /// - Parameter observer: The observer
    public func removeCountObserver(_ observer: NotificationStoreCountObserver) {
        countObservers.remove(observer)
    }

    /// Clears the store and fetches first page.
    /// - Parameters:
    ///    - completion: Closure with a `Result<[Notification], Error>`
    public func refresh(completion: @escaping (Result<[Notification], Error>) -> Void = { _ in }) {
        let pagePredicate = StorePagePredicate(size: pageSize)
        fetchStorePageInteractor.execute(storePredicate: predicate, userQuery: userQuery, pagePredicate: pagePredicate)
            .then { storePage in
                self.clear(notifyChanges: false)
                self.configurePagination(storePage)
                self.configureCount(storePage)
                let newNotifications = storePage.notifications
                self.notifications.append(contentsOf: newNotifications)
                self.forEachContentObserver { $0.didReloadStore(self) }
                completion(.success(newNotifications))
            }.fail { error in
                completion(.failure(error))
            }
    }

    /// Fetches the next page of notificatinos. It can be called multiple times to obtain all pages.
    /// This method will notify the observers if changes are made into the store.
    /// - Parameters:
    ///    - completion: Closure with a `Result<[Notification], Error>`
    public func fetch(completion: @escaping (Result<[Notification], Error>) -> Void = { _ in }) {
        guard hasNextPage else {
            completion(.success([]))
            return
        }
        let pagePredicate: StorePagePredicate = StorePagePredicate(page: nextPage, size: pageSize)
        fetchStorePageInteractor.execute(storePredicate: predicate, userQuery: userQuery, pagePredicate: pagePredicate)
            .then { storePage in
                self.configurePagination(storePage)
                self.configureCount(storePage)

                let oldCount = self.notifications.count
                let newNotifications = storePage.notifications
                self.notifications.append(contentsOf: newNotifications)
                completion(.success(newNotifications))
                let indexes = Array(oldCount..<self.notifications.count)
                self.forEachContentObserver { $0.store(self, didInsertNotificationsAt: indexes) }
            }.fail { error in
                completion(.failure(error))
            }
    }

    /// Deletes a notification.
    /// Calling this method triggers the observers to get notified upon deletion.
    /// - Parameters:
    ///    - notification: The notification
    ///    - completion: Closure with a `Error`. Success if error is nil.
    public func delete(_ notification: Notification, completion: @escaping (Error?) -> Void) {
        deleteNotificationInteractor
            .execute(notificationId: notification.id, userQuery: userQuery)
            .then { _ in
                if let notificationIndex = self.notifications.firstIndex(where: { $0.id == notification.id }) {
                    self.updateCountersWhenDelete(notification: self.notifications[notificationIndex], predicate: self.predicate)
                    self.notifications.remove(at: notificationIndex)
                    self.forEachContentObserver { $0.store(self, didDeleteNotificationAt: [notificationIndex]) }
                    completion(nil)
                }
            }.fail { error in
                completion(error)
            }
    }

    /// Marks a notification as read.
    /// - Parameters:
    ///    - notification: The notification
    ///    - completion: Closure with a `Error`. Success if error is nil.
    public func markAsRead(_ notification: Notification, completion: @escaping (Result<Notification, Error>) -> Void) {
        executeNotificationAction(
            notification: notification,
            action: .markAsRead,
            modificationsBlock: { notification in
                self.markNotificationAsRead(&notification, with: self.predicate)
            },
            completion: completion)
    }

    /// Marks a notification as unread.
    /// - Parameters:
    ///    - notification: The notification
    ///    - completion: Closure with a `Error`. Success if error is nil.
    public func markAsUnread(_ notification: Notification, completion: @escaping (Result<Notification, Error>) -> Void) {
        executeNotificationAction(
            notification: notification,
            action: .markAsUnread,
            modificationsBlock: { notification in
                self.markNotificationAsUnread(&notification, with: self.predicate)
            },
            completion: completion)
    }

    /// Marks a notification as archived.
    /// - Parameters:
    ///    - notification: Notification will be marked as archived.
    ///    - completion: Closure with a `Error`. Success if error is nil.
    public func archive(_ notification: Notification, completion: @escaping (Result<Notification, Error>) -> Void) {
        executeNotificationAction(
            notification: notification,
            action: .archive,
            modificationsBlock: { notification in
                self.archiveNotification(&notification, with: self.predicate)
            },
            completion: completion)
    }

    /// Marks a notification as unarchived.
    /// - Parameters:
    ///    - notification: Notification will be marked as unarchived.
    ///    - completion: Closure with a `Error`. Success if error is nil.
    public func unarchive(_ notification: Notification, completion: @escaping (Result<Notification, Error>) -> Void) {
        executeNotificationAction(
            notification: notification,
            action: .unarchive,
            modificationsBlock: { $0.archivedAt = nil },
            completion: completion)
    }

    /// Marks all notifications as read.
    /// - Parameters:
    ///    - completion: Closure with a `Error`. Success if error is nil.
    public func markAllRead(completion: @escaping (Error?) -> Void) {
        executeAllNotificationsAction(
            action: .markAllAsRead,
            modificationsBlock: { notification in
                self.markNotificationAsRead(&notification, with: self.predicate)
            },
            completion: completion)
    }

    /// Marks all notifications as seen.
    /// - Parameters:
    ///    - completion: Closure with a `Error`. Success if error is nil.
    public func markAllSeen(completion: @escaping (Error?) -> Void) {
        executeAllNotificationsAction(
            action: .markAllAsSeen,
            modificationsBlock: {
                if $0.seenAt == nil {
                    $0.seenAt = Date()
                    self.setUnseenCount(self.unseenCount - 1, notifyObservers: true)
                }
            },
            completion: completion)
    }

    // MARK: - Private Methods

    func clear(notifyChanges: Bool) {
        let notificationCount = count
        notifications = []
        setTotalCount(0, notifyObservers: notifyChanges)
        setUnreadCount(0, notifyObservers: notifyChanges)
        setUnseenCount(0, notifyObservers: notifyChanges)
        nextPage = 1
        setHasNextPage(true)

        if notifyChanges {
            forEachContentObserver { $0.store(self, didDeleteNotificationAt: Array(0..<notificationCount)) }
        }
    }

    private func executeNotificationAction(
        notification: Notification,
        action: NotificationActionQuery.Action,
        modificationsBlock: @escaping (inout Notification) -> Void,
        completion: @escaping (Result<Notification, Error>) -> Void
    ) {
        actionNotificationInteractor
            .execute(action: action, userQuery: userQuery, notificationId: notification.id)
            .then { _ in
                if let notificationIndex = self.notifications.firstIndex(where: { $0.id == notification.id }) {
                    modificationsBlock(&self.notifications[notificationIndex])
                    completion(.success(self.notifications[notificationIndex]))
                } else {
                    completion(.failure(MagicBellError("Notification not found in store")))
                }
            }.fail { error in
                completion(.failure(error))
            }
    }

    private func executeAllNotificationsAction(
        action: NotificationActionQuery.Action,
        modificationsBlock: @escaping (inout Notification) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        actionNotificationInteractor
            .execute(action: action, userQuery: userQuery, notificationId: nil)
            .then { _ in
                for i in self.notifications.indices {
                    modificationsBlock(&self.notifications[i])
                }
                completion(nil)
            }.fail { error in
                completion(error)
            }
    }

    private func configurePagination(_ page: StorePage) {
        nextPage = page.currentPage + 1
        setHasNextPage(page.currentPage < page.totalPages)
    }

    private func configureCount(_ page: StorePage) {
        setTotalCount(page.totalCount, notifyObservers: true)
        setUnreadCount(page.unreadCount, notifyObservers: true)
        setUnseenCount(page.unseenCount, notifyObservers: true)
    }

    private func refreshAndNotifyObservers() {
        refresh { _ in }
    }

    // MARK: - Observer methods
    func notifyNewNotification(id: String) {
        /**
         If GraphQL allows us to query for notificationId, then we can query for the predicate + notificationID. If we obtain a result, it means that this new notification is part of this store. Then, we set the notification in the first position of the array + set the new cursor as the newest one.

         Now, we just refresh all the store.
         */
        refreshAndNotifyObservers()
    }

    func notifyDeleteNotification(id: String) {
        if let storeIndex = notifications.firstIndex(where: { $0.id == id }) {
            updateCountersWhenDelete(notification: notifications[storeIndex], predicate: self.predicate)
            notifications.remove(at: storeIndex)
            forEachContentObserver { $0.store(self, didDeleteNotificationAt: [storeIndex]) }
        }
    }

    func notifyNotificationChange(id: String, change: StoreRealTimeNotificationChange) {
        if let storeIndex = notifications.firstIndex(where: { $0.id == id }) {
            // If exist
            var notification = notifications[storeIndex]
            switch change {
            case .read:
                markNotificationAsRead(&notification, with: self.predicate)
            case .unread:
                markNotificationAsUnread(&notification, with: self.predicate)
            case .archive:
                archiveNotification(&notification, with: self.predicate)
            }

            if predicate.match(notification) {
                notifications[storeIndex] = notification
                self.forEachContentObserver { $0.store(self, didChangeNotificationAt: [storeIndex]) }
            } else {
                notifications.remove(at: storeIndex)
                self.forEachContentObserver { $0.store(self, didDeleteNotificationAt: [storeIndex]) }
            }
        } else {
            /**
             If GraphQL allows us to query for notificationId, then we can query for the predicate + notificationID. If we obtain a result, it means that this new notification is part of this store. If not, we can remove it from the current store.

             The next step would be to place it in the correct position. we check the range from the newest to the oldest one. if it's older than the oldest one, we don't add it to the store yet. if it's the newest one, we place in the first position and update the newest cursor.

             Now, we just refresh the store with the predicate.
             */
            refreshAndNotifyObservers()
        }
    }

    func notifyAllNotificationRead() {
        if let read = predicate.read, read == false {
            clear(notifyChanges: true)
        } else {
            refreshAndNotifyObservers()
        }
    }

    func notifyAllNotificationSeen() {
        if let seen = predicate.seen, seen == false {
            clear(notifyChanges: true)
        } else {
            refreshAndNotifyObservers()
        }
    }

    func notifyReloadStore() {
        refreshAndNotifyObservers()
    }

    // MARK: - Notification modification function

    private func markNotificationAsRead( _ notification: inout Notification, with predicate: StorePredicate) {
        if notification.seenAt == nil {
            setUnseenCount(unseenCount - 1, notifyObservers: true)
        }

        if notification.readAt == nil {
            setUnreadCount(unreadCount - 1, notifyObservers: true)
            if let read = predicate.read {
                if read {
                    setTotalCount(totalCount + 1, notifyObservers: true)
                } else {
                    setTotalCount(totalCount - 1, notifyObservers: true)
                }
            }
        }

        let now = Date()
        notification.readAt = now
        notification.seenAt = now
    }

    private func markNotificationAsUnread(_ notification: inout Notification, with predicate: StorePredicate) {
        if notification.readAt != nil {
            // When a predicate is read, unread count is always 0
            if let read = predicate.read {
                if read {
                    setTotalCount(totalCount - 1, notifyObservers: true)
                    setUnreadCount(0, notifyObservers: true)
                } else {
                    setTotalCount(totalCount + 1, notifyObservers: true)
                    setUnreadCount(unreadCount + 1, notifyObservers: true)
                }
            } else {
                setUnreadCount(unreadCount + 1, notifyObservers: true)
            }
        }

        notification.readAt = nil
    }

    private func archiveNotification(_ notification: inout Notification, with predicate: StorePredicate) {
        guard notification.archivedAt == nil else { return }
        
        if notification.seenAt == nil {
            setUnseenCount(unseenCount - 1, notifyObservers: true)
        }

        if notification.readAt == nil {
            setUnreadCount(unreadCount - 1, notifyObservers: true)
        }

        if notification.archivedAt == nil {
            if predicate.archived {
                // Nothing to do
            } else {
                setTotalCount(totalCount - 1, notifyObservers: true)
            }
        }
        notification.archivedAt = Date()
    }

    // MARK: - Notification store observer methods

    private func forEachContentObserver(action: (NotificationStoreContentObserver) -> Void) {
        contentObservers.allObjects.forEach {
            if let contentDelegate = $0 as? NotificationStoreContentObserver {
                action(contentDelegate)
            }
        }
    }

    private func forEachCountObserver(action: (NotificationStoreCountObserver) -> Void) {
        countObservers.allObjects.forEach {
            if let countDelegate = $0 as? NotificationStoreCountObserver {
                action(countDelegate)
            }
        }
    }

    // MARK: - Counter methods

    private func updateCountersWhenDelete(notification: Notification, predicate: StorePredicate) {
        setTotalCount(totalCount - 1, notifyObservers: true)

        decreaseUnreadCountIfUnreadPredicate(predicate, notification)
        decreaseUnseenCountIfNotificationWasUnseen(notification)
    }
    
    private func decreaseUnreadCountIfUnreadPredicate(_ predicate: StorePredicate, _ notification: Notification) {
        if predicate.read == false {
            setUnreadCount(unreadCount - 1, notifyObservers: true)
        } else if predicate.read == nil {
            if notification.readAt == nil {
                setUnreadCount(unreadCount - 1, notifyObservers: true)
            }
        }
    }

    private func decreaseUnseenCountIfNotificationWasUnseen(_ notification: Notification) {
        if notification.seenAt == nil {
            setUnseenCount(unseenCount - 1, notifyObservers: true)
        }
    }
}
