status is-interactive; or return

function __slashslash_verbose
  set -q slashslash_verbose; and echo $argv >&2
end

function __slashslash_write_cells --description "Internal func to update the cells available for a given process" -a pid -a n_plugins
  set -l pid_info (ps -p "$pid" 2>/dev/null); or return 1
  test (count $pid_info) -eq 2; or return 1
  string match -rq 'fish$' -- "$pid_info[2]"; or return 1
  set -e argv[1..2]
  for plug_idx in (seq 1 $n_plugins)
    set plugin $argv[$plug_idx]
    set plugin_name $argv[(math $plug_idx + $n_plugins)]
    set real_plugin_name "$plugin_name"
    set plugin_workspace
    for line in ($plugin)
      if string match -rq '^__plugin_name__\s+(?<synth_name>.*)$' -- "$line"
        set plugin_name "$real_plugin_name:$synth_name"
        continue
      end
      if string match -rq '^__plugin_workspace__\s+(?<workspace_path>.*)$' -- "$line"
        set plugin_workspace $workspace_path
        continue
      end
      if not string match -rq '^\s*(?<cell>([a-zA-Z_0-9-]+|//))\s*:\s*(?<path>[^\s]+)(\s+(?<prio>\d+))?$' -- "$line"
        __slashslash_verbose "Unable to parse cell: $line"
        continue
      end
      if test -n "$plugin_workspace"; and test (string sub -l 1 -- "$path") != "/"
        set path "$plugin_workspace/$path"
      end
      if not set -q prio; or test -z "$prio"
        set prio 100
      end
      if set idx (contains -i -- "$cell" $cell_names)
        set other_path $cell_paths[$idx]
        set other_prio $cell_prios[$idx]
        set other_name $cell_plugin_names[$idx]
        if test "$other_prio" -lt "$prio"
          __slashslash_verbose "Overwriting $cell: $other_path ($other_name) < $path ($plugin_name)"
          set cell_paths[$idx] "$path"
          set cell_prios[$idx] "$prio"
          set cell_plugin_names[$idx] "$plugin_name"
        else
          __slashslash_verbose "Not overwriting $cell: $other_path ($other_name) >= $path ($plugin_name)"
        end
        continue
      end
      set -af cell_names "$cell"
      set -af cell_paths "$path"
      set -af cell_prios "$prio"
      set -af cell_plugin_names "$plugin_name"
    end
  end
  set scratch "/tmp/.slashslash_fish_cells_$pid.tmp"
  string join \n -- $cell_names > "$scratch"
  string join \n -- $cell_paths >> "$scratch"
  string join \n -- $cell_plugin_names >> "$scratch"
  count $cell_names >> "$scratch"
  echo $PWD >> "$scratch"
  mv "$scratch" /tmp/slashslash_fish_cells_$pid
  __slashslash_verbose "Successfully loaded cells for $PWD"
end

function __slashslash_load_cells --description "Internal func to load cells from disk"
  argparse r/reset -- $argv
  if set -ql _flag_r
    set -e __slashslash_current_cells
    set -e __slashslash_current_cell_paths
    set -e __slashslash_current_cell_plugin_names
    set -e __slashslash_loaded_pwd
    return 0
  end

  test "$__slashslash_loaded_pwd" = "$PWD"; and return

  set loaded_data (cat /tmp/slashslash_fish_cells_$fish_pid 2>/dev/null)
  if test (count $loaded_data) -eq 0
    __slashslash_load_cells -r
    return 0
  end

  set loaded_pwd $loaded_data[-1]
  set n_cells $loaded_data[-2]

  if test $n_cells -gt 0
    for i in (seq 1 $n_cells)
      set cell $loaded_data[$i]
      set path $loaded_data[(math $n_cells + $i)]
      set plugin_name $loaded_data[(math $n_cells + $n_cells + $i)]
      if not string match -rq '.*//$' -- $cell
        set cell "$cell//"
      end
      set -a cells "$cell"
      set -a paths "$path"
      set -a plugin_names "$plugin_name"
    end
  end

  set -g __slashslash_current_cells $cells
  set -g __slashslash_current_cell_paths $paths
  set -g __slashslash_current_cell_plugin_names $plugin_names
  set -g __slashslash_loaded_pwd $loaded_data[-1]
  return 0
