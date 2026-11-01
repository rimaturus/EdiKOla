for _,f in ipairs(arg) do local ok,e=loadfile(f); print(f, ok and "ok" or e) end
