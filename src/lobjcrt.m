/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "lobjc.h"
#import "lobjc_invoke.h"
#import "lobjc_convert.h"
#import "typeencoding.h"
#import "LuaWrapper.h"

#import <objc/runtime.h>
#import <lua.h>
#import <lauxlib.h>
#import <Foundation/Foundation.h>
#import <stdbool.h>
#import <assert.h>

extern int run_simple_test (lua_State *L);

static const char tname_id[] = "objc:id";
static const char tname_Method[] = "objc:Method";
static const char tname_Ivar[] = "objc:Ivar";

static void pushid_impl (lua_State *L, id obj, bool retain, bool try_method) {
  if (obj == nil) {
    lua_pushnil(L); // TODO: reconsider this behavior
  } else if (try_method && [obj respondsToSelector: @selector(lobjc_pushLuaValue:)]
          && [obj lobjc_pushLuaValue: L]) {
  } else {
    lua_getfield(L, LUA_REGISTRYINDEX, "lobjc:id_cache");
    lua_pushlightuserdata(L, (void *)obj);
    lua_rawget(L, -2);
    if (lua_isnil(L, -1)) {
      lua_pop(L, 1);

      id *ptr = (id*)lua_newuserdata(L, sizeof(id));
      *ptr = nil;

      luaL_getmetatable(L, tname_id);
      lua_setmetatable(L, -2);

      // we retain obj AFTER we have set its metatable
      // (to make sure __gc is called)
      if (retain) {
        [obj retain];
      }
      *ptr = obj;

      lua_pushlightuserdata(L, (void *)obj);
      lua_pushvalue(L, -2);
      lua_settable(L, -4);
    }
    lua_remove(L, -2); // remove cache table
  }
}
LUALIB_API void lobjc_pushid (lua_State *L, id obj) {
  pushid_impl(L, obj, true, true);
}

LUALIB_API void lobjc_pushid_noretain (lua_State *L, id obj) {
  pushid_impl(L, obj, false, true);
}

LUALIB_API void lobjc_rawpushid (lua_State *L, id obj) {
  pushid_impl(L, obj, true, false);
}


// TODO: make it possible to distinguish automatically-converted objects
//       from other objects
LUALIB_API id lobjc_toid (lua_State *L, int idx) {
  if (lua_isuserdata(L, idx)) { // TODO: try metamethod
    lua_getmetatable(L, idx);
    luaL_getmetatable(L, tname_id);
    if (lua_rawequal(L, -1, -2)) {
      lua_pop(L, 2);
      return *(id*)lua_touserdata(L, idx);
    }
    lua_pop(L, 2);
  } else if (lua_isstring(L, idx)) {
    return [NSString stringWithUTF8String: lua_tostring(L, idx)];
  } else if (lua_isboolean(L, idx)) {
    return [NSNumber numberWithBool: lua_toboolean(L, idx)];
  } else if (lua_isnumber(L, idx)) {
#if defined(LUA_NUMBER_DOUBLE)
    return [NSNumber numberWithDouble: lua_tonumber(L, idx)];
#else
# error "cannot convert lua_Number to NSNumber"
#endif
  } else if (lua_isnoneornil(L, idx)) {
    return nil;
  }
  lua_pushvalue(L, idx);
  return [[[LuaWrapper alloc] initWithLuaState: L] autorelease];
}

LUALIB_API id lobjc_rawtoid (lua_State *L, int idx) {
  if (lua_isuserdata(L, idx)) {
    lua_getmetatable(L, idx);
    luaL_getmetatable(L, tname_id);
    if (lua_rawequal(L, -1, -2)) {
      lua_pop(L, 2);
      return *(id*)lua_touserdata(L, idx);
    }
    lua_pop(L, 2);
  }
  return nil;
}


static int id_gc (lua_State *L) {
  id *p = (id *)lua_touserdata(L, 1);
  if (*p != nil) {
    [*p release];
    *p = nil;
  }
  return 0;
}

static const luaL_Reg idfuncs[] = {
  {"__gc", id_gc},
  {NULL, NULL}
};