end

function __slashslash_invoke --description 'Expand any // and invoke'
  set -f cmd (__slashslash_expand_cmd -f (string escape -- $argv))
  __slashslash_verbose "//> $cmd"
  eval $cmd
end

function __slashslash_gen_write_cells_script -a n_plugins
  functions --no-details __slashslash_verbose
  functions --no-details __slashslash_write_cells
  set -e argv[1]
  if test $n_plugins -gt 0
    for i in (seq 1 $n_plugins)
      functions --no-details "$argv[$i]"
    end
  end
  if set -q slashslash_verbose
    echo 'set -g slashslash_verbose'
  end
  for spec in $__slashslash_global_cells
    echo "set -ga __slashslash_global_cells '$spec'"
  end
  echo "__slashslash_write_cells $fish_pid $n_plugins $argv"
end

function __slashslash_pwd_hook --on-variable PWD --description '// PWD change hook'
  set -qg NO_SLASHSLASH; and return
  set -qg __slashslash_plugins; or return
  test "$__slashslash_loaded_pwd" = "$PWD"; and return

  for plugin in $__slashslash_plugins
    set -l function_key __slashslash_plugin_$plugin
    set -qg $function_key; or continue
    set -af plugin_funcs $$function_key
    set -af plugin_names $plugin
  end

  __slashslash_load_cells -r

  if set -q slashslash_verbose
    set -f inherited_env slashslash_verbose=1
  end

  begin
    set -l IFS
    set -l shell_exe (status fish-path)
    set -l shell_script (__slashslash_gen_write_cells_script (count $plugin_funcs) $plugin_funcs $plugin_names)

    __slashslash_verbose "Running under $shell_exe: `$shell_script`"
    if set -q slashslash_sync
      $shell_exe --no-config -c "$shell_script"
    else
      $shell_exe --no-config -c "$shell_script" &; disown
    end
  end
end

function __slashslash_exit --on-event fish_exit
  test -f "/tmp/slashslash_fish_cells_$fish_pid"; and rm -f "/tmp/slashslash_fish_cells_$fish_pid"
end

# User can run e.g. `!! //foo/bar`
alias !! "eval"

# Setup defaults: user can disable with ss disable
ss !! cat ls cp rm mv cd zip unzip vim nvim vi buck sl git hg grep ack

# Builtin plugins
function __slashslash_buck_completer -a cur
  command buck complete --target="$cur" 2>/dev/null | command grep -v ':$'
end

function __slashslash_buck_subpather -a cur
  string replace -r '(?<!\\\\):(?!.*/)' / -- "$cur"
end

function __slashslash_buck
  type -q buck; or return
  set -l root (buck root 2>/dev/null); or return
  echo "//: $root 200"
  buck audit cell 2>/dev/null | sed 's|$| 200|'
end

function __slashslash_git
  set root (git rev-parse --show-toplevel 2>/dev/null); or return
  echo "//:$root 150"
end

function __slashslash_hg
  if type -q sl
    set root (sl root 2>/dev/null); or return 0
  else if type -q hg
    set root (hg root 2>/dev/null); or return 0
  end
  echo "//:$root"
end

function __slashslash_global_cell_plugin
  for spec in $__slashslash_global_cells
    echo $spec
  end
end

function __slashslash_dotfile_plugin
  set d "$PWD"
  while not test "$d" = "/"
    set f "$d/.ss"
    if test -f "$f"
      echo "__plugin_name__ $f"
      echo "__plugin_workspace__ $d"
      cat $f
    end
    set d (path dirname "$d")
  end
end

ss plugin buck __slashslash_buck -c __slashslash_buck_completer -s __slashslash_buck_subpather
ss plugin git __slashslash_git
ss plugin hg __slashslash_hg
ss plugin global __slashslash_global_cell_plugin
ss plugin dotfile __slashslash_dotfile_plugin

# Load cells for initial PWD
__slashslash_pwd_hook
