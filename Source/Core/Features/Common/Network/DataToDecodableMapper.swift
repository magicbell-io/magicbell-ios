//
//  DataToDecodableMapper.swift
//  MagicBell
//
//  Created by Javi on 17/11/21.
//

import Foundation
import Harmony

public class DataToDecodableMapper<T>: Mapper<Data, T> where T: Decodable {

    private let decoder = JSONDecoder()

    public override func map(_ from: Data) throws -> T {
        do {
            #if DEBUG
            print(String(data: from, encoding: .utf8) ?? "Cannot print data")
            #endif
            let value = try decoder.decode(T.self, from: from)
            return value
        } catch {
            #if DEBUG
            switch error {
            case let decodingError as DecodingError:
                switch decodingError {
                case .dataCorrupted(let context):
                    print(context)
                case .keyNotFound(let key, let context):
                    print("Key '\(key)' not found:", context.debugDescription)
                    print("codingPath:", context.codingPath)
                case .valueNotFound(let value, let context):
                    print("Value '\(value)' not found:", context.debugDescription)
                    print("codingPath:", context.codingPath)
                case .typeMismatch(let type, let context):
                    print("Type '\(type)' mismatch:", context.debugDescription)
                    print("codingPath:", context.codingPath)
                @unknown default:
                    print(error)
                }
            default:
                print("error: ", error)
            }
            #endif

            throw MappingError<T>(error)
        }
    }
}