static bool lobjc_pushptr (lua_State *L, void *obj, const char *tname, const char *cache) {
  if (obj == nil) {
    lua_pushnil(L);
  } else {
    lua_getfield(L, LUA_REGISTRYINDEX, cache);
    lua_pushlightuserdata(L, obj);
    lua_rawget(L, -2);
    if (lua_isnil(L, -1)) {
      lua_pop(L, 1);

      *(void**)lua_newuserdata(L, sizeof(void *)) = obj;

      luaL_getmetatable(L, tname);
      lua_setmetatable(L, -2);

      lua_pushlightuserdata(L, obj);
      lua_pushvalue(L, -2);
      lua_settable(L, -4);
      lua_remove(L, -2); // remove cache table
      return true;
    }
    lua_remove(L, -2); // remove cache table
  }
  return false;
}
#define lobjc_toptr(L,narg,tname) (*(void **)luaL_checkudata(L, narg, tname))



static int lobjc_objc_lookUpClass (lua_State *L) {  /** objc_lookUpClass(name) */
  lobjc_pushclass(L, objc_lookUpClass(luaL_checkstring(L, 1)));
  return 1;
}

static int lobjc_objc_getClass (lua_State *L) { /** objc_getClass(name) */
  lobjc_pushclass(L, objc_getClass(luaL_checkstring(L, 1)));
  return 1;
}

static int lobjc_objc_getMetaClass (lua_State *L) { /** objc_getMetaClass(name) */
  lobjc_pushclass(L, objc_getMetaClass(luaL_checkstring(L, 1)));
  return 1;
}

static int lobjc_objc_allocateClassPair (lua_State *L) { /** objc_allocateClassPair(super,name,extraBytes) */
  Class superclass = lobjc_toclass(L, 1);
  luaL_argcheck(L, superclass != Nil, 1, "no superclass specified"); // deny creating a new root class
  const char *name = luaL_checkstring(L, 2);
  size_t extraBytes = (size_t)luaL_optnumber(L, 3, 0);
  Class newclass = objc_allocateClassPair(superclass, name, extraBytes);
  // NB: do not try to invoke a method of newclass
  pushid_impl(L, newclass, false, false);
  return 1;
}

static int lobjc_objc_registerClassPair(lua_State *L) { /** objc_registerClassPair(cls) */
  Class cls = lobjc_toclass(L, 1);
  objc_registerClassPair(cls);
  return 0;
}

static int lobjc_object_getClass (lua_State *L) { /** object_getClass(obj) */
  lobjc_pushclass(L, object_getClass(lobjc_toid(L, 1)));
  return 1;
}

static int lobjc_object_getClassName (lua_State *L) { /** object_getClassName(obj) */
  lua_pushstring(L, object_getClassName(lobjc_toid(L, 1)));
  return 1;
}

static int lobjc_object_setClass (lua_State *L) { /** object_setClass(obj,cls) */
  id obj = lobjc_toid(L, 1);
  Class cls = lobjc_toclass(L, 2);
  lobjc_pushclass(L, object_setClass(obj, cls));
  return 1;
}

static int lobjc_object_getIvar (lua_State *L) { /** object_getIvar(obj,ivar) */
  id obj = lobjc_toid(L, 1);
  Ivar ivar = lobjc_toptr(L, 2, tname_Ivar);
  lobjc_pushid(L, object_getIvar(obj, ivar));
  return 1;
}

static int lobjc_object_setIvar (lua_State *L) { /** object_setIvar(obj,ivar,value) */
  id obj = lobjc_toid(L, 1);
  Ivar ivar = lobjc_toptr(L, 2, tname_Ivar);
  id value = lobjc_toid(L, 3);
  object_setIvar(obj, ivar, value);
  return 0;
}

static int lobjc_object_getInstanceVariable (lua_State *L) { /** object_getInstanceVariable(obj,name) */
  id obj = lobjc_toid(L, 1);
  const char *name = luaL_checkstring(L, 2);
  void *value = NULL;
  Ivar ivar = object_getInstanceVariable(obj, name, &value);
  const char *type = ivar_getTypeEncoding(ivar);
  lobjc_conv_objctolua1(L, type, value);
  lobjc_pushptr(L, ivar, tname_Ivar, "lobjc:Ivar_cache");
  return 2;
}

static int lobjc_class_getName (lua_State *L) { /** class_getName(cls) */
  lua_pushstring(L, class_getName(lobjc_toclass(L, 1)));
  return 1;
}

