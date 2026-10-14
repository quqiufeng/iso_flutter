// 探针：Flutter/Dart ←FFI→ LuaJIT，跑一段 Lua 拿回字符串（验证桥）
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

void main() {
  final lib = DynamicLibrary.open('libluajit-5.1.so.2');
  final newState = lib.lookupFunction<_NewStateC, _NewStateD>('luaL_newstate');
  final openLibs = lib.lookupFunction<_OpenLibsC, _OpenLibsD>('luaL_openlibs');
  final loadString = lib.lookupFunction<_LoadStringC, _LoadStringD>('luaL_loadstring');
  final pcall = lib.lookupFunction<_PcallC, _PcallD>('lua_pcall');
  final toLString = lib.lookupFunction<_ToLStringC, _ToLStringD>('lua_tolstring');

  final l = newState();
  openLibs(l);

  const code = r'''
    local pts = {}
    for i = 0, 63 do
      local a = i / 64 * math.pi * 2
      pts[#pts+1] = string.format("%s%.1f %.1f", i == 0 and "M" or "L", 40*math.cos(a), 40*math.sin(a))
    end
    return table.concat(pts) .. "Z"
  ''';

  final codePtr = code.toNativeUtf8().cast<Char>();
  final loaded = loadString(l, codePtr);
  final ok = pcall(l, 0, 1, 0);
  final lenPtr = calloc<Int>();
  final res = toLString(l, -1, lenPtr);
  print('load=$loaded  pcall=$ok  len=${lenPtr.value}');
  print('result=${res.cast<Utf8>().toDartString()}');
  calloc.free(codePtr);
  calloc.free(lenPtr);
}
