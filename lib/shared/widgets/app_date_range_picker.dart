import 'package:flutter/material.dart';
import 'package:flutter_mingcute/flutter_mingcute.dart';
import '../../core/theme/design_tokens.dart';
import 'app_bottom_sheet.dart';

/// 自有风格的日期范围选择器（替代 Material `showDateRangePicker` 的 Google 原生样式）。
///
/// 以底部弹窗呈现：月历网格（周一为首列）、起始/结束高亮、区间浅蓝填充、
/// 上/下月切换、底部「确定」按钮。返回选中的 [DateTimeRange]，取消返回 null。
class AppDateRangePicker {
  static Future<DateTimeRange?> show(
    BuildContext context, {
    required DateTime firstDate,
    required DateTime lastDate,
    required DateTimeRange initialRange,
  }) {
    return AppBottomSheet.show<DateTimeRange>(
      context: context,
      title: '选择汇报周期',
      isScrollControlled: true,
      body: (ctx) => _PickerBody(
        firstDate: _dayOnly(firstDate),
        lastDate: _dayOnly(lastDate),
        initialRange: initialRange,
      ),
    );
  }
}

DateTime _dayOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

class _PickerBody extends StatefulWidget {
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange initialRange;
  const _PickerBody({
    required this.firstDate,
    required this.lastDate,
    required this.initialRange,
  });

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  late DateTime _start;
  late DateTime? _end;
  late DateTime _view; // 当前查看月份的第一天

  @override
  void initState() {
    super.initState();
    _start = _dayOnly(widget.initialRange.start);
    final e = _dayOnly(widget.initialRange.end);
    _end = e.isAtSameMomentAs(_start) ? null : e;
    _view = DateTime(_start.year, _start.month, 1);
  }

  void _onTap(DateTime day) {
    setState(() {
      if (_end == null) {
        if (day.isBefore(_start)) {
          _start = day; // 早于起点：重设起点，继续等待终点
        } else if (!day.isAtSameMomentAs(_start)) {
          _end = day;
        }
      } else {
        // 已选完整区间，再次点按视为重新选起点
        _start = day;
        _end = null;
      }
    });
  }

  void _stepMonth(int delta) {
    setState(() => _view = DateTime(_view.year, _view.month + delta, 1));
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _buildWeeks();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _navRow(),
        const SizedBox(height: 10),
        _weekdayRow(),
        const SizedBox(height: 6),
        for (final w in weeks) _weekRow(w),
        const SizedBox(height: 12),
        _summary(),
        const SizedBox(height: 12),
        _confirmButton(),
      ],
    );
  }

  Widget _navRow() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _navBtn(MingCuteIcons.leftLine, _canPrev(), () => _stepMonth(-1)),
          Text('${_view.year} 年 ${_view.month} 月',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 22 / 15,
                  color: AppTokens.fg)),
          _navBtn(MingCuteIcons.rightLine, _canNext(), () => _stepMonth(1)),
        ],
      );

  Widget _navBtn(IconData icon, bool enabled, VoidCallback onTap) => SizedBox(
        width: 32,
        height: 32,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            onTap: enabled ? onTap : null,
            child: Icon(icon,
                size: 20, color: enabled ? AppTokens.fg : AppTokens.note),
          ),
        ),
      );

  Widget _weekdayRow() => Row(
        children: const ['一', '二', '三', '四', '五', '六', '日']
            .map((w) => Expanded(
                  child: Center(
                    child: Text(w,
                        style: const TextStyle(
                            fontSize: 12,
                            height: 18 / 12,
                            color: AppTokens.muted)),
                  ),
                ))
            .toList(),
      );

  Widget _weekRow(List<DateTime?> week) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: week.map((d) => Expanded(child: _dayCell(d))).toList(),
        ),
      );

  Widget _dayCell(DateTime? d) {
    if (d == null) return const SizedBox(height: 40);
    final disabled = d.isBefore(widget.firstDate) || d.isAfter(widget.lastDate);
    final isStart = d.isAtSameMomentAs(_start);
    final isEnd = _end != null && d.isAtSameMomentAs(_end!);
    final inRange =
        _end != null && d.isAfter(_start) && d.isBefore(_end!);
    final isToday = d.isAtSameMomentAs(_dayOnly(DateTime.now()));
    final selected = isStart || isEnd;

    Color bg = Colors.transparent;
    Color fg = disabled ? AppTokens.muted : AppTokens.fg;
    if (selected) {
      bg = AppTokens.brand;
      fg = AppTokens.onAccent;
    } else if (inRange) {
      bg = AppTokens.brandSoft;
      fg = AppTokens.brand;
    } else if (isToday && !disabled) {
      fg = AppTokens.brand;
    }

    return SizedBox(
      height: 40,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          onTap: disabled ? null : () => _onTap(d),
          child: Center(
            child: Text('${d.day}',
                style: TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                )),
          ),
        ),
      ),
    );
  }

  Widget _summary() => Row(
        children: [
          Expanded(
            child: Text(
              '已选：${_fmt(_start)} ~ ${_fmt(_end ?? _start)}',
              style: const TextStyle(
                  fontSize: 13, height: 20 / 13, color: AppTokens.fg2),
            ),
          ),
        ],
      );

  Widget _confirmButton() => SizedBox(
        width: double.infinity,
        height: 48,
        child: Material(
          color: AppTokens.brand,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            onTap: () => Navigator.of(context)
                .pop(DateTimeRange(start: _start, end: _end ?? _start)),
            child: Center(
              child: Text('确定',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 24 / 16,
                      color: AppTokens.onAccent)),
            ),
          ),
        ),
      );

  bool _canPrev() =>
      _view.isAfter(DateTime(widget.firstDate.year, widget.firstDate.month, 1));
  bool _canNext() =>
      _view.isBefore(DateTime(widget.lastDate.year, widget.lastDate.month, 1));

  List<List<DateTime?>> _buildWeeks() {
    final first = DateTime(_view.year, _view.month, 1);
    final leading = (first.weekday - 1) % 7; // 周一为首列
    final total = DateTime(_view.year, _view.month + 1, 0).day;
    final cells = <DateTime?>[];
    for (var i = 0; i < leading; i++) {
      cells.add(null);
    }
    for (var d = 1; d <= total; d++) {
      cells.add(DateTime(_view.year, _view.month, d));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final weeks = <List<DateTime?>>[];
    for (var i = 0; i < cells.length; i += 7) {
      weeks.add(cells.sublist(i, i + 7));
    }
    return weeks;
  }

  String _fmt(DateTime d) =>
      '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
  String _pad(int n) => n < 10 ? '0$n' : '$n';
}
