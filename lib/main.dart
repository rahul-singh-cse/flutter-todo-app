import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<int> colorNotifier = ValueNotifier(0);

const List<Color> seedColors = [
  Colors.green,
  Colors.blue,
  Colors.purple,
  Colors.orange,
  Colors.pink,
  Colors.teal,
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDark') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  final savedColor = prefs.getInt('colorIndex') ?? 0;
  colorNotifier.value =
      (savedColor >= 0 && savedColor < seedColors.length) ? savedColor : 0;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([themeNotifier, colorNotifier]),
      builder: (context, _) {
        final seed = seedColors[colorNotifier.value];
        return MaterialApp(
          title: 'To-Do App',
          debugShowCheckedModeBanner: false,
          themeMode: themeNotifier.value,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: seed),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            ),
          ),
          home: const TodoPage(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const List<String> priorityLabels = ['Low', 'Medium', 'High'];
const List<Color> priorityColors = [Colors.green, Colors.orange, Colors.red];

const List<String> categoryLabels = ['Kaam', 'Ghar', 'Padhai', 'Personal'];
const List<IconData> categoryIcons = [
  Icons.work,
  Icons.home,
  Icons.school,
  Icons.person,
];

const List<String> repeatLabels = [
  'Repeat nahi',
  'Roz',
  'Har hafte',
  'Har mahine',
];

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------
class SubTask {
  String title;
  bool done;

  SubTask(this.title, {this.done = false});

  Map<String, dynamic> toJson() => {'title': title, 'done': done};

  factory SubTask.fromJson(Map<String, dynamic> json) =>
      SubTask(json['title'] ?? '', done: json['done'] ?? false);
}

class Task {
  String title;
  String note;
  bool done;
  DateTime? due;
  int priority; // 0 = Low, 1 = Medium, 2 = High
  int category; // index of categoryLabels
  int repeat; // 0 = none, 1 = daily, 2 = weekly, 3 = monthly
  List<SubTask> subs;

  Task(
    this.title, {
    this.note = '',
    this.done = false,
    this.due,
    this.priority = 1,
    this.category = 0,
    this.repeat = 0,
    List<SubTask>? subs,
  }) : subs = subs ?? [];

  Map<String, dynamic> toJson() => {
        'title': title,
        'note': note,
        'done': done,
        'due': due?.toIso8601String(),
        'priority': priority,
        'category': category,
        'repeat': repeat,
        'subs': subs.map((s) => s.toJson()).toList(),
      };

  factory Task.fromJson(Map<String, dynamic> json) {
    final c = json['category'];
    final p = json['priority'];
    final r = json['repeat'];
    final rawSubs = json['subs'] as List? ?? [];
    return Task(
      json['title'] ?? '',
      note: json['note'] ?? '',
      done: json['done'] ?? false,
      due: json['due'] != null ? DateTime.parse(json['due']) : null,
      priority: (p is int && p >= 0 && p < priorityLabels.length) ? p : 1,
      category: (c is int && c >= 0 && c < categoryLabels.length) ? c : 0,
      repeat: (r is int && r >= 0 && r < repeatLabels.length) ? r : 0,
      subs: rawSubs
          .map((e) => SubTask.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

enum TaskFilter { all, pending, done }

enum SortMode { added, date, priority }

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
String formatDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  return '$day/$month/${d.year}';
}

DateTime todayDate() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String dueLabel(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(todayDate()).inDays;
  if (diff == 0) return 'Aaj';
  if (diff == 1) return 'Kal';
  if (diff == -1) return 'Kal tha';
  return formatDate(d);
}

DateTime _advance(DateTime d, int repeat) {
  switch (repeat) {
    case 1:
      return DateTime(d.year, d.month, d.day + 1);
    case 2:
      return DateTime(d.year, d.month, d.day + 7);
    case 3:
      return DateTime(d.year, d.month + 1, d.day);
    default:
      return d;
  }
}

DateTime nextDue(DateTime d, int repeat) {
  var next = _advance(d, repeat);
  var guard = 0;
  while (next.isBefore(todayDate()) && guard < 1000) {
    next = _advance(next, repeat);
    guard++;
  }
  return next;
}

// ---------------------------------------------------------------------------
// Pomodoro timer
// ---------------------------------------------------------------------------
class PomodoroSheet extends StatefulWidget {
  const PomodoroSheet({super.key});

  @override
  State<PomodoroSheet> createState() => _PomodoroSheetState();
}

class _PomodoroSheetState extends State<PomodoroSheet> {
  int _minutes = 25;
  int _left = 25 * 60;
  bool _running = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setMinutes(int m) {
    if (_running) return;
    setState(() {
      _minutes = m;
      _left = m * 60;
    });
  }

  void _start() {
    if (_left <= 0) {
      _left = _minutes * 60;
    }
    setState(() {
      _running = true;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
        HapticFeedback.heavyImpact();
        if (mounted) {
          setState(() {
            _left = 0;
            _running = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _left--;
          });
        }
      }
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(() {
      _running = false;
    });
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _left = _minutes * 60;
    });
  }

  String get _timeText {
    final m = (_left ~/ 60).toString().padLeft(2, '0');
    final s = (_left % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = 1 - (_left / (_minutes * 60));
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Focus Timer', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final m in [15, 25, 45])
                ChoiceChip(
                  label: Text('$m min'),
                  selected: _minutes == m,
                  onSelected: _running ? null : (_) => _setMinutes(m),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CircularProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    strokeWidth: 8,
                  ),
                ),
                Text(
                  _timeText,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _running ? _pause : _start,
                icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                label: Text(_running ? 'Pause' : 'Start'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
          if (_left == 0)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('Time ho gaya! Thoda break lo. 🎉'),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Statistics bottom sheet
// ---------------------------------------------------------------------------
void showStatsSheet(BuildContext context, List<Task> tasks) {
  final total = tasks.length;
  final done = tasks.where((t) => t.done).length;
  final overdue = tasks
      .where((t) => !t.done && t.due != null && t.due!.isBefore(todayDate()))
      .length;
  final dueToday = tasks.where((t) {
    if (t.done || t.due == null) return false;
    final d = DateTime(t.due!.year, t.due!.month, t.due!.day);
    return d == todayDate();
  }).length;

  Widget statBox(String label, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: color.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Statistics',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  statBox('Total', '$total', Colors.blue),
                  statBox('Ho gaye', '$done', Colors.green),
                  statBox('Aaj', '$dueToday', Colors.orange),
                  statBox('Der', '$overdue', Colors.red),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Category ke hisaab se',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < categoryLabels.length; i++)
                Builder(builder: (context) {
                  final inCat = tasks.where((t) => t.category == i).toList();
                  final catDone = inCat.where((t) => t.done).length;
                  final value = inCat.isEmpty ? 0.0 : catDone / inCat.length;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(categoryIcons[i], size: 18),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 70,
                          child: Text(categoryLabels[i]),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('$catDone/${inCat.length}'),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Naya kaam / kaam badlo wala bottom sheet
// ---------------------------------------------------------------------------
class TaskSheet extends StatefulWidget {
  final Task? task;
  const TaskSheet({super.key, this.task});

  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  final TextEditingController _subCtrl = TextEditingController();
  late List<SubTask> _subs;
  DateTime? _due;
  int _priority = 1;
  int _category = 0;
  int _repeat = 0;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _note = TextEditingController(text: t?.note ?? '');
    _subs =
        (t?.subs ?? []).map((s) => SubTask(s.title, done: s.done)).toList();
    _due = t?.due;
    _priority = t?.priority ?? 1;
    _category = t?.category ?? 0;
    _repeat = t?.repeat ?? 0;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _subCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        _due = picked;
      });
    }
  }

  void _addSub() {
    final text = _subCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subs.add(SubTask(text));
      _subCtrl.clear();
    });
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    if (_subCtrl.text.trim().isNotEmpty) {
      _subs.add(SubTask(_subCtrl.text.trim()));
    }
    // Repeat ke liye tareekh zaroori hai, nahi hai to aaj ki lagao.
    final due = (_repeat != 0 && _due == null) ? todayDate() : _due;
    Navigator.pop(
      context,
      Task(
        title,
        note: _note.text.trim(),
        done: widget.task?.done ?? false,
        due: due,
        priority: _priority,
        category: _category,
        repeat: _repeat,
        subs: _subs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isNew = widget.task == null;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isNew ? 'Naya kaam' : 'Kaam badlo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Kaam ka naam',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Note (zaroori nahi)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Chhote kaam (checklist)'),
            const SizedBox(height: 4),
            for (int i = 0; i < _subs.length; i++)
              Row(
                children: [
                  Checkbox(
                    value: _subs[i].done,
                    onChanged: (v) {
                      setState(() {
                        _subs[i].done = v ?? false;
                      });
                    },
                  ),
                  Expanded(
                    child: Text(
                      _subs[i].title,
                      style: TextStyle(
                        decoration: _subs[i].done
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _subs.removeAt(i);
                      });
                    },
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subCtrl,
                    onSubmitted: (_) => _addSub(),
                    decoration: InputDecoration(
                      hintText: 'Chhota kaam jodo',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  onPressed: _addSub,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Category'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (int i = 0; i < categoryLabels.length; i++)
                  ChoiceChip(
                    avatar: Icon(categoryIcons[i], size: 16),
                    label: Text(categoryLabels[i]),
                    selected: _category == i,
                    onSelected: (_) {
                      setState(() {
                        _category = i;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Priority'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (int i = 0; i < priorityLabels.length; i++)
                  ChoiceChip(
                    avatar:
                        Icon(Icons.flag, size: 16, color: priorityColors[i]),
                    label: Text(priorityLabels[i]),
                    selected: _priority == i,
                    onSelected: (_) {
                      setState(() {
                        _priority = i;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Tareekh'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Aaj'),
                  onPressed: () {
                    setState(() {
                      _due = todayDate();
                    });
                  },
                ),
                ActionChip(
                  label: const Text('Kal'),
                  onPressed: () {
                    setState(() {
                      _due = todayDate().add(const Duration(days: 1));
                    });
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.calendar_month, size: 18),
                  label: Text(
                    _due == null ? 'Tareekh chuno' : formatDate(_due!),
                  ),
                  onPressed: _pickDate,
                ),
                if (_due != null)
                  ActionChip(
                    avatar: const Icon(Icons.close, size: 16),
                    label: const Text('Hatao'),
                    onPressed: () {
                      setState(() {
                        _due = null;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Repeat'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (int i = 0; i < repeatLabels.length; i++)
                  ChoiceChip(
                    label: Text(repeatLabels[i]),
                    selected: _repeat == i,
                    onSelected: (_) {
                      setState(() {
                        _repeat = i;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(isNew ? 'Add karo' : 'Save karo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  List<Task> _tasks = [];
  TaskFilter _filter = TaskFilter.all;
  SortMode _sort = SortMode.added;
  int? _categoryFilter;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  bool get _canReorder =>
      _filter == TaskFilter.all &&
      _sort == SortMode.added &&
      _categoryFilter == null &&
      _query.isEmpty;

  List<Task> get _visibleTasks {
    final list = _tasks.where((t) {
      if (_filter == TaskFilter.pending && t.done) return false;
      if (_filter == TaskFilter.done && !t.done) return false;
      if (_categoryFilter != null && t.category != _categoryFilter) {
        return false;
      }
      if (_query.isNotEmpty &&
          !t.title.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    switch (_sort) {
      case SortMode.date:
        list.sort((a, b) {
          if (a.due == null && b.due == null) return 0;
          if (a.due == null) return 1;
          if (b.due == null) return -1;
          return a.due!.compareTo(b.due!);
        });
        break;
      case SortMode.priority:
        list.sort((a, b) => b.priority.compareTo(a.priority));
        break;
      case SortMode.added:
        break;
    }
    return list;
  }

  Future<void> _toggleTheme() async {
    final isDark = themeNotifier.value == ThemeMode.dark;
    themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', !isDark);
  }

  Future<void> _pickColor() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('App ka rang chuno'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (int i = 0; i < seedColors.length; i++)
              GestureDetector(
                onTap: () async {
                  colorNotifier.value = i;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('colorIndex', i);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: seedColors[i],
                  child: colorNotifier.value == i
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('tasks');
    if (saved != null) {
      final list = jsonDecode(saved) as List;
      setState(() {
        _tasks = list
            .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
    }
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_tasks.map((t) => t.toJson()).toList());
    await prefs.setString('tasks', data);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openTaskSheet({Task? task}) async {
    final result = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => TaskSheet(task: task),
    );
    if (result == null) return;
    setState(() {
      if (task == null) {
        _tasks.add(result);
      } else {
        task.title = result.title;
        task.note = result.note;
        task.due = result.due;
        task.priority = result.priority;
        task.category = result.category;
        task.repeat = result.repeat;
        task.subs = result.subs;
      }
    });
    _saveTasks();
  }

  void _toggleDone(Task task, bool value) {
    HapticFeedback.lightImpact();
    if (value && task.repeat != 0 && task.due != null) {
      // Repeat wala kaam: agli tareekh par bhej do.
      final next = nextDue(task.due!, task.repeat);
      setState(() {
        task.due = next;
        task.done = false;
        for (final s in task.subs) {
          s.done = false;
        }
      });
      _saveTasks();
      _toast('Agli baar: ${dueLabel(next)}');
      return;
    }
    setState(() {
      task.done = value;
    });
    _saveTasks();
  }

  void _deleteTask(Task task) {
    final index = _tasks.indexOf(task);
    if (index == -1) return;
    setState(() {
      _tasks.removeAt(index);
    });
    _saveTasks();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${task.title}" hata diya'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              final position = index > _tasks.length ? _tasks.length : index;
              _tasks.insert(position, task);
            });
            _saveTasks();
          },
        ),
      ),
    );
  }

  void _clearCompleted() {
    ScaffoldMessenger.of(context).clearSnackBars();
    if (!_tasks.any((t) => t.done)) {
      _toast('Abhi koi ho gaya kaam nahi hai');
      return;
    }
    final backup = List<Task>.from(_tasks);
    setState(() {
      _tasks.removeWhere((t) => t.done);
    });
    _saveTasks();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Ho gaye saare kaam hata diye'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              _tasks = backup;
            });
            _saveTasks();
          },
        ),
      ),
    );
  }

  Future<void> _backupCopy() async {
    final data = jsonEncode(_tasks.map((t) => t.toJson()).toList());
    await Clipboard.setData(ClipboardData(text: data));
    _toast('Backup copy ho gaya. Kahin paste karke save kar lo.');
  }

  Future<void> _restoreBackup() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final controller = TextEditingController(text: clip?.text ?? '');
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup wapas lao'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Apna backup yahan paste karo. Abhi ke saare kaam badal jayenge.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final list = jsonDecode(text) as List;
      final restored = list
          .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      setState(() {
        _tasks = restored;
      });
      _saveTasks();
      _toast('${restored.length} kaam wapas aa gaye');
    } catch (_) {
      _toast('Ye sahi backup nahi hai');
    }
  }

  bool _isOverdue(Task task) {
    if (task.due == null || task.done) return false;
    return task.due!.isBefore(todayDate());
  }

  Widget _buildSubtitle(Task task) {
    final overdue = _isOverdue(task);
    final color = overdue ? Colors.red : Colors.grey;
    final subDone = task.subs.where((s) => s.done).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (task.note.isNotEmpty)
          Text(
            task.note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(categoryIcons[task.category],
                    size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  categoryLabels[task.category],
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            if (task.due != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(
                    overdue
                        ? 'Der ho gayi: ${dueLabel(task.due!)}'
                        : dueLabel(task.due!),
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ],
              ),
            if (task.subs.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.checklist, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '$subDone/${task.subs.length}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            if (task.repeat != 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.repeat, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    repeatLabels[task.repeat],
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildItem(Task task) {
    return Dismissible(
      key: ObjectKey(task),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteTask(task),
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          onTap: () => _openTaskSheet(task: task),
          leading: Checkbox(
            value: task.done,
            onChanged: (value) => _toggleDone(task, value ?? false),
          ),
          title: Text(
            task.title,
            style: TextStyle(
              decoration:
                  task.done ? TextDecoration.lineThrough : TextDecoration.none,
              color: task.done ? Colors.grey : null,
            ),
          ),
          subtitle: _buildSubtitle(task),
          trailing: IconButton(
            icon: Icon(Icons.flag, color: priorityColors[task.priority]),
            tooltip: '${priorityLabels[task.priority]} (badalne ke liye dabao)',
            onPressed: () {
              setState(() {
                task.priority = (task.priority + 1) % 3;
              });
              _saveTasks();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<Task> visible) {
    if (_canReorder) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: visible.length,
        buildDefaultDragHandles: true,
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) newIndex -= 1;
          setState(() {
            final item = _tasks.removeAt(oldIndex);
            _tasks.insert(newIndex, item);
          });
          _saveTasks();
        },
        itemBuilder: (context, index) {
          final task = visible[index];
          return KeyedSubtree(
            key: ObjectKey(task),
            child: _buildItem(task),
          );
        },
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: visible.length,
      itemBuilder: (context, index) => _buildItem(visible[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visible = _visibleTasks;
    final total = _tasks.length;
    final doneCount = _tasks.where((t) => t.done).length;
    final progress = total == 0 ? 0.0 : doneCount / total;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: _searching
            ? TextField(
                autofocus: true,
                onChanged: (value) {
                  setState(() {
                    _query = value.trim();
                  });
                },
                decoration: const InputDecoration(
                  hintText: 'Kaam dhundho',
                  border: InputBorder.none,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('To-Do'),
                  Text(
                    formatDate(DateTime.now()),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: 'Search',
            onPressed: () {
              setState(() {
                _searching = !_searching;
                _query = '';
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.timer),
            tooltip: 'Focus timer',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                showDragHandle: true,
                builder: (context) => const PomodoroSheet(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Statistics',
            onPressed: () => showStatsSheet(context, _tasks),
          ),
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: 'Theme badlo',
            onPressed: _toggleTheme,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'clear':
                  _clearCompleted();
                  break;
                case 'color':
                  _pickColor();
                  break;
                case 'backup':
                  _backupCopy();
                  break;
                case 'restore':
                  _restoreBackup();
                  break;
                default:
                  setState(() {
                    _sort = SortMode.values.firstWhere((m) => m.name == value);
                  });
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                enabled: false,
                child: Text('Sort karo'),
              ),
              CheckedPopupMenuItem<String>(
                value: 'added',
                checked: _sort == SortMode.added,
                child: const Text('Jaise add kiye'),
              ),
              CheckedPopupMenuItem<String>(
                value: 'date',
                checked: _sort == SortMode.date,
                child: const Text('Tareekh ke hisaab se'),
              ),
              CheckedPopupMenuItem<String>(
                value: 'priority',
                checked: _sort == SortMode.priority,
                child: const Text('Priority ke hisaab se'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'color',
                child: Text('App ka rang badlo'),
              ),
              const PopupMenuItem<String>(
                value: 'clear',
                child: Text('Ho gaye kaam hatao'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'backup',
                child: Text('Backup copy karo'),
              ),
              const PopupMenuItem<String>(
                value: 'restore',
                child: Text('Backup wapas lao'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTaskSheet(),
        icon: const Icon(Icons.add),
        label: const Text('Naya kaam'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          children: [
            if (total > 0)
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            doneCount == total
                                ? 'Sab kaam ho gaye! 🎉'
                                : '$doneCount / $total kaam ho gaye',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${(progress * 100).round()}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<TaskFilter>(
                segments: const [
                  ButtonSegment(value: TaskFilter.all, label: Text('Sab')),
                  ButtonSegment(
                      value: TaskFilter.pending, label: Text('Baaki')),
                  ButtonSegment(
                      value: TaskFilter.done, label: Text('Ho gaye')),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) {
                  setState(() {
                    _filter = selection.first;
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Sab'),
                      selected: _categoryFilter == null,
                      onSelected: (_) {
                        setState(() {
                          _categoryFilter = null;
                        });
                      },
                    ),
                  ),
                  for (int i = 0; i < categoryLabels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(categoryIcons[i], size: 16),
                        label: Text(categoryLabels[i]),
                        selected: _categoryFilter == i,
                        onSelected: (_) {
                          setState(() {
                            _categoryFilter = i;
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _tasks.isEmpty
                  ? const Center(
                      child: Text(
                        'Abhi koi kaam nahi.\nNeeche "Naya kaam" dabao!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : visible.isEmpty
                      ? const Center(
                          child: Text(
                            'Koi kaam nahi mila.',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : _buildList(visible),
            ),
          ],
        ),
      ),
    );
  }
}