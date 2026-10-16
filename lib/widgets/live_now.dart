import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds [builder] with the current time at the start of every minute,
/// so lock-screen clocks stay correct.
class LiveNow extends StatefulWidget {
  const LiveNow({super.key, required this.builder});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<LiveNow> createState() => _LiveNowState();
}

class _LiveNowState extends State<LiveNow> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  void _scheduleTick() {
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(nextMinute.difference(now), () {
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
