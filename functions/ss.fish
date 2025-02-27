function ss --description "Frontend to configure //. See ss --help"
  status is-interactive; or return

  if test (count $argv) -ne 0; and not string match -q -- '-*' $argv[1]
    set subcmd __slashslash_$argv[1]_cmd
    if functions -q $subcmd
      $subcmd $argv[2..]
      return $status
    else
      echo "ss: Unknown subcommand: $argv[1]" >&2
      return 1
    end
  end

  argparse h/help -- $argv; or return

  if set -q _flag_h; or test (count $argv) -eq 0
    echo "Subcommands:"
    echo "  enable -- enable // expansion on a command"
    echo "  disable -- disable // expansion on a command"
    echo "  plugin -- enable/disable/list plugins"
    echo "  expand -- expand //"
    echo "  complete -- print completions of a given token after expanding //"
    echo "  reload -- reload the current cells. Useful after editing .ss. Pass -a to load async"
    return 0
  end
end

function __slashslash_disable_cmd
  argparse h/help -- $argv; or return

  if set -q _flag_h
    echo "Usage:"
    echo "ss disable CMD [CMD [CMD ..]]"
    echo
    echo "Disable expanding // for CMD(s)"
    return 0
  end

  for arg in $argv
    if not functions -q __slashslash_restore_$arg; or not type -q __slashslash_real_$arg
      echo "W: $arg wasn't ever slashslash enabled" >&2
      continue
    end
    # Remove our alias
    functions -e "$arg"
    # Restore original definition
    __slashslash_restore_$arg
    # Disable completion
    complete -e -c $arg -a '(__slashslash_complete_cmd (commandline --current-token))'
    complete -e -c $arg --no-files
    complete -e -c $arg --wraps "__slashslash_invoke __slashslash_real_$arg"
  end
end

function __slashslash_enable_cmd
  argparse h/help -- $argv; or return

  if set -q _flag_h
    echo "Usage:"
    echo "ss enable CMD [CMD [CMD ..]]"
    echo
    echo "Enable expanding // for CMD(s)"
    return 0
  end

  for arg in $argv
    if functions -q "__slashslash_real_$arg"
      echo "W: $arg already slashslash enabled, ignoring" >&2
      continue
    end
    if functions -q "$arg"
      functions -c "$arg" "__slashslash_real_$arg"
      function __slashslash_restore_$arg --description "Disable // expansion for $arg"
        functions -c "__slashslash_real_$arg" "$arg"
      end
    else
      alias "__slashslash_real_$arg" "command $arg"
      function __slashslash_restore_$arg --description "Disable // expansion for $arg"
        functions -e "__slashslash_real_$arg"
      end
    end
    alias "$arg" "__slashslash_invoke __slashslash_real_$arg"
    complete -c $arg -a '(__slashslash_complete_cmd (commandline --current-token))'
    complete -c $arg --no-files  # Our completion handler will handle this
  end
end

