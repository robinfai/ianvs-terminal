part of 'command_blocks_view.dart';

/// Only this label ticks: output, selection and timeline layout keep their state.
/// Native shell markers use the client's Unix milliseconds, including over SSH.
class _CommandBlockElapsed extends StatefulWidget {
  const _CommandBlockElapsed({
    required this.block,
    required this.style,
    required this.chinese,
  });

  final CommandBlock block;
  final TextStyle style;
  final bool chinese;

  @override
  State<_CommandBlockElapsed> createState() => _CommandBlockElapsedState();
}

class _CommandBlockElapsedState extends State<_CommandBlockElapsed>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _now = DateTime.now().millisecondsSinceEpoch;
  bool _visible = true;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _resetTimer();
  }

  @override
  void didUpdateWidget(_CommandBlockElapsed oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.block;
    final after = widget.block;
    if (before.id != after.id ||
        before.startedAt != after.startedAt ||
        before.finishedAt != after.finishedAt ||
        before.running != after.running) {
      _resetTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    setState(_resetTimer);
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = null;
    _now = DateTime.now().millisecondsSinceEpoch;
    final block = widget.block;
    if (_visible &&
        _foreground &&
        block.running &&
        block.startedAt != null &&
        block.finishedAt == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _now = DateTime.now().millisecondsSinceEpoch);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _format(int milliseconds) {
    if (!widget.block.running && milliseconds < 60000) {
      return milliseconds < 1000
          ? '${milliseconds}ms'
          : '${(milliseconds / 1000).toStringAsFixed(1)}s';
    }
    final seconds = milliseconds ~/ 1000;
    final hours = seconds ~/ 3600;
    final minutes = seconds ~/ 60 % 60;
    final remainder = seconds % 60;
    if (widget.chinese) {
      return '${hours > 0 ? '$hours时' : ''}'
          '${seconds >= 60 ? '$minutes分' : ''}$remainder秒';
    }
    return '${hours > 0 ? '${hours}h ' : ''}'
        '${seconds >= 60 ? '${minutes}m ' : ''}${remainder}s';
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final elapsed =
        block.durationMs ??
        (block.running && block.startedAt != null
            ? (_now - block.startedAt!).clamp(0, 1 << 53)
            : null);
    if (elapsed == null) return const SizedBox.shrink();
    final value = _format(elapsed);
    return Semantics(
      // Elapsed changes must not announce over the AI's phase transitions.
      container: true,
      label: widget.chinese ? '命令耗时 $value' : 'Command elapsed $value',
      excludeSemantics: true,
      child: Text(
        value,
        key: ValueKey('block-elapsed-${block.id}'),
        maxLines: 1,
        style: widget.style,
      ),
    );
  }
}
