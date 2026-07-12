enum Site { narou, kakuyomu }

extension SiteX on Site {
  String get displayName {
    switch (this) {
      case Site.narou:
        return 'なろう';
      case Site.kakuyomu:
        return 'カクヨム';
    }
  }
}
