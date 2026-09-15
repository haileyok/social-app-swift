import Domain
import Foundation
import LoginLogic

/**
 One-line rendering of a login failure's underlying XRPC answer, for the login
 screen's temporary diagnostic caption.

 The mapper's user-facing copy intentionally hides server detail; this shows
 it verbatim (status, error code, message) so a failing sign-in identifies
 *which host answered and what it said* in one glance.
 */
extension LoginError {

  /** The raw server answer, or nil when the failure had no XRPC detail. */
  var appDebugDetail: String? {
    switch self {
    case .incorrectCredentials(let underlying):
      return detail(underlying, label: "credentials rejected")
    case .authFactorRequired(let underlying):
      return detail(underlying, label: "2FA required")
    case .invalidAuthFactorToken(let underlying):
      return detail(underlying, label: "2FA token invalid")
    case .rateLimited(let underlying, let retryAfter):
      return detail(underlying, label: "rate limited (retry \(retryAfter.map(String.init) ?? "?")s)")
    case .networkOffline(let underlying):
      return detail(underlying, label: "network offline")
    case .appPasswordNotAllowed(let underlying):
      return detail(underlying, label: "app password not allowed")
    case .unexpected(let value):
      return detail(value.underlying, label: "unexpected (\(value.message))")
    }
  }

  private func detail(_ shape: XRPCErrorShape?, label: String) -> String {
    guard let shape else {
      return "login failed: \(label) (no xrpc detail)"
    }
    return
      "login failed: \(label) | status=\(shape.status.map(String.init) ?? "-") error=\(shape.error ?? "-") message=\(shape.message)"
  }
}
