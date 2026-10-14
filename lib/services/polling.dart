import 'dart:async';
import 'package:flutter/foundation.dart';

/// Fires whenever the app writes something through the backend, so every
/// open [pollingStream] refetches right away instead of waiting for its
/// next tick -- e.g. a recruiter changing a status sees their own Pipeline
/// update instantly, and a sent chat message shows up without a delay.
class DataRefresh extends ChangeNotifier {
  DataRefresh._();
  static final DataRefresh instance = DataRefresh._();

  void bump() => notifyListeners();
}

/// Turns a one-shot REST [fetch] into a live-ish [Stream]: emits once on
/// listen, again every [interval], and immediately after any
/// [DataRefresh.bump]. Stops as soon as the listener cancels. Lets screens
/// that use `StreamBuilder` stay live on top of the plain REST API.
Stream<T> pollingStream<T>(
  Future<T> Function() fetch, {
  Duration interval = const Duration(seconds: 5),
}) {
  late StreamController<T> controller;
  Timer? timer;
  var fetching = false;
  var closed = false;

  Future<void> run() async {
    if (fetching || closed) return;
    fetching = true;
    try {
      final value = await fetch();
      if (!closed) controller.add(value);
    } catch (e, stackTrace) {
      if (!closed) controller.addError(e, stackTrace);
    } finally {
      fetching = false;
    }
  }

  void onBump() => run();

  controller = StreamController<T>(
    onListen: () {
      run();
      timer = Timer.periodic(interval, (_) => run());
      DataRefresh.instance.addListener(onBump);
    },
    onCancel: () {
      closed = true;
      timer?.cancel();
      DataRefresh.instance.removeListener(onBump);
    },
  );
  return controller.stream;
}
