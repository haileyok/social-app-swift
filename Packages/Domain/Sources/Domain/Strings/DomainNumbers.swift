import Foundation

/// Port of `src/lib/numbers.ts`.
public enum DomainNumbers {

  /// Clamps `v` into `[min, max]`.
  public static func clamp(_ v: Double, _ min: Double, _ max: Double) -> Double {
    Swift.min(max, Swift.max(min, v))
  }

  /// Integer overload of ``clamp(_:_:_:)``.
  public static func clamp(_ v: Int, _ min: Int, _ max: Int) -> Int {
    Swift.min(max, Swift.max(min, v))
  }
}
