import 'package:flutter/material.dart';

/// 全局路由观察者，供需要感知「重新成为顶层路由」的页面订阅。
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();
