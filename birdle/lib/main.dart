import 'package:flutter/material.dart';

import 'game.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WordBank.load();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Birdle',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121213),
      ),
      home: const GamePage(),
    );
  }
}

/// Цвета Birdle.
class WordleColors {
  static const correct = Color(0xFF6AAA64);   // зелёный — буква на месте
  static const present = Color(0xFFC9B458);   // жёлтый — буква есть, но не там
  static const absent = Color(0xFFB0B0B0);    // светло-серый — буквы нет в слове
  static const empty = Color(0xFF3A3A3C);     // тёмно-серый — пустая клетка
  static const border = Color(0xFF565758);    // рамка заполненной клетки
  static const keyIdle = Color(0xFF3A3A3C);   // тёмно-серый — ненажатая клавиша
  static const text = Colors.white;
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final Game _game = Game();

  /// Текущий ввод пользователя (0..5 букв).
  String _currentInput = '';

  /// Состояние клавиш: буква -> цвет (HitType).
  final Map<String, HitType> _keyStates = {};

  bool get _roundLocked => _game.didWin || _game.didLose;

  /// Русская раскладка ЙЦУКЕН (3 ряда).
  static const _rows = [
    ['й', 'ц', 'у', 'к', 'е', 'н', 'г', 'ш', 'щ', 'з', 'х', 'ъ'],
    ['ф', 'ы', 'в', 'а', 'п', 'р', 'о', 'л', 'д', 'ж', 'э'],
    ['ENTER', 'я', 'ч', 'с', 'м', 'и', 'т', 'ь', 'б', 'ю', 'ё', '⌫'],
  ];

  void _onLetter(String letter) {
    if (_roundLocked) return;
    if (_currentInput.length >= 5) return;
    setState(() => _currentInput += letter);
  }

  void _onBackspace() {
    if (_roundLocked) return;
    if (_currentInput.isEmpty) return;
    setState(() =>
        _currentInput = _currentInput.substring(0, _currentInput.length - 1));
  }

  void _onEnter() {
    if (_roundLocked) {
      _showMessage('Раунд завершён. Нажмите «Новый раунд».');
      return;
    }
    if (_currentInput.length != 5) {
      _showMessage('Слово должно состоять из 5 букв.');
      return;
    }
    if (!_game.isLegalGuess(_currentInput)) {
      _showMessage('Такого слова нет в словаре.');
      return;
    }

    setState(() {
      final result = _game.guess(_currentInput);

      // Обновляем цвета клавиш: приоритет — hit > partial > miss.
      for (final letter in result) {
        final current = _keyStates[letter.char];
        if (letter.type == HitType.hit ||
            (letter.type == HitType.partial && current != HitType.hit) ||
            (letter.type == HitType.miss && current == null)) {
          _keyStates[letter.char] = letter.type;
        }
      }

      _currentInput = '';

      if (_game.didWin) {
        _showMessage(
            'Победа! Слово: ${_game.hiddenWord.toString().toUpperCase()}',
            success: true);
      } else if (_game.didLose) {
        _showMessage(
            'Попытки закончились. Слово: ${_game.hiddenWord.toString().toUpperCase()}',
            success: false);
      }
    });
  }

  void _resetGame() {
    setState(() {
      _game.resetGame();
      _currentInput = '';
      _keyStates.clear();
    });
  }

