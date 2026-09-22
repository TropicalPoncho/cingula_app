DateTime? dateFromSeconds(Object? s) =>
    s is int ? DateTime.fromMillisecondsSinceEpoch(s * 1000) : null;

int? secondsFromDate(DateTime? d) => d == null ? null : d.millisecondsSinceEpoch ~/ 1000;
