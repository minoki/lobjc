/*
** Copyright (C) 2009 ARATA Mizuki
** See file COPYRIGHT for more information
*/

#import "lobjc.h"

#import <lua.h>
#import <lauxlib.h>
#import <Foundation/Foundation.h>
#import <stdbool.h>


@interface lobjc_BridgeSupportParserDelegate : NSObject {
  lua_State *L;
}
- initWithLuaState:(lua_State *)L_;
@end
@implementation lobjc_BridgeSupportParserDelegate
- initWithLuaState:(lua_State *)L_ {
  self = [super init];
  if (self) {
    L = L_;
  }
  return self;
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
                                        namespaceURI:(NSString *)namespaceURI
                                       qualifiedName:(NSString *)qName
                                          attributes:(NSDictionary *)attributeDict {
  lua_newtable(L);

  lua_pushvalue(L, -1);
  lua_rawseti(L, -3, lua_objlen(L, -3)+1);

  lua_pushstring(L, [elementName UTF8String]);
  lua_setfield(L, -2, "tag");
  NSEnumerator *e = [attributeDict keyEnumerator];
  for (NSString *key; (key = [e nextObject]); ) {
    lua_pushstring(L, [[attributeDict objectForKey:key] UTF8String]);
    lua_setfield(L, -2, [key UTF8String]);
  }
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName
                                        namespaceURI:(NSString *)namespaceURI
                                       qualifiedName:(NSString *)qName {
  lua_pop(L, 1);
}
@end

static int bs_parsexml (lua_State *L) {
  size_t len = 0;
  const char *str = luaL_checklstring(L, 1, &len);
  lua_newtable(L);
  id pool = [[NSAutoreleasePool alloc] init];

  NSData *data = [NSData dataWithBytes:str length:len];
  NSXMLParser *parser = [[[NSXMLParser alloc] initWithData:data] autorelease];
  id myDelegate = [[[lobjc_BridgeSupportParserDelegate alloc] initWithLuaState:L] autorelease];
  [parser setDelegate:myDelegate];
  [parser setShouldResolveExternalEntities:YES];

  if (![parser parse]) {
    lua_pushnil(L);
    lua_pushstring(L, [[[parser parserError] description] UTF8String]);
    [pool release];
    return 2;
  }
  [pool release];
  lua_rawgeti(L, -1, 1);
  return 1;
}

static const luaL_Reg funcs[] = {
  {"parsexml", bs_parsexml},
  {NULL, NULL}
};

int luaopen_objc_runtime_bridgesupport (lua_State *L) {
  luaL_register(L, "objc.runtime.bridgesupport", funcs);
  return 1;
}
