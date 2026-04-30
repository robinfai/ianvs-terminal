import 'local_shell_session_controller.dart';

enum TerminalPaneSplitDirection { right, down }

abstract class TerminalPaneNode {
  const TerminalPaneNode();

  int get paneCount;
  List<TerminalPaneLeaf> get leaves;
  bool containsPane(int paneId);
}

class TerminalPaneLeaf extends TerminalPaneNode {
  const TerminalPaneLeaf({required this.id, required this.shellController});

  final int id;
  final LocalShellSessionController shellController;

  @override
  int get paneCount => 1;

  @override
  List<TerminalPaneLeaf> get leaves => <TerminalPaneLeaf>[this];

  @override
  bool containsPane(int paneId) => id == paneId;
}

class TerminalPaneSplit extends TerminalPaneNode {
  TerminalPaneSplit({
    required this.direction,
    required this.first,
    required this.second,
    this.ratio = 0.5,
  }) : assert(ratio >= minRatio && ratio <= maxRatio);

  static const double minRatio = 0.2;
  static const double maxRatio = 0.8;

  final TerminalPaneSplitDirection direction;
  TerminalPaneNode first;
  TerminalPaneNode second;
  double ratio;

  void updateRatio(double value) {
    ratio = value.clamp(minRatio, maxRatio).toDouble();
  }

  @override
  int get paneCount => first.paneCount + second.paneCount;

  @override
  List<TerminalPaneLeaf> get leaves => <TerminalPaneLeaf>[
    ...first.leaves,
    ...second.leaves,
  ];

  @override
  bool containsPane(int paneId) =>
      first.containsPane(paneId) || second.containsPane(paneId);
}
