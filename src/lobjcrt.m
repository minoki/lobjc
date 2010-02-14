/*
** Copyright (C) 2009-2010 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "lobjc.h"
#import "lobjc_runtimetypes.h"
#import "lobjc_invoke.h"
#import "lobjc_convert.h"
#import "typeencoding.h"
#import "lobjc_luawrapper.h"

#import "objc-runtime.h"
#import <lua.h>
#import <lauxlib.h>
#import <Foundation/Foundation.h>
#import <stdbool.h>
#import <assert.h>
#import <math.h>


static int id_gc (lua_State *L) {
  id *p = (id *)lua_touserdata(L, 1);
  if (*p != nil) {
#if defined(GNU_RUNTIME)
    // With GNU runtime, you die if you send a message to a metaclass
    bool is_meta_class = class_isMetaClass(*p);
    if (!is_meta_class)
#endif
    {
      [*p release];
    }
    *p = nil;
  }
  return 0;
}

static const luaL_Reg idfuncs[] = {
  {"__gc", id_gc},
  {NULL, NULL}
};


struct copyXXXList_aux_params {
  unsigned int count;
  void *list;
};

static int copyIvarList_aux (lua_State *L) {
  struct copyXXXList_aux_params *params = lua_touserdata(L, 1);
  Ivar *ivars = params->list;
  lua_createtable(L, params->count, 0);
  for (unsigned int i = 0; i < params->count; ++i) {
    lobjc_pushIvar(L, ivars[i]);
    lua_rawseti(L, -2, i+1);
  }
  return 1;
}

static int copyMethodList_aux (lua_State *L) {
  struct copyXXXList_aux_params *params = lua_touserdata(L, 1);
  Method *methods = params->list;
  lua_createtable(L, params->count, 0);
  for (unsigned int i = 0; i < params->count; ++i) {
    lobjc_pushMethod(L, methods[i]);
    lua_rawseti(L, -2, i+1);
  }
  return 1;
}

static int copyMethodDescriptionList_aux (lua_State *L) {
  struct copyXXXList_aux_params *params = lua_touserdata(L, 1);
  struct objc_method_description *methods = params->list;
  lua_createtable(L, params->count, 0);
  for (unsigned int i = 0; i < params->count; ++i) {
    lua_createtable(L, 0, 2);
    lobjc_pushselector(L, methods[i].name);
    lua_setfield(L, -2, "name");
    lua_pushstring(L, methods[i].types);
    lua_setfield(L, -2, "types");
    lua_rawseti(L, -2, i+1);
  }
  return 1;
}

static int copyProtocolList_aux (lua_State *L) {
  struct copyXXXList_aux_params *params = lua_touserdata(L, 1);
  Protocol **protocols = params->list;
  lua_createtable(L, params->count, 0);
  for (unsigned int i = 0; i < params->count; ++i) {
    lobjc_pushProtocol(L, protocols[i]);
    lua_rawseti(L, -2, i+1);
  }
  return 1;
}

#if !defined(DISABLE_OBJC2_PROPERTIES)
static int copyPropertyList_aux (lua_State *L) {
  struct copyXXXList_aux_params *params = lua_touserdata(L, 1);
  objc_property_t* props = params->list;
  lua_createtable(L, params->count, 0);
  for (unsigned int i = 0; i < params->count; ++i) {
    lobjc_pushproperty(L, props[i]);
    lua_rawseti(L, -2, i+1);
  }
  return 1;
}
#endif

static int copystring_aux (lua_State *L) {
  char *s = *(char **)lua_touserdata(L, 1);
  lua_pushstring(L, s);
  return 1;
}


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

static int lobjc_objc_getProtocol (lua_State *L) { /** objc_getProtocol(name) */
  lobjc_pushProtocol(L, objc_getProtocol(luaL_checkstring(L, 1)));
  return 1;
}

