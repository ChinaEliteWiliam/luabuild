
local USE_ONE = true
local USE_VC = true

local DEBUG = false
local VERBOSE = false
local info = {
   ROOT =   [[..\]];
   SRCDIR = [[..\src\]];
   DSTDIR = [[dstdir\]];

   RM = 'del';
   CP = 'copy /y';
   QUIET = ' >nul 2>nul';
}
info.gcc = {
   CC = 'gcc $CFLAGS $flags -c $input';
   LD = 'gcc $CFLAGS $flags -o $output $input $libs';
   AR = 'ar rcs $output $input';
   RC = 'windres -i $input -o $RCOUT';
   RCOUT = '${output}.o';
   OBJ = '.o';
}
info.gcc_dbg = {
   base = info.gcc;
   CFLAGS = '-std=c99 -ggdb -pipe -O0 -Wall';
}
info.gcc_rel = {
   base = info.gcc;
   CFLAGS = '-std=c99 -s -pipe -O3 -Wall ';
}
info.vs = {
   CC = 'cl /nologo $CFLAGS $flags /c $input';
   LD = 'link /nologo $LDFLAGS $flags /OUT:"$output" $input $libs';
   AR = 'lib /nologo /OUT:$output $input';
   RC = 'rc /nologo /Fo"$RCOUT" $input';
   RCOUT = '${output}.res';
   OBJ = '.obj';
}
info.vs_dbg = {
   base = info.vs;
   CFLAGS = '/W3 /D_CRT_SECURE_NO_DEPRECATE '..
            '/MTd /Zi /Ob0 /Od /RTC1 /D _DEBUG';
   LDFLAGS = '/MACHINE:X86 /DEBUG /INCREMENTAL:NO /PDB:"$output.pdb"';
}
info.vs_rel = {
   base = info.vs;
   CFLAGS = '/nologo /W3 /D_CRT_SECURE_NO_DEPRECATE '..
            '/MT /GS- /GL /Gy /Oy- /O2 /Oi /arch:SSE2 /DNDEBUG';
   LDFLAGS = '/OPT:REF /OPT:ICF /MACHINE:X86 /INCREMENTAL:NO /LTCG:incremental';
}
info.vs_rel_pdb = {
   base = info.vs;
   CFLAGS = '/nologo /W3 /D_CRT_SECURE_NO_DEPRECATE '..
            '/MT /GS- /GL /Gy /Oy- /O2 /Oi /Zi /arch:SSE2 /DNDEBUG';
   LDFLAGS = '/OPT:REF /OPT:ICF /MACHINE:X86 /INCREMENTAL:NO /LTCG:incremental /DEBUG:FASTLINK /PDB:"$output.pdb"';
}
info.vs_rel_min = {
   base = info.vs;
   CFLAGS = '/nologo /W3 /D_CRT_SECURE_NO_DEPRECATE '..
            '/MT /GS- /GL /Gy /O1 /Ob1 /Oi /Oy- /arch:SSE2 /DNDEBUG';
   LDFLAGS = '/OPT:REF /OPT:ICF /MACHINE:X86 /INCREMENTAL:NO /LTCG:incremental';
}

local function find_version()
   local LUA_VERSION_MAJOR
   local LUA_VERSION_MINOR
   local LUA_VERSION_RELEASE
   local LUA_COPYRIGHT
   local LUA_RELEASE

   io.input(info.SRCDIR .. "lua.h")
   for line in io.lines() do
      local v = line:match "#define%s+LUA_VERSION_MAJOR%s+\"(%d+)\""
      if v then LUA_VERSION_MAJOR = v goto next end
      local v = line:match "#define%s+LUA_VERSION_MINOR%s+\"(%d+)\""
      if v then LUA_VERSION_MINOR = v goto next end
      local v = line:match "#define%s+LUA_VERSION_RELEASE%s+\"(%d+)\""
      if v then LUA_VERSION_RELEASE = v goto next end
      local v = line:match "#define%s+LUA_COPYRIGHT.-\"%s*(.-)\""
      if v then LUA_COPYRIGHT = v goto next end
      local v = line:match "#define%s+LUA_RELEASE%s+\"(.-)\""
      if v then LUA_RELEASE = tonumber(v) goto next end
      ::next::
   end
   io.input():close()
   io.input(io.stdin)

   if not LUA_VERSION_MAJOR then
      assert(LUA_RELEASE, "can not find Lua release!!")
      LUA_VERSION_MAJOR,
      LUA_VERSION_MINOR,
      LUA_VERSION_RELEASE = LUA_RELEASE:match "^Lua (%d+)%.(%d+)%.(%d+)"
      assert(LUA_VERSION_MAJOR, "can not find Lua release!!")
   end
   print(("find Lua release: Lua %d.%d.%d\n%s"):format(
      LUA_VERSION_MAJOR, LUA_VERSION_MINOR, LUA_VERSION_RELEASE,
      LUA_COPYRIGHT))
   info.LUA_VERSION_MAJOR   = LUA_VERSION_MAJOR
   info.LUA_VERSION_MINOR   = LUA_VERSION_MINOR
   info.LUA_VERSION_RELEASE = LUA_VERSION_RELEASE
   info.LUA_COPYRIGHT       = LUA_COPYRIGHT
   info.LUAV                = LUA_VERSION_MAJOR..LUA_VERSION_MINOR
   info.LUA_RELEASE         = ("%d.%d.%d"):format(
         LUA_VERSION_MAJOR,
         LUA_VERSION_MINOR,
         LUA_VERSION_RELEASE)
