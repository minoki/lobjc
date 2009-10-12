/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#include "lobjc-compat.h"

#if !defined(__NEXT_RUNTIME__) /* GNU runtime */

Class objc_getMetaClass(const char *name) {
  return class_get_meta_class(objc_get_class(name));
}

Class objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes) {
  // NOT IMPLEMENTED YET
  return Nil;
}

void objc_registerClassPair(Class cls) {
  // NOT IMPLEMENTED YET
}

Class object_setClass(id obj, Class cls) {
  if (obj == nil) {
    return Nil;
  }
  Class oldcls = obj->class_pointer;
  obj->class_pointer = cls;
  return oldcls;
}

Ivar object_getInstanceVariable(id obj, const char *name, void **outValue) {
  Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
  char *ptr = (char *)obj + ivar->ivar_offset;
  *outValue = *(void **)ptr;
  return ivar;
}

Ivar object_setInstanceVariable(id obj, const char *name, void *value) {
  Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
  char *ptr = (char *)obj + ivar->ivar_offset;
  *(void **)ptr = value;
  return ivar;
}

id object_getIvar(id obj, Ivar ivar) {
  if (!obj || !ivar) {
    return nil;
  }
  assert(strcmp(ivar->ivar_type, @encode(id)) == 0);
  char *ptr = (char *)obj + ivar->ivar_offset;
  return *(id *)ptr;
}

void object_setIvar(id obj, Ivar ivar, id value) {
  if (!obj || !ivar) {
    return;
  }
  assert(strcmp(ivar->ivar_type, @encode(id)) == 0);
  char *ptr = (char *)obj + ivar->ivar_offset;
  *(id *)ptr = value;
}

BOOL class_respondsToSelector(Class cls, SEL sel) {
  if (cls == Nil) {
    return NO;
  }
  struct objc_method_list *methods = cls->methods;
  while (methods) {
    for (int i = 0; i < methods->method_count; ++i) {
      Method method = &methods->method_list[i];
      if (sel_eq(method->method_name, sel)) {
        return YES;
      }
    }
    methods = methods->method_next;
  }
  if (cls->super_class) {
    return class_respondsToSelector(cls->super_class, sel);
  } else {
    return NO;
  }
//  return [cls instancesRespondTo:sel];
}

BOOL class_addIvar(Class cls, const char *name, size_t size, uint8_t alignment, const char *types) {
  // NOT IMPLEMENTED YET
  return NO;
}

Ivar class_getInstanceVariable(Class cls, const char *name) {
  if (cls == Nil) {
    return NULL;
  }
  struct objc_ivar_list *ivars = cls->ivars;
  for (int i = 0; i < ivars->ivar_count; ++i) {
    struct objc_ivar *ivar = &ivars->ivar_list[i];
    if (strcmp(ivar->ivar_name, name) == 0) {
      return ivar;
    }
  }
  return NULL;
}

BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types) {
  // NOT IMPLEMENTED YET
  return NO;
}

void method_exchangeImplementations(Method m1, Method m2) {
  IMP tmp = m1->method_imp;
  m1->method_imp = m2->method_imp;
  m2->method_imp = tmp;
}


#endif