static bool class_conformsToProtocol_r(Class cls, Protocol *protocol) {
  if (cls == Nil) {
    return false;
  } else if (class_conformsToProtocol(cls, protocol)) {
    return true;
  } else {
    return class_conformsToProtocol_r(class_getSuperclass(cls), protocol);
  }
}

static int lobjc_objc_getClassList (lua_State *L) { /** objc_getClassList() */
  int n = objc_getClassList(NULL, 0);
  Class *buffer = lua_newuserdata(L, sizeof(Class)*n);
  objc_getClassList(buffer, n);
  lua_createtable(L, n, 0);
  int c = 1;
  for (int i = 0; i < n; ++i) {
    if (class_conformsToProtocol_r(buffer[i], @protocol(NSObject))) {
      lobjc_pushclass(L, buffer[i]);
      lua_rawseti(L, -2, c++);
    }
  }
  return 1;
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

static int lobjc_getInstanceVariable (lua_State *L) { /** getInstanceVariable(obj,name) */
  id obj = lobjc_toid(L, 1);
  const char *name = luaL_checkstring(L, 2);

  Class class = object_getClass(obj);
  Ivar ivar = class_getInstanceVariable(class, name);
  if (!ivar) {
    return luaL_error(L, "no such instance variable");
  }
  const char *type = ivar_getTypeEncoding(ivar);
  lobjc_conv_objctolua1(L, type, (unsigned char *)obj + ivar_getOffset(ivar));
  return 1;
}

static int lobjc_setInstanceVariable (lua_State *L) { /** setInstanceVariable(obj,name,value) */
  id obj = lobjc_toid(L, 1);
  const char *name = luaL_checkstring(L, 2);
  luaL_checkany(L, 3);

  Class class = object_getClass(obj);
  Ivar ivar = class_getInstanceVariable(class, name);
  if (!ivar) {
    return luaL_error(L, "no such instance variable");
  }
  const char *type = ivar_getTypeEncoding(ivar);
  lobjc_conv_luatoobjc1(L, 3, type, (unsigned char *)obj + ivar_getOffset(ivar));
  return 0;
}

static int lobjc_class_getName (lua_State *L) { /** class_getName(cls) */
  lua_pushstring(L, class_getName(lobjc_toclass(L, 1)));
  return 1;
}

static int lobjc_class_getSuperclass (lua_State *L) { /** class_getSuperclass(cls) */
  lobjc_pushclass(L, class_getSuperclass(lobjc_toclass(L, 1)));
  return 1;
}

static int lobjc_class_getInstanceVariable (lua_State *L) { /** class_getInstanceVariable(cls,name) */
  Class cls = lobjc_toclass(L, 1);
  const char *name = luaL_checkstring(L, 2);
  lobjc_pushIvar(L, class_getInstanceVariable(cls, name));
  return 1;
}

static int lobjc_class_getInstanceMethod (lua_State *L) { /** class_getInstanceMethod(cls,sel) */
  Class cls = lobjc_toclass(L, 1);
  SEL sel = lobjc_checkselector(L, 2);
  lobjc_pushMethod(L, class_getInstanceMethod(cls, sel));
  return 1;
}

static int lobjc_class_getClassMethod (lua_State *L) { /** class_getClassMethod(cls,sel) */
  Class cls = lobjc_toclass(L, 1);
  SEL sel = lobjc_checkselector(L, 2);
  lobjc_pushMethod(L, class_getClassMethod(cls, sel));
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

static int lobjc_class_addProtocol (lua_State *L) { /** class_addProtocol(cls,protocol) */
  Class cls = lobjc_toclass(L, 1);
  Protocol *protocol = lobjc_checkProtocol(L, 2);
  lua_pushboolean(L, class_addProtocol(cls, protocol));
  return 1;
}

static int lobjc_class_conformsToProtocol (lua_State *L) { /** class_conformsToProtocol(cls,protocol) */
  Class cls = lobjc_toclass(L, 1);
  Protocol *protocol = lobjc_checkProtocol(L, 2);
  lua_pushboolean(L, class_conformsToProtocol(cls, protocol));
  return 1;
}

static int lobjc_class_copyIvarList (lua_State *L) { /** class_copyIvarList(cls) */
  Class cls = lobjc_toclass(L, 1);
  struct copyXXXList_aux_params params = {0, NULL};

  lua_pushvalue(L, lua_upvalueindex(1));
  lua_pushlightuserdata(L, &params);

  Ivar *ivars = class_copyIvarList(cls, &params.count);
  params.list = ivars;
  int err = lua_pcall(L, 1, 1, 0);
  free(ivars);

  return err == 0 ? 1 : lua_error(L);
}

static int lobjc_class_copyMethodList (lua_State *L) { /** class_copyMethodList(cls) */
  Class cls = lobjc_toclass(L, 1);
  struct copyXXXList_aux_params params = {0, NULL};

  lua_pushvalue(L, lua_upvalueindex(1));
  lua_pushlightuserdata(L, &params);

  Method *methods = class_copyMethodList(cls, &params.count);
  params.list = methods;
  int err = lua_pcall(L, 1, 1, 0);
  free(methods);

  return err == 0 ? 1 : lua_error(L);
}

static int lobjc_class_copyProtocolList (lua_State *L) { /** class_copyProtocolList(cls) */
  Class cls = lobjc_toclass(L, 1);
  struct copyXXXList_aux_params params = {0, NULL};

  lua_pushvalue(L, lua_upvalueindex(1));
  lua_pushlightuserdata(L, &params);

  Protocol **protocols = class_copyProtocolList(cls, &params.count);
  params.list = protocols;
  int err = lua_pcall(L, 1, 1, 0);
  free(protocols);

  return err == 0 ? 1 : lua_error(L);
}

static int lobjc_objc_copyProtocolList (lua_State *L) { /** objc_copyProtocolList() */
  struct copyXXXList_aux_params params = {0, NULL};

  lua_pushvalue(L, lua_upvalueindex(1));
  lua_pushlightuserdata(L, &params);

  Protocol **protocols = objc_copyProtocolList(&params.count);
  params.list = protocols;
  int err = lua_pcall(L, 1, 1, 0);
  free(protocols);

  return err == 0 ? 1 : lua_error(L);
}

static int lobjc_class_getInstanceSize (lua_State *L) { /** class_getInstanceSize(cls) */
  lua_pushnumber(L, class_getInstanceSize(lobjc_toclass(L, 1)));
  return 1;
}

#if !defined(DISABLE_OBJC2_PROPERTIES)
static int lobjc_class_getProperty (lua_State *L) { /** class_getProperty(cls,name) */
  Class cls = lobjc_toclass(L, 1);
  const char *name = luaL_checkstring(L, 2);
  lobjc_pushproperty(L, class_getProperty(cls, name));
  return 1;
}

static int lobjc_class_copyPropertyList (lua_State *L) { /** class_copyPropertyList(cls) */
  Class cls = lobjc_toclass(L, 1);
  struct copyXXXList_aux_params params = {0, NULL};

  lua_pushvalue(L, lua_upvalueindex(1));
  lua_pushlightuserdata(L, &params);

  objc_property_t *props = class_copyPropertyList(cls, &params.count);
  params.list = props;
  int err = lua_pcall(L, 1, 1, 0);
  free(props);

  return err == 0 ? 1 : lua_error(L);
}
#endif

static int lobjc_method_getName (lua_State *L) { /** method_getName(method) */
  Method method = lobjc_checkMethod(L, 1);
  lobjc_pushselector(L, method_getName(method));
  return 1;
}

static int lobjc_method_getNumberOfArguments (lua_State *L) { /** method_getNumberOfArguments(method) */
  Method method = lobjc_checkMethod(L, 1);
  lua_pushinteger(L, method_getNumberOfArguments(method));
  return 1;
}

static int lobjc_method_getTypeEncoding (lua_State *L) { /** method_getTypeEncoding(method) */
  Method method = lobjc_checkMethod(L, 1);
  lua_pushstring(L, method_getTypeEncoding(method));
  return 1;
}

static int lobjc_method_getReturnType (lua_State *L) { /** method_getReturnType(method) */
  Method method = lobjc_checkMethod(L, 1);
  char *type = NULL;
  lua_pushvalue(L, lua_upvalueindex(1));
  lua_pushlightuserdata(L, &type);
  type = method_copyReturnType(method);
  int err = lua_pcall(L, 1, 1, 0);
  free(type);
  return err == 0 ? 1 : lua_error(L);
}

static int lobjc_method_getArgumentType (lua_State *L) { /** method_getArgumentType(method,index) */
  Method method = lobjc_checkMethod(L, 1);
  unsigned int index = (unsigned int)lua_tointeger(L, 2);
  char *type = NULL;
  lua_pushvalue(L, lua_upvalueindex(1));
  lua_pushlightuserdata(L, &type);
  type = method_copyArgumentType(method, index);
  int err = lua_pcall(L, 1, 1, 0);
  free(type);
  return err == 0 ? 1 : lua_error(L);
}

static int lobjc_method_exchangeImplementations (lua_State *L) { /** method_exchangeImplementations(m1,m2) */
  Method m1 = lobjc_checkMethod(L, 1);
  Method m2 = lobjc_checkMethod(L, 2);
  method_exchangeImplementations(m1, m2);
  return 0;
}

static int lobjc_ivar_getName (lua_State *L) { /** ivar_getName(ivar) */
  lua_pushstring(L, ivar_getName(lobjc_checkIvar(L, 1)));
  return 1;
}

static int lobjc_ivar_getTypeEncoding (lua_State *L) { /** ivar_getTypeEncoding(ivar) */
  lua_pushstring(L, ivar_getTypeEncoding(lobjc_checkIvar(L, 1)));
  return 1;
}

static int lobjc_ivar_getOffset (lua_State *L) { /** ivar_getOffset(ivar) */
  lua_pushinteger(L, ivar_getOffset(lobjc_checkIvar(L, 1)));
  return 1;
}

static int lobjc_protocol_getName (lua_State *L) { /** protocol_getName(protocol) */
  lua_pushstring(L, protocol_getName(lobjc_checkProtocol(L, 1)));
  return 1;
}

static int lobjc_protocol_isEqual (lua_State *L) { /** protocol_isEqual(a,b) */
  Protocol *a = lobjc_checkProtocol(L, 1);
  Protocol *b = lobjc_checkProtocol(L, 2);
  lua_pushboolean(L, protocol_isEqual(a, b));
  return 1;
}

static int lobjc_protocol_copyMethodDescriptionList (lua_State *L) { /** protocol_copyMethodDescriptionList(protocol,isRequiredMethod,isInstanceMethod) */
  Protocol *protocol = lobjc_checkProtocol(L, 1);
  BOOL isRequiredMethod = lua_toboolean(L, 2);
  BOOL isInstanceMethod = lua_toboolean(L, 3);
  struct copyXXXList_aux_params params = {0, NULL};

  lua_pushvalue(L, lua_upvalueindex(1));
  lua_pushlightuserdata(L, &params);

  struct objc_method_description *methods = protocol_copyMethodDescriptionList(protocol, isRequiredMethod, isInstanceMethod, &params.count);
  params.list = methods;
  int err = lua_pcall(L, 1, 1, 0);
  free(methods);

  return err == 0 ? 1 : lua_error(L);
}

static int lobjc_protocol_getMethodDescription (lua_State *L) { /** protocol_getMethodDescription(protocol,sel,isRequiredMethod,isInstanceMethod) */
  Protocol *protocol = lobjc_checkProtocol(L, 1);
  SEL sel = lobjc_checkselector(L, 2);
  BOOL isRequiredMethod = lua_toboolean(L, 3);
  BOOL isInstanceMethod = lua_toboolean(L, 4);
  struct objc_method_description desc = protocol_getMethodDescription(protocol, sel, isRequiredMethod, isInstanceMethod);
  if (desc.name == NULL) {
    lua_pushnil(L);
  } else {
    lua_createtable(L, 0, 2);
    lobjc_pushselector(L, desc.name);
    lua_setfield(L, -2, "name");
    lua_pushstring(L, desc.types);
    lua_setfield(L, -2, "types");
  }
  return 1;
}

#if !defined(DISABLE_OBJC2_PROPERTIES)
static int lobjc_protocol_copyPropertyList (lua_State *L) { /** protocol_copyPropertyList(protocol) */
  Protocol *protocol = lobjc_checkProtocol(L, 1);
  struct copyXXXList_aux_params params = {0, NULL};

  lua_pushvalue(L, lua_upvalueindex(1));
  lua_pushlightuserdata(L, &params);

  objc_property_t *props = protocol_copyPropertyList(protocol, &params.count);
  params.list = props;
  int err = lua_pcall(L, 1, 1, 0);
  free(props);

  return err == 0 ? 1 : lua_error(L);
}

static int lobjc_protocol_getProperty (lua_State *L) { /** protocol_getProperty(protocol,name,isRequiredProperty,isInstanceProperty) */
  Protocol *protocol = lobjc_checkProtocol(L, 1);
  const char *name = luaL_checkstring(L, 2);
  BOOL isRequiredProperty = lua_toboolean(L, 3);
  BOOL isInstanceProperty = lua_toboolean(L, 4);
  lobjc_pushproperty(L, protocol_getProperty(protocol, name, isRequiredProperty, isInstanceProperty));
  return 1;
}
#endif

static int lobjc_protocol_copyProtocolList (lua_State *L) { /** protocol_copyProtocolList(cls) */
  Protocol *protocol = lobjc_checkProtocol(L, 1);
  struct copyXXXList_aux_params params = {0, NULL};

  lua_pushvalue(L, lua_upvalueindex(1));
  lua_pushlightuserdata(L, &params);

  Protocol **protocols = protocol_copyProtocolList(protocol, &params.count);
  params.list = protocols;
  int err = lua_pcall(L, 1, 1, 0);
  free(protocols);

  return err == 0 ? 1 : lua_error(L);
}

static int lobjc_protocol_conformsToProtocol (lua_State *L) { /** protocol_conformsToProtocol(a,b) */
  Protocol *a = lobjc_checkProtocol(L, 1);
  Protocol *b = lobjc_checkProtocol(L, 2);
  lua_pushboolean(L, protocol_conformsToProtocol(a, b));
  return 1;
}

#if !defined(DISABLE_OBJC2_PROPERTIES)
static int lobjc_property_getName (lua_State *L) { /** property_getName(prop) */
  lua_pushstring(L, property_getName(lobjc_checkproperty(L, 1)));
  return 1;
}

static int lobjc_property_getAttributes (lua_State *L) { /** property_getAttributes(prop) */
  lua_pushstring(L, property_getAttributes(lobjc_checkproperty(L, 1)));
  return 1;
}
#endif


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
    m = class ? class_getInstanceMethod(class, sel) : NULL;
    if (!m) {
      lua_pop(L, 1); // pop table
      return method_getTypeEncoding(method);
    }
    goto retry;
  }
}