end

local function expand(s, t)
   local count = 0
   local function replace(s, space)
      local s = t and t[s] or info[s]
      if s then
         if type(s) == "table" then
            s = table.concat(s, " ")
         end
         s = s .. (space or "")
         count = count + 1
      end
      return s or ""
   end
   assert(s, "template expected")
   while true do
      local old = count
      s = s:gsub("$%{([%w_]+)%}", replace)
      s = s:gsub("$([%w_]+)(%s*)", replace)
      if old == count then return s end
   end
end

local function patch_rcfile(file)
   local info = {
      LUA_CSV_RELEASE = ("%d,%d,%d,0"):format(
         info.LUA_VERSION_MAJOR,
         info.LUA_VERSION_MINOR,
         info.LUA_VERSION_RELEASE);
   }

   print("[PATCH]\t"..file..".rc")
   io.input("res/"..file..".rc")
   io.output(file..".rc")

   for line in io.lines() do
      io.write(expand(line, info), "\n")
   end

   io.input():close()
   io.output():close()
   io.input(io.stdin)
   io.output(io.stdout)
end

local function patch_luaconf()
   local LUA_VDIR = info.LUA_VERSION_MAJOR.."."..info.LUA_VERSION_MINOR
   local t = {
      path = [[
#define LUA_PATH_DEFAULT  ".\\?.lua;" ".\\?\\init.lua;" \
		LUA_CDIR "?.lua;" LUA_CDIR "?\\init.lua;" \
		LUA_CDIR "lua\\?.lua;" LUA_CDIR "lua\\?\\init.lua;" \
		LUA_CDIR "clibs\\?.lua;" LUA_CDIR "clibs\\?\\init.lua;" \
		LUA_CDIR "..\\share\\lua\\]]..LUA_VDIR..[[\\?.lua;" \
		LUA_CDIR "..\\share\\lua\\]]..LUA_VDIR..[[\\?\\init.lua"]];
      cpath = [[
#define LUA_CPATH_DEFAULT  ".\\?.dll;" ".\\loadall.dll;" \
		LUA_CDIR "?.dll;" LUA_CDIR "loadall.dll;" \
		LUA_CDIR "clibs\\?.dll;" LUA_CDIR "clibs\\loadall.dll;" \
		LUA_CDIR "..\\lib\\lua\\]]..LUA_VDIR..[[\\?.dll;" \
		LUA_CDIR "..\\lib\\lua\\]]..LUA_VDIR..[[\\loadall.dll"]];
   }

   print("[PATCH]\tluaconf.h")
   io.input(info.SRCDIR.."luaconf.h")
   io.output "luaconf.h"
   local patched = 0
   local begin
   for line in io.lines() do
      if patched < 2 then
         if begin and not line:match "\\$" then
            line = t[begin]
            patched = patched + 1
            begin = nil
         elseif line:match "#define%s+LUA_PATH_DEFAULT" then
            begin = "path"
         elseif line:match "#define%s+LUA_CPATH_DEFAULT" then
            begin = "cpath"
         end
      end

      if not begin then io.write(line, "\n") end
   end
   io.input():close()
   io.output():close()
   io.input(io.stdin)
   io.output(io.stdout)
end

