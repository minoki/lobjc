/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#include "objc-runtime.h"

#if defined(GNU_RUNTIME)

#include <objc/Protocol.h>

Class objc_getMetaClass(const char *name) {
  return class_get_meta_class(objc_get_class(name));
}

Protocol *objc_getProtocol(const char *name) {
  // NOT IMPLEMENTED YET
  return nil;
}

Class objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes) {
  // NOT IMPLEMENTED YET
  return Nil;
}

void objc_registerClassPair(Class cls) {
  // NOT IMPLEMENTED YET
}

int objc_getClassList(Class *buffer, int bufferLen) {
  Class cls;
  void *state = NULL;
  int n = 0;
  while ((cls = objc_next_class(&state))) {
    if (buffer && bufferLen > n) {
      buffer[n] = cls;
    }
    ++n;
  }
  return n;
}

Protocol **objc_copyProtocolList(unsigned int *outCount) {
  // NOT IMPLEMENTED YET
  if (outCount) {
    *outCount = 0;
  }
  return NULL;
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
  if (ivars) {
    for (int i = 0; i < ivars->ivar_count; ++i) {
      struct objc_ivar *ivar = &ivars->ivar_list[i];
      if (strcmp(ivar->ivar_name, name) == 0) {
        return ivar;
      }
    }
  }
  return class_getInstanceVariable(cls->super_class, name);
}

BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types) {
  // NOT IMPLEMENTED YET
  return NO;
}

BOOL class_addProtocol(Class cls, Protocol *protocol) {
  // NOT IMPLEMENTED YET
  return NO;
}

BOOL class_conformsToProtocol(Class cls, Protocol *protocol) {
  if (cls == Nil || protocol == nil) {
    return NO;
  }
  struct objc_protocol_list *protocols = cls->protocols;
  while (protocols) {
    for (size_t i = 0; i < protocols->count; ++i) {
      if ([protocols->list[i] conformsTo:protocol]) {
        return YES;
      }
    }
    protocols = protocols->next;
  }
  return NO;
}

Ivar *class_copyIvarList(Class cls, unsigned int *outCount) {
  if (cls == Nil) {
    return NULL;
  }
  unsigned int count = 0;
  struct objc_ivar_list *ivars = cls->ivars;
  if (ivars) {
    count = ivars->ivar_count;
  }
  if (outCount) {
    *outCount = count;
  }
  if (count == 0) {
    return NULL;
  }
  Ivar *copied_ivars = malloc(sizeof(Ivar)*(count+1));
  if (!copied_ivars) {
    return NULL;
  }
  {
    Ivar *curr = copied_ivars;
    for (int i = 0; i < ivars->ivar_count; ++i) {
      *curr++ = &ivars->ivar_list[i];
    }
    *curr = NULL;
  }
  return copied_ivars;
}

Method *class_copyMethodList(Class cls, unsigned int *outCount) {
  if (cls == Nil) {
    return NULL;
  }
  unsigned int count = 0;
  {
    struct objc_method_list *methods = cls->methods;
    while (methods) {
      count += methods->method_count;
      methods = methods->method_next;
    }
  }
  if (outCount) {
    *outCount = count;
  }
  if (count == 0) {
    return NULL;
  }
  Method *copied_methods = malloc(sizeof(Method)*(count+1));
  if (!copied_methods) {
    return NULL;
  }
  {
    struct objc_method_list *methods = cls->methods;
    Method *curr = copied_methods;
    while (methods) {
      for (int i = 0; i < methods->method_count; ++i) {
        *curr++ = &methods->method_list[i];
      }
      methods = methods->method_next;
    }
    *curr = NULL;
  }
  return copied_methods;
}

Protocol **class_copyProtocolList(Class cls, unsigned int *outCount) {
  if (cls == Nil) {
    return NULL;
  }
  unsigned int count = 0;
  {
    struct objc_protocol_list *protocols = cls->protocols;
    while (protocols) {
      count += protocols->count;
      protocols = protocols->next;
    }
  }
  if (outCount) {
    *outCount = count;
  }
  if (count == 0) {
    return NULL;
  }
  Protocol **copied_protocols = malloc(sizeof(Protocol *)*(count+1));
  if (!copied_protocols) {
    return NULL;
  }
  {
    struct objc_protocol_list *protocols = cls->protocols;
    Protocol **curr = copied_protocols;
    while (protocols) {
      for (int i = 0; i < protocols->count; ++i) {
        *curr++ = protocols->list[i];
      }
      protocols = protocols->next;
    }
    *curr = NULL;
  }
  return copied_protocols;
}

void method_exchangeImplementations(Method m1, Method m2) {
  IMP tmp = m1->method_imp;
  m1->method_imp = m2->method_imp;
  m2->method_imp = tmp;
}


#endif