static bool isReturnValueAlreadyRetained(SEL sel) {
  return false // TODO: take into account already_retained attribute in BridgeSupport
    || sel_isEqual(sel, @selector(alloc))
    || sel_isEqual(sel, @selector(allocWithZone:))
    || sel_isEqual(sel, @selector(new))
    || sel_isEqual(sel, @selector(newObject))
    || sel_isEqual(sel, @selector(copy))
    || sel_isEqual(sel, @selector(copyWithZone:))
    || sel_isEqual(sel, @selector(mutableCopy))
    || sel_isEqual(sel, @selector(mutableCopyWithZone:));
}

static int lobjc_invoke (lua_State *L) { /** invoke(obj,sel,...) */
  id obj        = lobjc_toid(L, 1);
  SEL sel       = sel_registerName(luaL_checkstring(L, 2));
  Class class   = object_getClass(obj);
  bool already_retained = isReturnValueAlreadyRetained(sel);
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

static int lobjc_invokewithclass (lua_State *L) { /** invokewithclass(class,obj,sel,...) */
  Class class   = lobjc_toclass(L, 1);
  id obj        = lobjc_toid(L, 2);
  SEL sel       = sel_registerName(luaL_checkstring(L, 3));
  assert([obj isKindOfClass:class]);
  bool already_retained = isReturnValueAlreadyRetained(sel);
  Method method = class_getInstanceMethod(class, sel);
  if (!method) {
    return 0;
  }
  IMP impl = method_getImplementation(method);
  const char *e = lobjc_method_getTypeEncoding_ex(L, class, sel, method);
  unsigned argc = method_getNumberOfArguments(method);

  return lobjc_invoke_func(L, (void (*)())impl, e, argc, 2, already_retained);
}

static int lobjc_gettypeencoding_x (lua_State *L) { /** gettypeencoding_x(obj,sel) */
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
  Method method = lobjc_checkMethod(L, 1);
  luaL_checkstring(L, 2);
  lua_getfield(L, LUA_REGISTRYINDEX, "lobjc:methodsig_override");
  lua_pushlightuserdata(L, (void *)method);
  lua_pushvalue(L, 2);
  lua_rawset(L, -3);
  return 0;
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



static int lobjc_createClass (lua_State *L) { /** createClass(name,super,fields) */
  const char *classname = luaL_checkstring(L, 1);
  Class superclass = lobjc_toclass(L, 2);
  bool hasfields = lua_istable(L, 3);
  Class class = objc_allocateClassPair(superclass, classname, 0);

  if (hasfields) {
    int len = lua_objlen(L, 3);
    for (int i = 1; i <= len; ++i) {
      lua_rawgeti(L, 3, i);
      const char *fieldname = lua_tostring(L, -1);
      class_addIvar(class, fieldname, sizeof(id), log2(sizeof(id)), @encode(id));
      lua_pop(L, 1);
    }
  }

  objc_registerClassPair(class);

  lobjc_pushclass(L, class);
  return 1;
}

static int lobjc_class_addMethod (lua_State *L) { /** class_addMethod(cls,sel,imp,types) */
  Class cls = lobjc_toclass(L, 1);
  SEL sel = lobjc_checkselector(L, 2);
  luaL_checktype(L, 3, LUA_TFUNCTION);
  const char *types = luaL_checkstring(L, 4);

  lua_pushvalue(L, 3);
  IMP imp = lobjc_buildIMP(L, types);
  luaL_ref(L, LUA_REGISTRYINDEX);
  
  lua_pushboolean(L, class_addMethod(cls, sel, imp, types));
  return 1;
}



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
  {"objc_getProtocol",            lobjc_objc_getProtocol},
  {"objc_getClassList",           lobjc_objc_getClassList},
  {"object_getClass",             lobjc_object_getClass},
  {"object_getClassName",         lobjc_object_getClassName},
  {"object_setClass",             lobjc_object_setClass},
  {"class_getName",               lobjc_class_getName},
  {"class_getSuperclass",         lobjc_class_getSuperclass},
  {"class_getInstanceVariable",   lobjc_class_getInstanceVariable},
  {"class_getInstanceMethod",     lobjc_class_getInstanceMethod},
  {"class_getClassMethod",        lobjc_class_getClassMethod},
  {"class_isMetaClass",           lobjc_class_isMetaClass},
  {"class_respondsToSelector",    lobjc_class_respondsToSelector},
  {"class_addProtocol",           lobjc_class_addProtocol},
  {"class_conformsToProtocol",    lobjc_class_conformsToProtocol},
  {"class_getInstanceSize",       lobjc_class_getInstanceSize},
#if !defined(DISABLE_OBJC2_PROPERTIES)
  {"class_getProperty",           lobjc_class_getProperty},
#endif
  {"method_getName",              lobjc_method_getName},
  {"method_getNumberOfArguments", lobjc_method_getNumberOfArguments},
  {"method_getTypeEncoding",      lobjc_method_getTypeEncoding},
  {"method_exchangeImplementations", lobjc_method_exchangeImplementations},
  {"ivar_getName",                lobjc_ivar_getName},
  {"ivar_getTypeEncoding",        lobjc_ivar_getTypeEncoding},
  {"ivar_getOffset",              lobjc_ivar_getOffset},
  {"protocol_getName",            lobjc_protocol_getName},
  {"protocol_isEqual",            lobjc_protocol_isEqual},
  {"protocol_getMethodDescription", lobjc_protocol_getMethodDescription},
#if !defined(DISABLE_OBJC2_PROPERTIES)
  {"protocol_getProperty",        lobjc_protocol_getProperty},
#endif
  {"protocol_conformsToProtocol", lobjc_protocol_conformsToProtocol},
#if !defined(DISABLE_OBJC2_PROPERTIES)
  {"property_getName",            lobjc_property_getName},
  {"property_getAttributes",      lobjc_property_getAttributes},
#endif

/* These functions need auxiliary functions as upvalues
  {"objc_copyProtocolList",       lobjc_objc_copyProtocolList},
  {"class_copyIvarList",          lobjc_class_copyIvarList},
  {"class_copyMethodList",        lobjc_class_copyMethodList},
  {"class_copyProtocolList",      lobjc_class_copyProtocolList},
  {"class_copyPropertyList",      lobjc_class_copyPropertyList},
  {"method_getReturnType",        lobjc_method_getReturnType},
  {"method_getArgumentType",      lobjc_method_getArgumentType},
  {"protocol_copyMethodDescriptionList", lobjc_protocol_copyMethodDescriptionList},
  {"protocol_copyPropertyList",   lobjc_protocol_copyPropertyList},
  {"protocol_copyProtocolList",   lobjc_protocol_copyProtocolList},
*/

  {"invoke", lobjc_invoke},
  {"invokewithclass", lobjc_invokewithclass},
  {"gettypeencoding_x", lobjc_gettypeencoding_x},
  {"overridesignature", lobjc_overridesignature},
  {"registermethod", lobjc_registermethod},
  {"createClass", lobjc_createClass},
  {"class_addMethod", lobjc_class_addMethod},

  {"getInstanceVariable",  lobjc_getInstanceVariable},
  {"setInstanceVariable",  lobjc_setInstanceVariable},

  {"NSData_to_string", lobjc_NSData_to_string},
  {"string_to_NSData", lobjc_string_to_NSData},
  {NULL, NULL}
};
/*
TODO:
method_setImplementation
method_getImplementation
*/

static const luaL_Reg sublibs[] = {
  {"objc.runtime.struct", luaopen_objc_runtime_struct},
  {"objc.runtime.ffi", luaopen_objc_runtime_ffi},
  {"objc.runtime.pointer", luaopen_objc_runtime_pointer},
  {"objc.runtime.bridgesupport", luaopen_objc_runtime_bridgesupport},
  {"objc.runtime.cfunction", luaopen_objc_runtime_cfunction},
  {NULL, NULL}
};

static void initcache (lua_State *L, const char *name, const char *mode) {
  lua_newtable(L);
  lua_pushstring(L, mode);
  lua_setfield(L, -2, "__mode");
  lua_pushvalue(L, -1);
  lua_setmetatable(L, -2);
  lua_setfield(L, LUA_REGISTRYINDEX, name);
}

static void auxopen (lua_State *L, const char *name,
                     lua_CFunction func, lua_CFunction auxfunc) {
  if (auxfunc == NULL) {
    lua_pushvalue(L, -1);
    lua_pushcclosure(L, func, 1);
    lua_setfield(L, -3, name);
  } else {
    lua_pushcfunction(L, auxfunc);
    lua_pushcclosure(L, func, 1);
    lua_setfield(L, -2, name);
  }
}

// Prepare NSAutoreleasePool
static void setupautoreleasepool (lua_State *L) {
  lobjc_pushid_noretain(L, [[NSAutoreleasePool alloc] init]);
  lua_setfield(L, LUA_REGISTRYINDEX, "lobjc:autoreleasepool");
}

static void setplatforminfo (lua_State *L) {
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

#if defined(__NEXT_RUNTIME__)
  lua_pushliteral(L, "next");
  lua_setfield(L, -2, "_RUNTIME");
#elif defined(GNU_RUNTIME)
  lua_pushliteral(L, "gnu");
  lua_setfield(L, -2, "_RUNTIME");
#else
#error "unknown Objective-C runtime"
#endif

#if defined(GNUSTEP)
  lua_pushboolean(L, 1);
  lua_setfield(L, -2, "_GNUSTEP");
#endif
}

LUALIB_API int luaopen_objc_runtime (lua_State *L) {
  initcache(L, "lobjc:wrapper_cache", "kv");
  initcache(L, "lobjc:wrapperinfo", "k");

  lua_pushcfunction(L, luaopen_objc_runtime_types);
  lua_call(L, 0, 0);

  luaL_getmetatable(L, tname_id);
  luaL_register(L, NULL, idfuncs);
  lua_pop(L, 1);

  setupautoreleasepool(L); // this must be called after luaL_newmetatable(...)

  lua_newtable(L);
  lua_setfield(L, LUA_REGISTRYINDEX, "lobjc:methodsig_override");

  luaL_register(L, "objc.runtime", funcs);
  /* These functions need auxiliary functions as upvalues */
  auxopen(L, "class_copyIvarList", lobjc_class_copyIvarList, copyIvarList_aux);
  auxopen(L, "class_copyMethodList", lobjc_class_copyMethodList, copyMethodList_aux);
  lua_pushcfunction(L, copyProtocolList_aux);
  auxopen(L, "objc_copyProtocolList", lobjc_objc_copyProtocolList, NULL);
  auxopen(L, "class_copyProtocolList", lobjc_class_copyProtocolList, NULL);
  auxopen(L, "protocol_copyProtocolList", lobjc_protocol_copyProtocolList, NULL);
  lua_pop(L, 1);
#if !defined(DISABLE_OBJC2_PROPERTIES)
  lua_pushcfunction(L, copyPropertyList_aux);
  auxopen(L, "class_copyPropertyList", lobjc_class_copyPropertyList, NULL);
  auxopen(L, "protocol_copyPropertyList", lobjc_protocol_copyPropertyList, NULL);
  lua_pop(L, 1);
#endif
  auxopen(L, "protocol_copyMethodDescriptionList",
    lobjc_protocol_copyMethodDescriptionList, copyMethodDescriptionList_aux);
  lua_pushcfunction(L, copystring_aux);
  auxopen(L, "method_getReturnType", lobjc_method_getReturnType, NULL);
  auxopen(L, "method_getArgumentType", lobjc_method_getArgumentType, NULL);
  lua_pop(L, 1);

  setplatforminfo(L);

  for (const luaL_Reg *lib = sublibs; lib->func; ++lib) {
    lua_pushcfunction(L, lib->func);
    lua_pushstring(L, lib->name);
    lua_call(L, 1, 0);
  }

  return 1;
}
