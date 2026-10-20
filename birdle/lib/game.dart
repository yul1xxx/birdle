/// Game logic and supporting types for Birdle,
/// a five-letter word-guessing game similar to Wordle.
library;

import 'dart:collection';
import 'dart:math';

import 'package:flutter/services.dart';

/// The result of evaluating a [Letter] of a guess against the hidden word.
enum HitType { none, hit, partial, miss }

/// A single character paired with its [HitType] against the hidden word.
typedef Letter = ({String char, HitType type});

/// Fallback dictionary used before the CSV list is loaded.
const List<String> _fallbackWords = [
  'добро', 'щетка', 'тропа', 'хомут', 'купон',
  'кумир', 'геоид', 'занос', 'триод', 'изъян',
];

class WordBank {
  static List<String> _words = List<String>.from(_fallbackWords);

  static List<String> get allWords => List.unmodifiable(_words);

  static Future<void> load() async {
    try {
      final raw = await rootBundle.loadString('words.csv');
      final loadedWords = raw
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim().toLowerCase())
          .where((word) =>
              word.length == 5 && RegExp(r'^[а-яё]+$').hasMatch(word))
          .toSet()
          .toList()
        ..sort();

      if (loadedWords.isNotEmpty) {
        _words = loadedWords;
      }
    } catch (_) {
      _words = List<String>.from(_fallbackWords);
    }
  }

  static bool contains(String word) =>
      _words.contains(word.trim().toLowerCase());
}

/// Game state of a single round of Birdle.
class Game {
  static const int defaultMaxGuesses = 5;

  Game({this.maxGuesses = defaultMaxGuesses, this.seed})
      : _wordToGuess = _generateInitialWord(seed),
        _guesses = List<Word>.filled(maxGuesses, Word.empty());

  final int maxGuesses;
  final int? seed;

  Word _wordToGuess;
  List<Word> _guesses;

  Word get hiddenWord => _wordToGuess;

  UnmodifiableListView<Word> get guesses => UnmodifiableListView(_guesses);

  Word get previousGuess {
    final index = _guesses.lastIndexWhere((word) => word.isNotEmpty);
    return index == -1 ? Word.empty() : _guesses[index];
  }

  int get activeIndex => _guesses.indexWhere((word) => word.isEmpty);

  int get guessesRemaining {
    if (activeIndex == -1) return 0;
    return maxGuesses - activeIndex;
  }

  bool get didWin {
    if (_guesses.first.isEmpty) return false;
    for (final letter in previousGuess) {
      if (letter.type != HitType.hit) return false;
    }
    return true;
  }

  bool get didLose => guessesRemaining == 0 && !didWin;

  void resetGame() {
    _wordToGuess = _generateInitialWord(seed);
    _guesses = List<Word>.filled(maxGuesses, Word.empty());
  }

  Word guess(String guess) {
    final result = matchGuessOnly(guess);
    addGuessToList(result);
    return result;
  }

  bool isLegalGuess(String guess) => Word.fromString(guess).isLegalGuess;

  Word matchGuessOnly(String guess) =>
      Word.fromString(guess).evaluateGuess(_wordToGuess);

  void addGuessToList(Word guess) {
    final guessIndex = activeIndex;
    if (guessIndex == -1) {
      throw StateError('No guesses remaining.');
    }
    _guesses[guessIndex] = guess;
  }

  static Word _generateInitialWord(int? seed) =>
      seed == null ? Word.random() : Word.fromSeed(seed);
}

/// A five-letter word made up of [Letter]s, each tracking its [HitType].
class Word with IterableMixin<Letter> {
  Word(this._letters);

  factory Word.empty() =>
      Word(List<Letter>.filled(5, (char: '', type: HitType.none)));

  factory Word.fromString(String guess) {
    if (guess.length != 5) {
      throw ArgumentError.value(
          guess, 'guess', 'Must be exactly 5 characters long.');
    }
    final letters = guess
        .toLowerCase()
        .split('')
        .map((char) => (char: char, type: HitType.none))
        .toList();
    return Word(letters);
  }

  factory Word.random() {
    final random = Random();
    final words = WordBank.allWords;
    return Word.fromString(words[random.nextInt(words.length)]);
  }

  factory Word.fromSeed(int seed) {
    final words = WordBank.allWords;
    return Word.fromString(words[seed % words.length]);
  }

  final List<Letter> _letters;

  @override
  Iterator<Letter> get iterator => _letters.iterator;

  @override
  bool get isEmpty => every((letter) => letter.char.isEmpty);

  @override
  int get length => _letters.length;

  Letter operator [](int i) => _letters[i];

  @override
  String toString() => _letters.map((letter) => letter.char).join().trim();

  String toStringVerbose() => _letters
      .map((letter) => '${letter.char} - ${letter.type.name}')
      .join('\n');
}

extension WordUtils on Word {
  bool get isLegalGuess => WordBank.contains(toString());

  Word evaluateGuess(Word hiddenWord) {
    final result = List<Letter>.filled(length, (char: '', type: HitType.none));
    final unmatchedHiddenLetterCounts = <String, int>{};

    for (var i = 0; i < length; i++) {
      final guessChar = this[i].char;
      final hiddenChar = hiddenWord[i].char;
      if (guessChar == hiddenChar) {
        result[i] = (char: guessChar, type: HitType.hit);
      } else {
        unmatchedHiddenLetterCounts[hiddenChar] =
            (unmatchedHiddenLetterCounts[hiddenChar] ?? 0) + 1;
      }
    }

    for (var i = 0; i < length; i++) {
      if (result[i].type == HitType.hit) continue;
      final guessChar = this[i].char;
      final unmatchedCount = unmatchedHiddenLetterCounts[guessChar] ?? 0;
      final isPartial = unmatchedCount > 0;
      if (isPartial) {
        unmatchedHiddenLetterCounts[guessChar] = unmatchedCount - 1;
      }
      result[i] = (
        char: guessChar,
        type: isPartial ? HitType.partial : HitType.miss,
      );
    }

    return Word(result);
  }
}