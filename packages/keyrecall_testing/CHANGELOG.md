# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog][1], and this package adheres to
[Semantic Versioning][2].

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/

## [Unreleased]

### Added

- `propertySeed`, `propertyBudget`, `failingOnErrors`, `weighted`, `optional`,
  and `choiceOf`, the property-testing conventions shared by the packages that
  use kiri_check.
- `Reached`, which checks after a property's last example that its generated
  examples reached every value they have to, and stands aside when the property
  itself failed.
