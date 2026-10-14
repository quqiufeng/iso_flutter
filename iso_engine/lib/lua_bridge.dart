// LuaJIT 桥：Dart ←FFI→ libluajit。跑一段 Lua、取回栈顶字符串（路径串/JSON）。
import 'dart:ffi';
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
typedef _CloseC = Void Function(Pointer<Void>);
typedef _CloseD = void Function(Pointer<Void>);

class Lua {
  Lua() : _lib = DynamicLibrary.open('libluajit-5.1.so.2') {
    _newState = _lib.lookupFunction<_NewStateC, _NewStateD>('luaL_newstate');
    _openLibs = _lib.lookupFunction<_OpenLibsC, _OpenLibsD>('luaL_openlibs');
    _loadString = _lib.lookupFunction<_LoadStringC, _LoadStringD>('luaL_loadstring');
    _pcall = _lib.lookupFunction<_PcallC, _PcallD>('lua_pcall');
    _toLString = _lib.lookupFunction<_ToLStringC, _ToLStringD>('lua_tolstring');
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
  late final void Function(Pointer<Void>) _close;
  late final Pointer<Void> _state;

  /// 跑一段 Lua（应 `return <字符串>`），返回结果；出错抛异常。
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
