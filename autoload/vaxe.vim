
" Utility variable that stores the directory that this script resides in
let s:plugin_path = escape(expand('<sfile>:p:h'), '\')

let s:slash = '/'
if has('win32') || has('win64')
    let s:slash = '\'
endif


" Utility function that lets users select from a list.  If list is length 1,
" then that item is returned.  Uses tlib#inpu#List if available.
function! s:InputList(label, items)
  if len(a:items) == 1
    return a:items[0]
  endif
  if exists("g:loaded_tlib")
      return tlib#input#List("s", a:label, a:items)
  else
      let items_list = map(range(len(a:items)),'(v:val+1)." ".a:items[v:val]')
      let items_list = [a:label] + items_list
      let sel = inputlist(items_list)
      " 0 is the label.  If that is returned, just use the first item in the
      " list instead
      if sel == 0
          sel = 1
      endif
      return a:items[sel-1]
  endif
endfunction

" Utility logging function
function! s:Log(str)
    if g:vaxe_logging
        echomsg a:str
    endif
endfunction

" Utility function that returns a list of unique values in the list argument.
function! s:UniqueList(items)
    let d = {}
    for v in a:items
        let d[v] = 1
    endfor
    return keys(d)
endfunction

" Utility function to open the hxml file that vaxe is using.
function! vaxe#OpenHxml()
    let vaxe_hxml = vaxe#CurrentBuild()
    if filereadable(vaxe_hxml)
        exe ':edit '.vaxe_hxml
    else
        echoerr 'build not readable: '.vaxe_hxml
    endif
endfunction

" Utility function that tries to 'do the right thing' in order to import a
" given class. Call it on a given line in order to import a class definition
" at that line.  E.g.
" var l = new haxe.FastList<Int>()
" becomes
" import haxe.FastList;
" ...
" var l = new FastList();
" You can also call this without a package prefix, and vaxe will try to look
" up packages that contain the (e.g. FastList) class name.
function! vaxe#ImportClass()
   let match_parts = matchlist(getline('.'), '\(\(\l\+\.\)\+\)*\(\u\w*\)')
   if len(match_parts)
       let package = match_parts[1]
       " get rid of the period at t*he end of the package declaration.
       let package = substitute(package, "\.$",'','g')
       let class = match_parts[3]
       let file_packages = {}
       let file_classes = {}

       if package == ''
           for val in taglist(".")
               if val['kind'] == 'p'
                   let file_packages[val['filename']] = val['name']
               elseif val['kind'] == 'c' || val['kind'] == 't' || val['kind'] == 'i'
                   if val['name'] == class
                       let file_classes[val['filename']] = val['name']
                   endif
               endif
           endfor

           let packages = []

           for file in keys(file_classes)
               if has_key(file_packages, file)
                   let packages = packages + [file_packages[file]]
               endif
           endfor

           if len(packages) == 0
               echomsg "No packages found in ctags"
               return
           endif

           let package = packages[0]
           if len(packages) > 1
               let package = s:InputList("Select package", packages)
           endif
       endif

       if package == ''
           echomsg "No package found for class"
           return
       endif
       let oldpos = getpos('.')


       if search("^\\s*import\\s*".package."\.".class) > 0
           let fixed = substitute(getline('.'), package.'\.', '','g')
           echomsg "Class has already been imported"
           return
       endif

       let importline = search("^\\s*import")
       if importline == 0
           let importline = search("^\\s*package")
       endif
       call cursor(oldpos[1], oldpos[2])
       let fixed = substitute(getline('.'), package.'\.', '','g')
       call setline(line('.'), fixed)
       call append(importline,['import '.package.'.'.class.';'])
       call cursor(oldpos[1]+1, oldpos[2])
   endif
endfunction

" A function suitable for omnifunc
function! vaxe#HaxeComplete(findstart,base)
   if a:findstart
       return col('.')
   else
       return s:DisplayCompletion()
   endif
endfunction

" A function that will search for valid hxml in the current working directory
"  and allow the user to select the right candidate.  The selection will
"  enable 'project mode' for vaxe.
function! vaxe#ProjectHxml(...)
    if exists('g:vaxe_hxml')
        unlet g:vaxe_hxml
    endif

    if a:0 > 0 && a:1 != ''
        let g:vaxe_hxml = a:1
    else
        let hxmls = split(glob("**/*.hxml"),'\n')

        if len(hxmls) == 0
            echoerr "No hxml files found in current working directory"
            return
        else
            let base_hxml = s:InputList("Select Hxml", hxmls)
        endif

        if base_hxml !~ "^//"
            let base_hxml = getcwd() . s:slash . base_hxml
        endif

        let g:vaxe_hxml = base_hxml
    endif
    if !filereadable(g:vaxe_hxml)
        echoerr "Project build file not valid, please create one."
        return
    endif

    call s:SetCompiler()
    return g:vaxe_hxml
endfunction

" A function that runs on a hx filetype load.  It will set the default hxml
" path if the project hxml is not set.
function! vaxe#AutomaticHxml()
    if exists('g:vaxe_hxml')
        return
    endif
    call vaxe#DefaultHxml()
endfunction

" A function that sets the default hxml located in the parent directories of
" the current buffer.
function! vaxe#DefaultHxml(...)
    " unlet any existing hxml variables
    if exists('b:vaxe_hxml')
        unlet b:vaxe_hxml
    endif
    "if exists('g:vaxe_hxml')
    "    unlet g:vaxe_hxml
    "endif
    if a:0 > 0 && a:1 != ''
        let b:vaxe_hxml = a:1
    else
        let base_hxml = findfile(g:vaxe_prefer_hxml, ".;")
        if base_hxml !~ "^/"
            let base_hxml = getcwd() . s:slash . base_hxml
        endif
        if !filereadable(base_hxml)
            redraw
            echomsg "Default build file not valid, please create one."
            return
        endif
        let b:vaxe_hxml = base_hxml
    endif
    call s:SetCompiler()
endfunction


" Returns the hxml file that should be used for compilation or completion
function! vaxe#CurrentBuild()
    let vaxe_hxml = ''
    if exists('g:vaxe_hxml')
        let vaxe_hxml = g:vaxe_hxml
    elseif exists('b:vaxe_hxml')
        let vaxe_hxml = b:vaxe_hxml
    endif
    return vaxe_hxml
endfunction

" Sets the makeprg

function! s:SetCompiler()
    let vaxe_hxml = vaxe#CurrentBuild()
    call s:Log("vaxe_hxml: ".vaxe_hxml)
    if (exists("g:vaxe_hxml"))
        let build_command = "haxe \"".vaxe_hxml."\" 2>&1"
    else
        " do not cd to different directory after command, it won't show quick
        " fix
        let build_command = "cd \"".fnamemodify(vaxe_hxml,":p:h")."\" &&"
                    \."haxe \"".vaxe_hxml."\" 2>&1"
    endif
    let &l:makeprg = build_command
    " only use simple info message for catching traces (%I%m), haxe doesn't
    " output the full file path in the trace output


    let lines = readfile(vaxe_hxml)
    let abspath = filter(lines,'v:val =~ "\\s*-D\\s*absolute_path"')

    let &l:errorformat="%I%f:%l: characters %c-%*[0-9] : Warning : %m
                    \,%E%f:%l: characters %c-%*[0-9] : %m
                    \,%E%f:%l: lines %*[0-9]-%*[0-9] : %m"
    " if -D absolute_path is specified, then traces contain path information,
    " and errorfmt can use the file/folder location
    "echomsg join(abspath,',')
    if (len(abspath)> 0)
        let &l:errorformat .= ",%I%f:%l: %m"
    endif
    " general catch all regex that will grab misc stdout
    let &l:errorformat .= ",%I%m"
endfunction

" returns a list of compiler class paths
function! vaxe#CompilerClassPaths()
   let complete_args = s:CurrentBlockHxml()
   let complete_args.= "\n"."-v"."\n"."--no-output"
   let complete_args = join(split(complete_args,"\n"),' ')
   let vaxe_hxml = vaxe#CurrentBuild()
   let hxml_cd = fnamemodify(vaxe_hxml,":p:h")
   let hxml_sys = "cd\ ".hxml_cd."; haxe ".complete_args."\ 2>&1"
   let voutput = system(hxml_sys)
   let raw_path = split(voutput,"\n")[0]
   let raw_path = substitute(raw_path, "Classpath :", "","")
   let paths = split(raw_path,';')
   let paths = filter(paths,'v:val != "/" && v:val != ""')
   if len(paths) == 1
       echoerr "The compiler exited with an error: ". paths[0]
       return []
   endif
   let unique_paths = s:UniqueList(paths)
   return unique_paths
endfunction

" Calls ctags on the list of compiler class paths
function! vaxe#Ctags()
    let paths = vaxe#CompilerClassPaths()

    if (len(paths) > 0)
        let fixed_paths = []
        for p in paths
            if p =~ "/std/$"
                "this is the target std dir. We need to alter use it to add some
                "global std utility paths, and avoid the target paths.
                let fixed_paths = fixed_paths + [p.'haxe/', p.'sys/', p.'tools/', p.'*.hx']
            elseif p =~ "/_std/$"
                "this is the selected target paths, we can exclude the _std path
                "that includes target specific implementations of std classes.
                let p = substitute(p, "_std/$", "","g")
                let fixed_paths = fixed_paths + [p]
            elseif p =~ "^\./$"
                "this is an alt representation of the working dir, we don't
                "need it
                continue
            else
                "this is a normal path (haxelib, or via -cp)
                let fixed_paths = fixed_paths + [p]
            endif
        endfor

        let pathstr = join( fixed_paths,' ')
        let vaxe_hxml = vaxe#CurrentBuild()
        " get the hxml name so we can cd to its directory
        " TODO: this probably needs to be user specified
        let hxml_cd = fnamemodify(vaxe_hxml,":p:h")
        " call ctags recursively on the directories
        let hxml_sys = " cd " . hxml_cd . ";"
                    \." ctags --languages=haxe --exclude=_std -R " . pathstr. ";"
        call s:Log(hxml_sys)
        call system(hxml_sys)
    endif
endfunction

" Generate inline compiler declarations for the given target from the relevant
" build hxml.  Remove any flags that generate unnecessary output or activity.
function! s:CurrentBlockHxml()
    let vaxe_hxml = vaxe#CurrentBuild()
    let hxfile = join(readfile(vaxe_hxml),"\n")
    let parts = split(hxfile, '--next')

    if len(parts) == 0
        let parts = [hxfile]
    endif

    let complete = filter(copy(parts), 'v:val =~ "#\\s*display completions"')
    if len(complete) == 0
        let complete = parts
    endif

    let complete_string = complete[0]
    let parts = split(complete_string,"\n")
    let parts = map(parts, 'substitute(v:val,"#.*","","")')
    let parts = map(parts, 'substitute(v:val,"\\s*-\\(cmd\\|xml\\|v\\)\\s*.*","","")')
    let complete_string = join(parts,"\n")
    return complete_string
endfunction

" Returns hxml that is suitable for making a --display completion call
function! s:CompletionHxml(file_name, byte_count)
    " the stripped down haxe compiler command (no -cmd, etc.)
    let stripped = s:CurrentBlockHxml()
    return stripped."\n"."--display \"".a:file_name.'@'.a:byte_count."\""
endfunction

" The main completion function that invokes the compiler, etc.
function! s:DisplayCompletion()
    if  synIDattr(synIDtrans(synID(line("."),col("."),1)),"name") == 'Comment'
        return []
    endif

    let vaxe_hxml = vaxe#CurrentBuild()
    if !filereadable(vaxe_hxml)
        echoerr 'No completion Possible. Build file not readable: '.vaxe_hxml
        return []
    endif
    let complete_args = s:CompletionHxml(expand("%:p")
                \, (line2byte('.')+col('.')-2))
    let hxml_cd = "cd\ \"".fnamemodify(vaxe_hxml,":p:h"). "\"&&"
    if exists("g:vaxe_hxml")
        let hxml_cd = ''
    endif
    let hxml_sys = hxml_cd." haxe ".complete_args."\ 2>&1"
    let hxml_sys =  join(split(hxml_sys,"\n")," ")
    call s:Log(hxml_sys)
    " ignore the write requests generated by completions
    if (g:vaxe_prevent_completion_bufwrite_events)
        let events = "BufWritePost,BufWritePre,BufWriteCmd"
        let old_ignore = &l:eventignore
        if (&l:eventignore)
            let &l:eventignore = &l:eventignore . ',' . events
        else
            let &l:eventignore = events
        endif
        exe ":silent update"
        let &l:eventignore = old_ignore
    else
        exe ":silent update"
    endif
    let complete_output = system(hxml_sys)
    " quick and dirty check for error
    if complete_output =~"\\u\\l*\.hx:\\d\\+"
        echoerr complete_output
        return []
    endif
    let output = []
    call s:Log(complete_output)

    " execute the python completion script in autoload/vaxe.py
    exe 'pyfile '.s:plugin_path.'/vaxe.py'
    py complete('complete_output','output')

    for o in output
        let tag = ''
        if has_key(o,'info')
            let o['info'] = join(o['info'],"\n")
        endif
        if has_key(o,'menu')
            let o['info'] = o['info'] . "\n>> " . o['menu']
        endif
    endfor
    " There was no compiler completion.  Complete a Type
    if len(output) == 0
        let classes = []
        let line2col =getline('.')[0:col('.')]
        let partial_word = ''
        let obj = copy(l:)

        " shortcut function that matches a regex and sets a partial word
        " variable
        function! obj.EML(regex)
            let matches = matchlist(self.line2col, a:regex)
            "echomsg join(matches,' ')
            if len(matches) > 0
               let self.partial_word = matches[1]
            end
            return len(matches)
        endfunction
        if obj.EML("new\\s*\\(\w*\\)$")
            let classes = filter(taglist('^'.partial_word),
                        \'v:val["kind"] == "c"')
            "echomsg "constructor"
        elseif obj.EML(":\\s*\\(\w*\\)$")
            let classes = filter(taglist('^'.partial_word),
                        \'v:val["kind"] == "c" '
                        \.'|| v:val["kind"] == "t" '
                        \.'|| v:val["kind"] == "i"')
        elseif obj.EML("import\\s*\\(\w*\\)$")
            let classes = filter(taglist('^'.partial_word),
                        \'v:val["kind"] == "p"')
        else
            "echomsg partial_word
            "echomsg "***".line2col."***"
        endif
        let output = map(classes,
                    \'{"word":substitute(v:val["name"],"^".partial_word,"","g")'
                    \.', "abbr":v:val["name"]'
                    \.', "menu":v:val["filename"]}')
    endif
    return output
endfunction