static int lobjc_class_getSuperclass (lua_State *L) { /** class_getSuperClass(cls) */
  lobjc_pushclass(L, class_getSuperclass(lobjc_toclass(L, 1)));
  return 1;
}

static int lobjc_class_getInstanceVariable (lua_State *L) { /** class_getInstanceVariable(cls,name) */
  Class cls = lobjc_toclass(L, 1);
  const char *name = luaL_checkstring(L, 2);
  lobjc_pushptr(L, class_getInstanceVariable(cls, name), tname_Ivar, "lobjc:Ivar_cache");
  return 1;
}

static int lobjc_class_getInstanceMethod (lua_State *L) { /** class_getInstanceMethod(cls,sel) */
  Class cls = lobjc_toclass(L, 1);
  SEL sel = lobjc_checkselector(L, 2);
  lobjc_pushptr(L, class_getInstanceMethod(cls, sel), tname_Method, "lobjc:Method_cache");
  return 1;
}

static int lobjc_class_getClassMethod (lua_State *L) { /** class_getClassMethod(cls,sel) */
  Class cls = lobjc_toclass(L, 1);
  SEL sel = lobjc_checkselector(L, 2);
  lobjc_pushptr(L, class_getClassMethod(cls, sel), tname_Method, "lobjc:Method_cache");
  return 1;
}

static int lobjc_class_isMetaClass (lua_State *L) { /** class_isMetaClass(cls) */
  lua_pushboolean(L, class_isMetaClass(lobjc_toclass(L, 1)));
  return 1;
}

static int lobjc_class_respondsToSelector (lua_State *L) { /** class_respondsToSelector(cls,sel) */
  Class cls = lobjc_toclass(L, 1);
  SEL sel = lobjc_checkselector(L, 2);
  lua_pushboolean(L, class_respondsToSelector(cls, sel));
  return 1;
}

static int lobjc_method_getName (lua_State *L) { /** method_getName(method) */
  Method method = lobjc_toptr(L, 1, tname_Method);
  lobjc_pushselector(L, method_getName(method));
  return 1;
}

static int lobjc_method_getNumberOfArguments (lua_State *L) { /** method_getNumberOfArguments(method) */
  Method method = lobjc_toptr(L, 1, tname_Method);
  lua_pushinteger(L, method_getNumberOfArguments(method));
  return 1;
}

static int lobjc_method_getTypeEncoding (lua_State *L) { /** method_getTypeEncoding(method) */
  Method method = lobjc_toptr(L, 1, tname_Method);
  lua_pushstring(L, method_getTypeEncoding(method));
  return 1;
}

static int lobjc_method_exchangeImplementations (lua_State *L) { /** method_exchangeImplementations(m1,m2) */
  Method m1 = lobjc_toptr(L, 1, tname_Method);
  Method m2 = lobjc_toptr(L, 2, tname_Method);
  method_exchangeImplementations(m1, m2);
  return 0;
}

static int lobjc_ivar_getName (lua_State *L) { /** ivar_getName(ivar) */
  lua_pushstring(L, ivar_getName(lobjc_toptr(L, 1, tname_Ivar)));
  return 1;
}

static int lobjc_ivar_getTypeEncoding (lua_State *L) { /** ivar_getTypeEncoding(ivar) */
  lua_pushstring(L, ivar_getTypeEncoding(lobjc_toptr(L, 1, tname_Ivar)));
  return 1;
}



static const char *lobjc_method_getTypeEncoding_ex (lua_State *L, Class class, SEL sel, Method method) {
  Method m = method;
  lua_getfield(L, LUA_REGISTRYINDEX, "lobjc:methodsig_override");
retry:
  lua_pushlightuserdata(L, (void *)m);
  lua_rawget(L, -2); // TODO: consider using the environment of this function
  if (lua_isstring(L, -1)) {
    const char *e = lua_tostring(L, -1);
    lua_pop(L, 2);
    return e;
  } else {
    lua_pop(L, 1); // pop nil
    class = class_getSuperclass(class);
    m = class_getInstanceMethod(class, sel);
    if (!m) {
      lua_pop(L, 1); // pop table
      return method_getTypeEncoding(method);
    }
    goto retry;
  }
}

