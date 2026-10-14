// LuaJIT 桥：Dart ←FFI→ libluajit。跑一段 Lua、取回栈顶字符串（路径串/JSON）。
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _NewStateC = Pointer<Void> Function();
typedef _NewStateD = Pointer<Void> Function();
typedef _OpenLibsC = Void Function(Pointer<Void>);
typedef _OpenLibsD = void Function(Pointer<Void>);
typedef _LoadStringC = Int32 Function(Pointer<Void>, Pointer<Char>);
typedef _LoadStringD = int Function(Pointer<Void>, Pointer<Char>);
typedef _PcallC = Int32 Function(Pointer<Void>, Int32, Int32, Int32);
typedef _PcallD = int Function(Pointer<Void>, int, int, int);
typedef _ToLStringC = Pointer<Char> Function(Pointer<Void>, Int32, Pointer<Int>);
typedef _ToLStringD = Pointer<Char> Function(Pointer<Void>, int, Pointer<Int>);
typedef _SetTopC = Void Function(Pointer<Void>, Int32);
typedef _SetTopD = void Function(Pointer<Void>, int);
typedef _CloseC = Void Function(Pointer<Void>);
typedef _CloseD = void Function(Pointer<Void>);

/// 依次尝试这些库名（可用环境变量 ISO_LUAJIT 指定完整路径）。
const List<String> _libNames = [
  'libluajit-5.1.so.2', 'libluajit-5.1.so', 'libluajit.so', // Linux
  'libluajit-5.1.dylib', 'libluajit.dylib', // macOS
  'luajit.dll', 'lua51.dll', // Windows
];

DynamicLibrary _openLuaJit() {
  final tried = <String>[];
  final env = Platform.environment['ISO_LUAJIT'];
  if (env != null && env.isNotEmpty) tried.add(env);
  tried.addAll(_libNames);
  Object? last;
  for (final name in tried) {
    try {
      return DynamicLibrary.open(name);
    } catch (e) {
      last = e;
    }
  }
  throw StateError('无法加载 LuaJIT（试过：${tried.join(", ")}）。\n可设环境变量 ISO_LUAJIT=<libluajit 完整路径>。\n$last');
}

class Lua {
  Lua() : _lib = _openLuaJit() {
    _newState = _lib.lookupFunction<_NewStateC, _NewStateD>('luaL_newstate');
    _openLibs = _lib.lookupFunction<_OpenLibsC, _OpenLibsD>('luaL_openlibs');
    _loadString = _lib.lookupFunction<_LoadStringC, _LoadStringD>('luaL_loadstring');
    _pcall = _lib.lookupFunction<_PcallC, _PcallD>('lua_pcall');
    _toLString = _lib.lookupFunction<_ToLStringC, _ToLStringD>('lua_tolstring');
    _settop = _lib.lookupFunction<_SetTopC, _SetTopD>('lua_settop');
    _close = _lib.lookupFunction<_CloseC, _CloseD>('lua_close');
    _state = _newState();
    _openLibs(_state);
  }

  final DynamicLibrary _lib;
  late final Pointer<Void> Function() _newState;
  late final void Function(Pointer<Void>) _openLibs;
  late final int Function(Pointer<Void>, Pointer<Char>) _loadString;
  late final int Function(Pointer<Void>, int, int, int) _pcall;
  late final Pointer<Char> Function(Pointer<Void>, int, Pointer<Int>) _toLString;
  late final void Function(Pointer<Void>, int) _settop;
  late final void Function(Pointer<Void>) _close;
  late final Pointer<Void> _state;

  /// 跑一段 Lua（应 `return <字符串>`），返回结果；出错抛异常。每次调用后**清栈**（防泄漏）。
  String run(String code) {
    final src = code.toNativeUtf8().cast<Char>();
    try {
      final loaded = _loadString(_state, src);
      if (loaded != 0) throw StateError('lua load error: ${_top()}');
      final ok = _pcall(_state, 0, 1, 0);
      if (ok != 0) throw StateError('lua error: ${_top()}');
      return _top();
    } finally {
      calloc.free(src);
      _settop(_state, 0); // 清空栈（否则每次调用残留一个值）
    }
  }

  String _top() {
    final len = calloc<Int>();
    try {
      final ptr = _toLString(_state, -1, len);
      if (ptr == nullptr) return '';
      return ptr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(len);
    }
  }

  void dispose() => _close(_state);
}
