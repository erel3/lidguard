import Foundation
import os.log

enum NetworkRetry {
  static func send(
    request: URLRequest,
    session: URLSession = .shared,
    retries: Int = 3,
    delay: TimeInterval = 2.0,
    logger: Logger,
    logCategory: LogCategory,
    completion: (@Sendable (Bool) -> Void)? = nil
  ) {
    session.dataTask(with: request) { _, response, error in
      if let error = error {
        logger.error("Send failed: \(error.localizedDescription)")
        ActivityLog.logAsync(logCategory, "Send failed: \(error.localizedDescription)")
        if retries > 0 {
          logger.info("Retrying... (\(retries) attempts left)")
          DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            send(request: request, session: session, retries: retries - 1,
                 delay: delay, logger: logger, logCategory: logCategory, completion: completion)
          }
          return
        }
        completion?(false)
        return
      } else if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
        logger.error("HTTP error: \(httpResponse.statusCode)")
        ActivityLog.logAsync(logCategory, "HTTP error: \(httpResponse.statusCode)")
        if retries > 0 {
          logger.info("Retrying... (\(retries) attempts left)")
          DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            send(request: request, session: session, retries: retries - 1,
                 delay: delay, logger: logger, logCategory: logCategory, completion: completion)
          }
          return
        }
        completion?(false)
        return
      }
      logger.debug("Sent")
      ActivityLog.logAsync(logCategory, "Sent")
      completion?(true)
    }.resume()
  }
}
