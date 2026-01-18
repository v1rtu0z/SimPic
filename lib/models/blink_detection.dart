enum EyeState {
  open,
  closed,
  notDetected,
}

class BlinkDetectionResult {
  final EyeState leftEye;
  final EyeState rightEye;
  final double? leftOpenProbability;
  final double? rightOpenProbability;

  const BlinkDetectionResult({
    required this.leftEye,
    required this.rightEye,
    this.leftOpenProbability,
    this.rightOpenProbability,
  });

  bool get bothEyesOpen => leftEye == EyeState.open && rightEye == EyeState.open;
  bool get eitherEyeClosed => leftEye == EyeState.closed || rightEye == EyeState.closed;
  
  bool get canShoot => bothEyesOpen || (leftEye == EyeState.notDetected && rightEye == EyeState.notDetected);

  String get message {
    if (eitherEyeClosed) return "Wait - eyes closed";
    return "";
  }
}

BlinkDetectionResult evaluateBlink(double? leftProb, double? rightProb) {
  const threshold = 0.8;

  EyeState getState(double? prob) {
    if (prob == null) return EyeState.notDetected;
    return prob > threshold ? EyeState.open : EyeState.closed;
  }

  return BlinkDetectionResult(
    leftEye: getState(leftProb),
    rightEye: getState(rightProb),
    leftOpenProbability: leftProb,
    rightOpenProbability: rightProb,
  );
}