local function glob(pattern)
   local fh = assert(io.popen("DIR /B /W "..pattern))
   local files = {}
   for line in fh:lines() do
      files[#files+1] = line
   end
   fh:close()
   return files
end

local function map(files, f)
   local t = {}
   for i, v in ipairs(files) do
      local new = f(i, v)
      if new then t[#t+1] = new end
   end
   return t
end

local function tsub(files, pattern, replace)
   local t = {}
   for i, v in ipairs(files) do
      t[i] = v:gsub(pattern, replace)
   end
   return t
end

local function execute(fmt, t)
   local cmdline = expand(fmt, t)
   if VERBOSE then
      print(">>", cmdline)
   end
   return assert(os.execute(cmdline))
end

local function find_toolchain(toolchain)
   if not toolchain then
      --local env = os.getenv "VS120COMNTOOLS" or -- VS2013
                  --os.getenv "VS110COMNTOOLS" or -- VS2012
                  --os.getenv "VS100COMNTOOLS" or -- VS2010
                  --os.getenv "VS90COMNTOOLS"     -- VS2008
      --if env then
         --execute("call "..env.."vsvars32.bat")
      --end
      if os.execute(expand[[cl $QUIET]]) then
         print("find VS toolchain")
         toolchain = "vs"
      elseif os.execute(expand[[gcc --version $QUIET]]) then
         print("find GCC toolchain")
         toolchain = "gcc"
      end
      if not toolchain then
         print("can not find toolchain!!!")
      end
      toolchain = toolchain .. (DEBUG and "_dbg" or "_rel")
   end
   print("use toolchain: "..toolchain)
   info.TOOLCHAIN = toolchain
   local t = info[toolchain]
   repeat
      for k,v in pairs(t) do
         info[k] = v
      end
      t = t.base
   until not t
end

local function compile(file, flags)
   if type(file) == "string" then
      print("[CC]\t"..file)
   end
   return execute("$CC", {
      input = file,
      flags = flags,
   })
end

local function compile_rc(file)
   print("[RC]\t"..file)
   local t = {
      input = file,
      output = file,
   }
   if execute(info.RC, t) then
      return expand(info.RCOUT, t)
   end
end

local function link(target, files, flags, libs)
   print("[LINK]\t"..target)
   return execute(info.LD, {
      flags = flags,
      input = files,
      output = target,
      libs = libs,
   })
end

local function library(lib, files)
   print("[AR]\t"..lib)
   return execute(info.AR, {
      output = lib,
      input = files,
   })
end

local function buildone_luas()
   patch_rcfile "luas"
   local LUAV = info.LUAV
   local rc = compile_rc "luas.rc"
   local flags = { "-DLUA_BUILD_AS_DLL -DMAKE_LUA -I$SRCDIR" }
   local ldflags = {}
   if tonumber(LUAV) >= 53 then
      flags[#flags+1] = "-DHAVE_LPREFIX"
   end
   if info.TOOLCHAIN:match "^gcc" then
      ldflags[#ldflags+1] = "-Wl,--out-implib,liblua"..LUAV..".exe.a"
   end
   compile("one.c", flags)
   link("lua"..LUAV..".exe", "one$OBJ "..rc, ldflags)
   if info.TOOLCHAIN:match "^vs" then
      execute[[move /Y lua${LUAV}.lib lua${LUAV}exe.lib $QUIET]]
      execute[[move /Y lua${LUAV}.exp lua${LUAV}exe.exp $QUIET]]
   end
end

local function buildone_luadll()
   patch_rcfile "luadll"
   local LUAV = info.LUAV
   local rc = compile_rc "luadll.rc"
   local flags = { "-DLUA_BUILD_AS_DLL -DMAKE_LIB -I$SRCDIR" }
   local ldflags = {}
   if tonumber(LUAV) >= 53 then
      flags[#flags+1] = "-DHAVE_LPREFIX"
   end
   if info.TOOLCHAIN:match "^gcc" then
      ldflags[#ldflags+1] = "-mdll"
      ldflags[#ldflags+1] = "-Wl,--out-implib,liblua"..LUAV..".dll.a"
      ldflags[#ldflags+1] = "-Wl,--output-def,lua"..LUAV..".def"
   else
      ldflags[#ldflags+1] = "/DLL"
   end
   compile("one.c ", flags)
   link("lua"..LUAV..".dll", "one$OBJ "..rc, ldflags)
end

local function build_lua()
   patch_rcfile "lua"
   local LUAV = info.LUAV
   local rc = compile_rc "lua.rc"
   local flags = "-DLUA_BUILD_AS_DLL -I$SRCDIR"
   local libs
   if info.TOOLCHAIN:match "^gcc" then
      libs = "-L. -llua"..LUAV..".dll"
   else
      libs = "lua"..LUAV..".lib"
   end
   compile("lua.c ", flags)
   link("lua.exe", "lua$OBJ "..rc, nil, libs)
end

local function buildone_luac()
   patch_rcfile "luac"
   local LUAV = info.LUAV
   local rc = compile_rc "luac.rc"
   local flags = "-DMAKE_LUAC -I$SRCDIR"
   if tonumber(LUAV) >= 53 then
      flags = flags .. " -DHAVE_LPREFIX"
   end
   compile("one.c ", flags)
   link("luac.exe", "one$OBJ "..rc)
end

local function build_lualib()
   print("[CC]\tlualib")
   local files = map(glob(info.SRCDIR.."*.c"), function(i, v)
      if v ~= "lua.c" and v ~= "luac.c" then
         return info.SRCDIR .. v
      end
   end)
   local LUAV = info.LUAV
   compile(files, "-DLUA_BUILD_AS_DLL -I$SRCDIR")
   if info.TOOLCHAIN:match "^gcc" then
      library("liblua"..LUAV..".a",
         tsub(files, info.SRCDIR.."(.*).c$", "%1.o"))
   else
      library("lua"..LUAV.."s.lib",
         tsub(files, info.SRCDIR.."(.*).c$", "%1.obj"))
   end
   execute("$RM /s /q *.o *.obj $QUIET")
end

local function make_dirs()
   print("[MKDIR]\t"..info.DSTDIR)
   execute [[del /s /q $DSTDIR $QUIET]]
   execute [[mkdir ${DSTDIR}         $QUIET]]
   execute [[mkdir ${DSTDIR}clibs    $QUIET]]
   execute [[mkdir ${DSTDIR}doc      $QUIET]]
   execute [[mkdir ${DSTDIR}lua      $QUIET]]
   execute [[mkdir ${DSTDIR}include  $QUIET]]
   execute [[mkdir ${DSTDIR}lib      $QUIET]]
end

local function install_doc()
   print("[INSTALL]\tdocuments")
   for i, v in ipairs(glob(info.ROOT.."doc")) do
      execute([[$CP ${ROOT}doc\$output ${DSTDIR}doc $QUIET]], { output = v })
   end
end

local function install_headers()
   print "[INSTALL]\theaders"
   execute[[$CP ${SRCDIR}luaconf.h ${DSTDIR}include $QUIET]]
   execute[[$CP ${SRCDIR}lua.h     ${DSTDIR}include $QUIET]]
   execute[[$CP ${SRCDIR}lua.hpp   ${DSTDIR}include $QUIET]]
   execute[[$CP ${SRCDIR}lauxlib.h ${DSTDIR}include $QUIET]]
   execute[[$CP ${SRCDIR}lualib.h  ${DSTDIR}include $QUIET]]
end

local function install_executables()
   print "[INSTALL]\texecutables"
   execute[[$CP lua.exe $DSTDIR $QUIET]]
   execute[[$CP luac.exe $DSTDIR $QUIET]]
   execute[[$CP lua$LUAV.exe $DSTDIR $QUIET]]
   execute[[$CP lua$LUAV.dll $DSTDIR $QUIET]]
   execute[[$RM vc*.pdb]]
   execute[[$CP *.pdb $DSTDIR $QUIET]]
end

local function install_libraries()
   print "[INSTALL]\tlibraries"
   execute[[$CP *.a   ${DSTDIR}lib $QUIET]]
   execute[[$CP *.lib ${DSTDIR}lib $QUIET]]
   execute[[$CP *.def ${DSTDIR}lib $QUIET]]
   execute[[$CP *.exp ${DSTDIR}lib $QUIET]]
end

local function dist()
   assert = function(...) return ... end
   info.DSTDIR = expand[[Lua$LUAV$TOOLCHAIN\]]
   print("[INSTALL]\t"..info.DSTDIR)
   make_dirs()
   install_doc()
   install_headers()
   install_executables()
   install_libraries()
end

local function cleanup()
   print("[CLEANUP]")
   execute[[$RM *.def *.a *.exe *.dll *.rc *.o $QUIET]]
   execute[[$RM *.obj *.lib *.exp *.res *.pdb *.ilk $QUIET]]
   execute[[$RM *.idb *.ipdb *.iobj $QUIET]]
   execute[[$RM luaconf.h $QUIET]]
end

-- begin build
while arg[1] and arg[1]:sub(1,1) == '-' do
   if arg[1] == '-v' then
      VERBOSE = true
   elseif arg[1] == '-d' then
      DEBUG = true
   elseif arg[1] == '-h' or arg[1] == '-?' then
      print(arg[0].." [-v] [-d] [toolchain]")
      print("support toolchain:")
      local tls = {}
      for k,v in pairs(info) do
         if type(v) == 'table' and v.base then
            tls[#tls+1] = k
         end
      end
      table.sort(tls)
      print("    "..table.concat(tls, "\n    "))
      return
   end
   table.remove(arg, 1)
end

find_version()
patch_luaconf()

find_toolchain(arg[1])
buildone_luas()
buildone_luadll()
build_lua()
buildone_luac()
build_lualib()
dist()
cleanup()
print "[DONE]"

-- cc: cc='D:\lua53\lua.exe'