function __slashslash_plugin_cmd --description "Enable/disable slashslash plugins"
  argparse h/help u/unregister l/list v/verbose c/complete= s/subpath= n/no-reload -- $argv; or return

  if set -ql _flag_l
    if not set -qg __slashslash_plugins
      echo "No registered plugins"
      return 1
    end
    for plugin in $__slashslash_plugins
      set -l function_key __slashslash_plugin_$plugin
      if not set -q "$function_key"
        echo "W: Configuration error. $plugin registered but no known definition" >&2
        continue
      end
      set -l function_name $$function_key
      if not functions -q "$function_name"
        echo "W: Configuration error. $plugin registered but missing definition" >&2
        continue
      end
      echo "$plugin : $function_name"
      if set -ql _flag_v
        functions $function_name
      end
    end
    return 0
  end

  if set -ql _flag_h; or test (count $argv) -eq 0
    echo "Usage:"
    echo "ss plugin [-h|--help]"
    echo "ss plugin [-n|--no-reload] [-c|--complete COMPLETE_CALLBACK] [-s|--subpath SUBPATH_CALLBACK] NAME CALLBACK"
    echo "ss plugin [-n|--no-reload] -u|--unregister NAME"
    echo "ss plugin -l|--list -v|--verbose"
    echo
    echo "The default command registers/unregisters a plugin named NAME with callback CALLBACK."
    echo "The optional -c|--complete flag specifies a callback to be called with a token that"
    echo "should be autocompleted. If -s|--subpath is specified then it will be called to"
    echo
    echo "When -l|--list is passed then the currently registered plugins are printed. When"
    echo "-v|--verbose is also passed then the plugin definitions will be printed as well."
    echo
    echo "Each plugin should be a function which accepts a path as an argument and prints"
    echo "the list of cells recognized at that path."
    return 0
  end

  if not set -ql _flag_u
    if test (count $argv) -ne 2
      echo "Usage: slashslash plugin [-c|--complete COMPLETE_CALLBACK] NAME CALLBACK" >&2
      return 1
    end

    set name "$argv[1]"
    set callback "$argv[2]"

    if not functions -q "$callback"
      echo -n "E: $callback is not a function. "(type $callback) >&2
      return 1
    end

    if not set -qg __slashslash_plugins
      set -g __slashslash_plugins
    end
    if not contains -- "$name" $__slashslash_plugins
      set -ga __slashslash_plugins "$name"
    end

    set -l function_key __slashslash_plugin_$name
    if set -gq $function_key
      echo "I: Overwriting $name, was "$$function_key
    end
    set -g $function_key $callback

    if set -q _flag_c
      if not functions -q "$_flag_c"
        echo -n "W: Ignoring $_flag_c: not a function. "(type $_flag_c) >&2
      else
        set -g __slashslash_completer_$name "$_flag_c"
        set -ga __slashslash_completers "$name"
      end
    end

    if set -q _flag_s
      if not functions -q "$_flag_s"
        echo -n "W: Ignoring $_flag_s: not a function. "(type $_flag_s) >&2
      else
        set -g __slashslash_subpather_$name "$_flag_s"
      end
    end

    set -q __slashslash_verbose; and echo "Registered $name > $callback"
  else
    if test (count $argv) -ne 1
      echo "Usage: slashslash plugin -d|--disable NAME" >&2
      return 1
    end
    set name "$argv[1]"

    if not set -qg __slashslash_plugins
      echo "W: No plugins registered, ignoring" >&2
      return 1
    end

    if not set -f idx (contains -i -- "$name" $__slashslash_plugins)
      echo "W: $name never registered, ignoring" >&2
      return 1
    end

    set -e __slashslash_plugins[$idx]

    set -l function_key __slashslash_plugin_$name
    if not set -gq $function_key
      echo "W: $name callback missing, ignoring" >&2
      return 1
    end
    set -e $function_key
    set -q __slashslash_completer_$name; and set -e __slashslash_completer_$name
    if set -f cidx (contains -i -- "$name" $__slashslash_completers)
      set -e __slashslash_completers[$cidx]
    end
    set -q __slashslash_subpather_$name; and set -e __slashslash_subpather_$name

    set -q __slashslash_verbose; and echo "Unregistered $name"
  end
  if not set -q _flag_n
    __slashslash_reload_cmd -a
  end
  return 0
end

