import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/buzzer_control_provider.dart';

class BuzzerControlCard extends StatelessWidget {
  const BuzzerControlCard({super.key});

  @override
  Widget build(BuildContext context) {
    final control = context.watch<BuzzerControlProvider>();
    final device = control.device;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Còi thiết bị',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ),
                if (control.pending)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (device != null) ...[
                  Text(device.buzzerEnabled ? 'BẬT' : 'TẮT'),
                  Switch(
                    key: const Key('buzzer-switch'),
                    value: device.buzzerEnabled,
                    onChanged: control.pending ? null : control.setEnabled,
                  ),
                ],
                IconButton(
                  tooltip: 'Làm mới cấu hình còi',
                  onPressed: control.pending ? null : control.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (device != null)
              Text(
                device.buzzerEnabled
                    ? '🔊 Còi đang bật'
                    : '🔇 Còi đang tắt — Chế độ kiểm thử',
              ),
            if (device == null && control.error == null)
              const Text('Đang đọc cấu hình còi…'),
            if (device != null && !device.buzzerEnabled)
              Container(
                key: const Key('buzzer-disabled-warning'),
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠ Còi vật lý đang tắt. Phát hiện té ngã và cảnh báo từ xa vẫn hoạt động.',
                  style: TextStyle(
                    color: Color(0xFF5D4200),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            const Text(
              'Thiết bị có thể mất tối đa khoảng 20 giây để nhận thay đổi.',
            ),
            const Text(
              'Đây là cấu hình đã lưu; việc áp dụng phụ thuộc kết nối của thiết bị.',
              style: TextStyle(fontSize: 12),
            ),
            if (control.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(control.message!),
              ),
            if (control.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  control.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
