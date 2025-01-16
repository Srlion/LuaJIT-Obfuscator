# These are modified files to work with the obfuscator

- `src/lib_jit.c` Added `jit.util.funcuv` to return the upvalue info of a proto

```c
LJLIB_CF(jit_util_funcuv)
{
  GCproto *pt = lj_lib_checkLproto(L, 1, 0);
  uint32_t idx = (uint32_t)lj_lib_checkint(L, 2);
  if (idx < pt->sizeuv) {
    int32_t v = proto_uv(pt)[idx];
    setintV(L->top++, v);
    return 1;
  }
  return 0;
}
```

- `src/luaconf.h` Increased stack size to a big number to avoid stack overflow when testing because stack size grows exponentially

```c
#define LUAI_MAXSTACK	65500 * 20	/* Max. # of stack slots for a thread (<64K). */
```

- `Makefile`:

  - Enabled `-DLUAJIT_DISABLE_FFI` and `-DLUAJIT_ENABLE_LUA52COMPAT` flags
  - Renamed executable to `obfuscate`(`.exe`)
  - Enabled `BUILDMODE= static` to build a static executable

- `src/luajit.c`

```c
/*
** LuaJIT frontend. Runs commands, scripts, read-eval-print (REPL) etc.
** Copyright (C) 2005-2025 Mike Pall. See Copyright Notice in luajit.h
**
** Major portions taken verbatim or adapted from the Lua interpreter.
** Copyright (C) 1994-2008 Lua.org, PUC-Rio. See Copyright Notice in lua.h
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define luajit_c

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "luajit.h"

#include "lj_arch.h"

static const char *progname = LUA_PROGNAME;

static void l_message(const char *msg)
{
  if (progname)
  {
    fputs(progname, stderr);
    fputc(':', stderr);
    fputc(' ', stderr);
  }
  fputs(msg, stderr);
  fputc('\n', stderr);
  fflush(stderr);
}

static int report(lua_State *L, int status)
{
  if (status && !lua_isnil(L, -1))
  {
    const char *msg = lua_tostring(L, -1);
    if (msg == NULL)
      msg = "(error object is not a string)";
    l_message(msg);
    lua_pop(L, 1);
  }
  return status;
}

static int traceback(lua_State *L)
{
  if (!lua_isstring(L, 1))
  { /* Non-string error object? Try metamethod. */
    if (lua_isnoneornil(L, 1) ||
        !luaL_callmeta(L, 1, "__tostring") ||
        !lua_isstring(L, -1))
      return 1;       /* Return non-string error object. */
    lua_remove(L, 1); /* Replace object by result of __tostring metamethod. */
  }
  luaL_traceback(L, L, lua_tostring(L, 1), 1);
  return 1;
}

static int docall(lua_State *L, int narg, int clear)
{
  int status;
  int base = lua_gettop(L) - narg; /* function index */
  lua_pushcfunction(L, traceback); /* push traceback function */
  lua_insert(L, base);             /* put it under chunk and args */

  status = lua_pcall(L, narg, (clear ? 0 : LUA_MULTRET), base);

  lua_remove(L, base); /* remove traceback function */

  /* force a complete garbage collection in case of errors */
  if (status != LUA_OK)
    lua_gc(L, LUA_GCCOLLECT, 0);
  return status;
}

static int dofile(lua_State *L, const char *name)
{
  int status = luaL_loadfile(L, name) || docall(L, 0, 1);
  return report(L, status);
}

int main()
{
  lua_State *L;
  L = lua_open();
  if (L == NULL)
  {
    l_message("cannot create state: not enough memory");
    return EXIT_FAILURE;
  }

  /* Stop the garbage collector completely for max speed. */
  /* We don't care as we will obfuscate and exit. (acting like an arena allocator) */
  lua_gc(L, LUA_GCSTOP, 0);
  luaL_openlibs(L);

  /* Try loading obfuscator.lua */
  if (dofile(L, "obfuscator.lua") != 0)
  {
    /* Try loading obfuscator/obfuscator.lua */
    if (dofile(L, "obfuscator/obfuscator.lua") != 0)
    {
      l_message("Error: could not load either obfuscator.lua or obfuscator/obfuscator.lua");
      lua_close(L);
      return EXIT_FAILURE;
    }
  }

  lua_close(L);
  return EXIT_SUCCESS;
}

```