function __slashslash_expand_cmd --description "Expand // based on current cells"
  argparse -i f/force e -- $argv

  if set -q _flag_e
    set -f res 1
  else
    set -f res 0
  end

  if not set -q _flag_f; and status is-command-substitution
    string join \n -- $argv
    return $res
  end

  if set -q __slashslash_expanding
    string join \n -- $argv
    return $res
  end
  set -g __slashslash_expanding

  __slashslash_load_cells

  if not set -qg __slashslash_current_cells; or not set -qg __slashslash_current_cell_paths
    __slashslash_verbose "No loaded cells"
    string join \n -- $argv
    set -e __slashslash_expanding
    return $res
  end

  test (realpath .) != "$PWD"; and set needs_abs

  for arg in $argv
    if string match --quiet -- '-*' $arg
      echo -- "$arg"
      continue
    end
    __slashslash_verbose "// Expanding '$arg'"

    # Is there // somewhere in this arg?
    if not string match -rq '^(?<cell>[^/\s]*//)(?<subpath>[^\s]*)$' -- $arg
      echo -- "$arg"
      continue
    end

    if not set idx (contains -i -- "$cell" $__slashslash_current_cells)
      echo -- "$arg"
      continue
    end

    set -l plugin_name $__slashslash_current_cell_plugin_names[$idx]
    set -l root $__slashslash_current_cell_paths[$idx]

    if set -q __slashslash_subpather_$plugin_name
      set subpather __slashslash_subpather_$plugin_name
      set new_subpath ($$subpather "$subpath")
      __slashslash_verbose "  expanded subpath $subpath > $new_subpath"
      set subpath "$new_subpath"
    end

    set -l abs "$root/$subpath"
    __slashslash_verbose "  matched idx=$idx plugin=$plugin_name root=$root abs=$abs"

    if set -q needs_abs
      # When we're inside a symlinked directory relative paths get weird, lets
      # fallback to absolute.
      echo -n -- (realpath "$abs")
    else
      echo -n -- (realpath -s --relative-to=. "$abs")
    end

    # Use abs instead of $subpath so that when $subpath is empty
    # the match succeeds and we correctly get a trailing slash.
    string match -rq '/$' -- "$abs"; and echo -n "/"
    echo

    set -f res 0
  end
  set -e __slashslash_expanding
  return $res
end

function __slashslash_complete_cmd -a cur --description "Print completions for a token after expanding //"
  string match --quiet -- '-*' $cur && return
  set -l expanded (__slashslash_expand_cmd -f "$cur")
  if test "$expanded" != "$cur"
    set -f unexpanded_dirname (string split --right --max 1 / -- "$cur")[1]
    if string match -q '*/*' -- "$expanded"
      set -l expanded_dirname (string split --right --max 1 / -- "$expanded")[1]
      set -f start_idx (math (string length "$expanded_dirname") + 1)
    else
      set -f unexpanded_dirname "$unexpanded_dirname/"
      set -f start_idx 1
    end
    for p in (__fish_complete_path $expanded)
      set -l completed (string sub -s $start_idx -- "$p")
      echo -- $unexpanded_dirname$completed
    end
    for completer_name in $__slashslash_completers
      set -l completer __slashslash_completer_$completer_name
      set -q $completer; and $$completer "$cur"
    end
  else
    __fish_complete_path $cur
    for cell_name in $__slashslash_current_cells
      if test (string sub --length (string length -- "$cur") -- $cell_name) = "$cur"
        echo -- $cell_name
      end
    end
  end
  return 0
end

