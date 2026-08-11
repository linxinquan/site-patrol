import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'shared/widgets/device_frame.dart';

void main() =>
    runApp(const ProviderScope(child: DeviceFrame(child: App())));
