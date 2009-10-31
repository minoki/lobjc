/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#ifndef LOBJC_COMPAT_H
#define LOBJC_COMPAT_H

#if defined(__NEXT_RUNTIME__)

#elif defined(GNU_RUNTIME)

#include <stdint.h>
#include <objc/objc-api.h>
#include <objc/encoding.h>

#include <Foundation/NSObjCRuntime.h>
#undef sel_getName
#undef sel_registerName
#undef objc_lookUpClass
#undef objc_getClass
#undef class_getInstanceMethod
#undef class_getClassMethod

#define objc_lookUpClass(name)   objc_lookup_class(name)
#define objc_getClass(name)      objc_get_class(name)
#define sel_getName(sel)         sel_get_name(sel)
#define sel_registerName(sel)    sel_register_name(sel)
#define sel_isEqual(a,b)         sel_eq(a,b)
#define object_getClassName(obj) object_get_class_name(obj)
#define class_getName(cls)       class_get_class_name(cls)
#define class_isMetaClass(cls)   class_is_meta_class(cls)
#define class_getInstanceMethod(cls,name) class_get_instance_method(cls,name)
#define method_getNumberOfArguments(m)    method_get_number_of_arguments(m)

#define Method Method_t
#define Ivar Ivar_t

static inline int ivar_getOffset(Ivar ivar) {
  return ivar ? ivar->ivar_offset : 0;
}
static inline const char *ivar_getTypeEncoding(Ivar ivar) {
  return ivar ? ivar->ivar_type : NULL;
}
static inline const char *ivar_getName(Ivar ivar) {
  return ivar ? ivar->ivar_name : NULL;
}
static inline SEL method_getName(Method method) {
  return method ? method->method_name : NULL;
}
static inline const char *method_getTypeEncoding(Method method) {
  return method ? method->method_types : NULL;
}
static inline IMP method_getImplementation(Method method) {
  return method ? method->method_imp : NULL;
}
static inline Class object_getClass(id obj) {
  return obj ? obj->class_pointer : Nil;
}
static inline Class class_getSuperclass(Class cls) {
  return cls ? cls->super_class : Nil;
}
static inline Method class_getClassMethod(Class cls, SEL sel) {
  return cls ? class_get_class_method(cls->class_pointer, sel) : NULL;
}

Class objc_getMetaClass(const char *name);
Protocol *objc_getProtocol(const char *name);
Class objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes);
void  objc_registerClassPair(Class cls);
int   objc_getClassList(Class *buffer, int bufferLen);
Protocol **objc_copyProtocolList(unsigned int *outCount);
Class object_setClass(id obj, Class cls);
Ivar  object_getInstanceVariable(id obj, const char *name, void **outValue);
Ivar  object_setInstanceVariable(id obj, const char *name, void *value);
id    object_getIvar(id obj, Ivar ivar);
void  object_setIvar(id obj, Ivar ivar, id value);
BOOL  class_respondsToSelector(Class cls, SEL sel);
BOOL  class_addIvar(Class cls, const char *name, size_t size, uint8_t alignment, const char *types);
Ivar  class_getInstanceVariable(Class cls, const char *name);
BOOL  class_addMethod(Class cls, SEL name, IMP imp, const char *types);
BOOL  class_addProtocol(Class cls, Protocol *protocol);
BOOL  class_conformsToProtocol(Class cls, Protocol *protocol);
Ivar *class_copyIvarList(Class cls, unsigned int *outCount);
Method *class_copyMethodList(Class cls, unsigned int *outCount);
Protocol **class_copyProtocolList(Class cls, unsigned int *outCount);
void  method_exchangeImplementations(Method m1, Method m2);

#else

#error "unknown Objective-C runtime"

#endif /* NeXT runtime / GNU runtime */

#if !defined(__BIG_ENDIAN__) && !defined(__LITTLE_ENDIAN__)
#include <endian.h>
#if __BYTE_ORDER == __BIG_ENDIAN
#define __BIG_ENDIAN__
#elif __BYTE_ORDER == __LITTLE_ENDIAN
#define __LITTLE_ENDIAN__
#endif
#endif

#endif