static int lobjc_invoke (lua_State *L) { /** invoke(obj,sel,...) */
  id obj        = lobjc_toid(L, 1);
  SEL sel       = sel_registerName(luaL_checkstring(L, 2));
  Class class   = object_getClass(obj);
  bool already_retained = false // TODO: take into account already_retained attribute in BridgeSupport
    || sel == @selector(alloc)
    || sel == @selector(allocWithZone:)
    || sel == @selector(new)
    || sel == @selector(newObject)
    || sel == @selector(copy)
    || sel == @selector(copyWithZone:)
    || sel == @selector(mutableCopy)
    || sel == @selector(mutableCopyWithZone:);
  Method method = class_getInstanceMethod(class, sel);
  if (!method) {
    if ([obj respondsToSelector: sel]) {
      NSMethodSignature *sig = [obj methodSignatureForSelector: sel];
      if (sig) {
        return lobjc_invoke_with_signature(L, obj, sel, sig, 1, already_retained);
      }
    }
    return 0;
  }
  IMP impl = method_getImplementation(method);
  const char *e = lobjc_method_getTypeEncoding_ex(L, class, sel, method);
  unsigned argc = method_getNumberOfArguments(method);

  return lobjc_invoke_func(L, (void (*)())impl, e, argc, 1, already_retained);
}

static int lobjc_gettypeencoding_x (lua_State *L) { /** gettypeencoding_x(obj,sel,...) */
  id obj        = lobjc_toid(L, 1);
  SEL sel       = sel_registerName(luaL_checkstring(L, 2));
  Class class   = object_getClass(obj);
  Method method = class_getInstanceMethod(class, sel);
  if(!method) {
    return 0;
  }
  lua_pushstring(L, lobjc_method_getTypeEncoding_ex(L, class, sel, method));
  return 1;
}

static int lobjc_overridesignature (lua_State *L) { /** overridesignature(method,sig) */
  Method method = lobjc_toptr(L, 1, tname_Method);
  luaL_checkstring(L, 2);
  lua_getfield(L, LUA_REGISTRYINDEX, "lobjc:methodsig_override");
  lua_pushlightuserdata(L, (void *)method);
  lua_pushvalue(L, 2);
  lua_rawset(L, -3);
  return 0;
}

static int lobjc_registerinformalprotocol (lua_State *L) { /** registerinformalprotocol(name) */
  luaL_checktype(L, 1, LUA_TSTRING);
  lua_getfield(L, LUA_REGISTRYINDEX, "lobjc:informal_protocols");
  lua_pushvalue(L, 1);
  lua_gettable(L, -2);
  if (lua_isnil(L, -1)) {
    lua_pop(L, 1);
    lua_newtable(L);
    lua_pushvalue(L, -1);
    lua_pushvalue(L, 1);
    lua_settable(L, -4);
  }
  return 1;
}

static int lobjc_registermethod (lua_State *L) { /** registermethod(obj,name,type) */
  id obj = lobjc_toid(L, 1);
  SEL sel = lobjc_checkselector(L, 2);
  const char *type = luaL_checkstring(L, 3);
  if ([obj respondsToSelector:@selector(lobjc_addMethod:type:)]) {
    [obj lobjc_addMethod:sel type:type];
  }
  return 0;
}



// TODO: find suitable place for these functions
static int lobjc_NSData_to_string (lua_State *L) { /** NSData_to_string(data) */
  NSData *data = lobjc_toid(L, 1);
  const void *bytes = [data bytes];
  if (bytes) {
    lua_pushlstring(L, (const char *)bytes, [data length]);
  } else {
    lua_pushnil(L);
  }
  return 1;
}

static int lobjc_string_to_NSData (lua_State *L) { /** string_to_NSData(str) */
  size_t length = 0;
  const void *ptr = luaL_checklstring(L, 1, &length);
  lobjc_pushid(L, [NSData dataWithBytes: ptr length: length]);
  return 1;
}


