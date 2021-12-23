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

protocol ActionNotificationInteractor {
    func execute(
        action: NotificationActionQuery.Action,
        userQuery: UserQuery,
        notificationId: String?
    ) -> Future<Void>
}

struct ActionNotificationDefaultInteractor: ActionNotificationInteractor {
    private let executor: Executor
    private let actionInteractor: Interactor.PutByQuery<Void>

    init(executor: Executor,
         actionInteractor: Interactor.PutByQuery<Void>) {
        self.executor = executor
        self.actionInteractor = actionInteractor
    }

    func execute(action: NotificationActionQuery.Action,
                 userQuery: UserQuery,
                 notificationId: String? = nil) -> Future<Void> {
        return executor.submit {
            let query = NotificationActionQuery(action: action, notificationId: notificationId ?? "", userQuery: userQuery)
            try actionInteractor.execute(nil, query: query, in: DirectExecutor()).result.get()
        }
    }
}
