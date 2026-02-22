/// Tool risk level for approval decisions.
///
/// - readOnly: does not modify user data
/// - write: creates/updates user data
/// - destructive: delete/overwrite/bulk changes, or untrusted external execution
enum AiToolRiskLevel {
  readOnly,
  write,
  destructive,
}
