# Changelog for Hedis

## 0.3.2 -> 0.4.1

* The following commands got a 'Maybe' added to their return type, to
  properly handle Redis returning `nil`-replies: `brpoplpush`, `lindex`, `lpop`,
  `objectEncoding`, `randomkey`, `rpop`, `rpoplpush`, `spop`, `srandmember`,
  `zrank`, `zrevrank`, `zscore`.

* Updated dependencies on `bytestring-lexing` and `stm`.

* Minor improvements and fixes to the documentation.