function __slashslash_cells_cmd --description "Query the currently available cells. Pass -r/--reload to reload"
  argparse r/reload h/help a/add d/delete n/no-reload -- $argv; or return

  if set -ql _flag_h
    echo "Usage:"
    echo "ss cells [-h|--help]"
    echo "ss cells"
    echo "ss cells [-r|reload]"
    echo "ss cells [-n|--noreload] -a|-add NAME PATH [PRIORITY]"
    echo "ss cells [-n|--noreload] -d|--delete NAME"
    echo
    echo "Passing -a|-add adds a global cell that will exist no matter where your PWD is."
    echo "Optionally specify PRIORITY a non-negative integer to dictate which plugin should"
    echo "be used when multiple plugins declare the same cell. Defaults to 50 when unspecified."
    echo
    echo "The default priority across plugins is 100. git defaults to 150 and buck defaults to 200."
    echo
    echo "For example specifying priority 1000 indicates the given cell should override (essentially)"
    echo "any other definition of that cell by any other plugin."
    echo
    echo "On the other hand specifying 0 indicates the specified cell should *only* be used as a fallback."
    echo
    echo "Any cell added this way is added globally, meaning only this fish instance will see the new cell."
    echo
    echo "Passing -d|--delete will remove the global cell definition."
    echo
    echo "Passing -n|--no-reload will disable reloading cells. This is helpful for startup perf"
    echo
    echo "Passing -r|--reload force reloads the cells. Without any flags, prints the currently available cells."
    return 0
  end

  if set -ql _flag_a
    set cell_name $argv[1]
    set cell_path $argv[2]
    set cell_priority $argv[3]

    if test -z "$cell_name"
      echo "E: Require non-empty NAME. See ss cells --help" >&2
      return 1
    else if test -z "$cell_path"
      echo "E: Require non-empty PATH See ss cells --help" >&2
      return 1
    else if test -z "$cell_priority"
      set cell_priority 50
    end

    if not string match -rq '\d+' -- "$cell_priority"
      echo "E: PRIORITY must be non-negative integer. See ss cells --help" >&2
      return 1
    else if not string match -rq '[a-zA-Z_0-9-]+|//' -- "$cell_name"
      echo "E: Invalid NAME '$cell_name'. Must match [a-zA-Z_0-9-]+|//" >&2
      return 1
    else if not string match -rq '[^\s]+' -- "$cell_path"
      echo "E: Invalid PATH '$cell_path'. Must match [^\s]+" >&2
      return 1
    end

    for spec in $__slashslash_global_cells
      if string match -rq "^$cell_name\s" -- $spec
        echo "E: $cell_name already registered: $spec" >&2
        return 1
      end
    end

    set -ga __slashslash_global_cells "$cell_name : $cell_path $cell_priority"

    if not set -q _flag_n
      __slashslash_reload_cmd -a
    end
    return 0
  else if set -ql _flag_d
    set cell_name $argv[1]
    if test -z "$cell_name"
      echo "E: Specify NAME of cell you want to delete" >&2
      return 1
    end
    set n (count $__slashslash_global_cells)
    if test $n -eq 0
      echo "W: No cells registered, can't delete $cell_name" >&2
      return 1
    end

    for idx in (seq 1 $n)
      set spec $__slashslash_global_cells[$idx]
      if string match -rq "^$cell_name\s" -- $spec
        __slashslash_verbose "Deleting cell spec: $spec"
        set -e __slashslash_global_cells[$idx]
        if not set -q _flag_n
          __slashslash_reload_cmd -a
        end
        return 0
      end
    end
    echo "W: No cells named $cell_name registered" >&2
    return 1
  end

  if set -ql _flag_r
    __slashslash_reload_cmd
  end

  __slashslash_load_cells

  if not set -qg __slashslash_current_cells; or not set -qg __slashslash_current_cell_paths
    return 0
  end
  set -f n (count $__slashslash_current_cells)
  if test $n -ne (count $__slashslash_current_cell_paths)
    echo "Internal error: mismatch number of cells and paths" >&2
    return 1
  else if test $n -ne (count $__slashslash_current_cell_plugin_names)
    echo "Internal error: mismatch number of cells and cell plugin names" >&2
    return 1
  end
  test $n -eq 0; and return 0

  for i in (seq 1 $n)
    echo $__slashslash_current_cells[$i] : $__slashslash_current_cell_paths[$i] '('$__slashslash_current_cell_plugin_names[$i]')'
  end
end

function __slashslash_reload_cmd
  argparse a/async -- $argv; or return

  __slashslash_load_cells --reset

  if not set -q _flag_a
    set -q slashslash_sync; and set -f was_sync
    set -g slashslash_sync
  end

  __slashslash_pwd_hook

  if not set -q _flag_a; and not set -q was_sync
    set -e slashslash_sync
  end
end