  void _showMessage(String text, {bool? success}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white)),
        backgroundColor: success == null
            ? WordleColors.empty
            : (success ? WordleColors.correct : WordleColors.present),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, color: WordleColors.border),
            Expanded(child: _buildBoard()),
            _buildKeyboard(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Spacer(),
          const Text(
            'BIRDLE',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _resetGame,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Новый раунд',
          ),
        ],
      ),
    );
  }

    Widget _buildBoard() {
    return Expanded(
      child: LayoutBuilder(builder: (context, constraints) {
        const rows = Game.defaultMaxGuesses;
        const gap = 4.0;
        // Квадратные клетки: размер = минимум из доступной ширины/высоты.
        final byWidth = (constraints.maxWidth - gap * 6) / 5;
        final byHeight = (constraints.maxHeight - gap * (rows + 1)) / rows;
        final tileSize = byWidth < byHeight ? byWidth : byHeight;

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(rows, (rowIndex) {
              final guess = _game.guesses[rowIndex];
              final isActiveRow =
                  rowIndex == _game.activeIndex && !_roundLocked;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: gap / 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (colIndex) {
                    final letter = guess[colIndex];
                    String char;
                    HitType type;
                    if (guess.isEmpty && isActiveRow) {
                      char = colIndex < _currentInput.length
                          ? _currentInput[colIndex]
                          : '';
                      type = HitType.none;
                    } else {
                      char = letter.char;
                      type = letter.type;
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: gap / 2),
                      child: Tile(
                        char: char,
                        type: type,
                        size: tileSize,
                        isActive: isActiveRow &&
                            colIndex == _currentInput.length,
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildKeyboard() {
    return LayoutBuilder(builder: (context, constraints) {
      // Доступная ширина минус внешние отступы (4+4).
      final availableWidth = constraints.maxWidth - 8;
      // ~4px зазор между клавишами.
      const keyGap = 4.0;
      const outerPad = 2.0;

      // Максимальное число клавиш в ряду — 12 (нижний ряд).
      // Считаем ширину клавиши от этого ряда, чтобы все ряды были одной высоты.
      const maxKeysInRow = 12;
      // В нижнем ряду две широкие клавиши (ENTER/⌫) — считаем их за 1.6 обычной.
      const actionWeight = 1.6;
      // Нижний ряд: 10 обычных + 2 «широких» = 10 + 2*1.6 = 13.2 «единиц».
      // Но чтобы не гадать — считаем по фактическому числу клавиш с учётом весов.
      double totalWeightForRow(List<String> row) {
        double w = 0;
        for (final key in row) {
          w += (key == 'ENTER' || key == '⌫') ? actionWeight : 1.0;
        }
        return w;
      }

      final baseRow = _rows[2]; // самый длинный ряд
      final totalWeight = totalWeightForRow(baseRow);
      final gapsWidth = keyGap * (baseRow.length - 1) + outerPad * 2;
      final unitWidth = (availableWidth - gapsWidth) / totalWeight;

      // Высота клавиши: ограничим, чтобы на маленьких экранах не съедало доску.
      final keyHeight = (unitWidth * 1.5).clamp(38.0, 52.0);

      Widget keyWidget(String key) {
        final isAction = key == 'ENTER' || key == '⌫';
        final hitType = _keyStates[key] ?? HitType.none;
        final color = _keyColor(hitType);
        final textColor =
            hitType == HitType.miss ? Colors.black87 : Colors.white;
        final weight = isAction ? actionWeight : 1.0;
        final width = unitWidth * weight;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: keyGap / 2),
          child: SizedBox(
            width: width,
            height: keyHeight,
            child: Material(
              color: color,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  if (key == 'ENTER') {
                    _onEnter();
                  } else if (key == '⌫') {
                    _onBackspace();
                  } else {
                    _onLetter(key);
                  }
                },
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        key == '⌫' ? '⌫' : key.toUpperCase(),
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: isAction ? 12 : 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return Container(
        padding: EdgeInsets.fromLTRB(outerPad, 6, outerPad, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _rows.map((row) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: row.map(keyWidget).toList(),
              ),
            );
          }).toList(),
        ),
      );
    });
  }

  Color _keyColor(HitType type) {
    switch (type) {
      case HitType.hit:
        return WordleColors.correct;
      case HitType.partial:
        return WordleColors.present;
      case HitType.miss:
        return WordleColors.absent;    // светло-серый
      case HitType.none:
        return WordleColors.keyIdle;   // тёмно-серый
    }
  }
}

class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.char,
    required this.type,
    required this.size,
    this.isActive = false,
  });

  final String char;
  final HitType type;
  final double size;
  final bool isActive;

  Color _fillColor() {
    switch (type) {
      case HitType.hit:
        return WordleColors.correct;
      case HitType.partial:
        return WordleColors.present;
      case HitType.miss:
        return WordleColors.absent;    // светло-серый
      case HitType.none:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filled = char.isNotEmpty;
    final filledEmpty = filled && type == HitType.none;
    // На светло-сером фоне (miss) — тёмный текст, иначе белый.
    final textColor = type == HitType.miss ? Colors.black87 : Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _fillColor(),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: filledEmpty
              ? WordleColors.border
              : (isActive ? Colors.white54 : WordleColors.empty),
          width: filledEmpty ? 2 : 1.5,
        ),
      ),
      child: Text(
        char.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}