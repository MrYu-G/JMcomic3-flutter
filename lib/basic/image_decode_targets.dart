const _decodeTargetBuckets = <int>[256, 512, 768, 1024, 1536, 2048, 3072, 4096];

int? normalizeImageDecodeTarget(int? value) {
  if (value == null || value <= 0) {
    return null;
  }
  for (final bucket in _decodeTargetBuckets) {
    if (value <= bucket) {
      return bucket;
    }
  }
  // Never let a caller create an unbounded image-cache key or request a
  // decoder target larger than the largest supported profile.
  return _decodeTargetBuckets.last;
}

int? imageDecodeTargetExtent(double? logicalExtent, double devicePixelRatio) {
  if (logicalExtent == null ||
      !logicalExtent.isFinite ||
      logicalExtent <= 0 ||
      !devicePixelRatio.isFinite ||
      devicePixelRatio <= 0) {
    return null;
  }
  final value = (logicalExtent * devicePixelRatio).round();
  if (value <= 0) return null;
  // Keep the codec/cache key space bounded.  The source file remains the
  // canonical (fully decoded/decrypted) image; this only controls Flutter's
  // codec sampling target and therefore cannot affect decryption semantics.
  return normalizeImageDecodeTarget(value);
}