static const luaL_Reg funcs[] = {
  {"objc_lookUpClass",            lobjc_objc_lookUpClass},
  {"objc_getClass",               lobjc_objc_getClass},
  {"objc_getMetaClass",           lobjc_objc_getMetaClass},
  {"objc_allocateClassPair",      lobjc_objc_allocateClassPair},
  {"objc_registerClassPair",      lobjc_objc_registerClassPair},
  {"object_getClass",             lobjc_object_getClass},
  {"object_getClassName",         lobjc_object_getClassName},
  {"object_setClass",             lobjc_object_setClass},
  {"object_getIvar",              lobjc_object_getIvar},
  {"object_setIvar",              lobjc_object_setIvar},
  {"object_getInstanceVariable",  lobjc_object_getInstanceVariable},
  {"class_getName",               lobjc_class_getName},
  {"class_getSuperClass",         lobjc_class_getSuperclass},
  {"class_getInstanceVariable",   lobjc_class_getInstanceVariable},
  {"class_getInstanceMethod",     lobjc_class_getInstanceMethod},
  {"class_getClassMethod",        lobjc_class_getClassMethod},
  {"class_isMetaClass",           lobjc_class_isMetaClass},
  {"class_respondsToSelector",    lobjc_class_respondsToSelector},
  {"method_getName",              lobjc_method_getName},
  {"method_getNumberOfArguments", lobjc_method_getNumberOfArguments},
  {"method_getTypeEncoding",      lobjc_method_getTypeEncoding},
  {"method_exchangeImplementations", lobjc_method_exchangeImplementations},
  {"ivar_getName",                lobjc_ivar_getName},
  {"ivar_getTypeEncoding",        lobjc_ivar_getTypeEncoding},

  {"invoke", lobjc_invoke},
  {"gettypeencoding_x", lobjc_gettypeencoding_x},
  {"overridesignature", lobjc_overridesignature},
  {"registerinformalprotocol", lobjc_registerinformalprotocol},
  {"registermethod", lobjc_registermethod},

  {"NSData_to_string", lobjc_NSData_to_string},
  {"string_to_NSData", lobjc_string_to_NSData},
  {NULL, NULL}
};
/*
TODO:
method_setImplementation
method_getImplementation
*/

static void initcache (lua_State *L, const char *name, const char *mode) {
  lua_newtable(L);
  lua_pushstring(L, mode);
  lua_setfield(L, -2, "__mode");
  lua_pushvalue(L, -1);
  lua_setmetatable(L, -2);
  lua_setfield(L, LUA_REGISTRYINDEX, name);
}

// Prepare NSAutoreleasePool
static void setupautoreleasepool (lua_State *L) {
  lobjc_pushid_noretain(L, [[NSAutoreleasePool alloc] init]);
  lua_setfield(L, LUA_REGISTRYINDEX, "lobjc:autoreleasepool");
}

LUALIB_API int luaopen_objc_runtime (lua_State *L) {
  assert(run_simple_test(L));

  initcache(L, "lobjc:id_cache", "v");
  initcache(L, "lobjc:Method_cache", "v");
  initcache(L, "lobjc:Ivar_cache", "v");
  initcache(L, "lobjc:wrapper_cache", "kv");

  luaL_newmetatable(L, tname_id);
  luaL_register(L, NULL, idfuncs);

  luaL_newmetatable(L, tname_Method);
  luaL_newmetatable(L, tname_Ivar);

  setupautoreleasepool(L); // this must be called after luaL_newmetatable(...)

  lua_newtable(L);
  lua_setfield(L, LUA_REGISTRYINDEX, "lobjc:methodsig_override");

  lua_newtable(L);
  lua_setfield(L, LUA_REGISTRYINDEX, "lobjc:informal_protocols");

  luaL_register(L, "objc.runtime", funcs);

  luaL_getmetatable(L, tname_id);
  lua_setfield(L, -2, "__id_metatable");

  lua_pushinteger(L, sizeof(void *));
  lua_setfield(L, -2, "_PTRSIZE");

#if defined(__BIG_ENDIAN__)
  lua_pushliteral(L, "big");
#elif defined(__LITTLE_ENDIAN__)
  lua_pushliteral(L, "little");
#else
# error "unknown endian"
#endif
  lua_setfield(L, -2, "_ENDIAN");

  lua_pushcfunction(L, luaopen_objc_runtime_struct);
  lua_call(L, 0, 0);

  lua_pushcfunction(L, luaopen_objc_runtime_ffi);
  lua_call(L, 0, 0);

  return 1;
}
