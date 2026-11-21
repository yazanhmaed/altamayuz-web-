abstract class StocktakeState {}

class StocktakeInitial extends StocktakeState {}

/// Reading/parsing the picked file and loading live products.
class StocktakeParsing extends StocktakeState {}

/// [StocktakeCubit.analysis] is ready (or was re-computed after a choice).
class StocktakeReviewReady extends StocktakeState {}

class StocktakeApplying extends StocktakeState {
  final int done;
  final int total;
  StocktakeApplying(this.done, this.total);
}

/// Some or all products were applied; see [StocktakeCubit.lastResult].
class StocktakeApplied extends StocktakeState {}

class StocktakeError extends StocktakeState {
  final String message;
  StocktakeError(this.message);
}

class StocktakeHistoryLoading extends StocktakeState {}

class StocktakeHistoryLoaded extends StocktakeState {}

class StocktakeUndoDone extends StocktakeState {
  final String message;
  StocktakeUndoDone(this.message);
}
