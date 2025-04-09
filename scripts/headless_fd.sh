#!/bin/sh

BASEDIR=$(cd "$(dirname "$0")" ; pwd -P)

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options"
    echo "-h, --help            Show this help"
    echo "-d, --debug           Debug level [0|1|2|false|true|v]"
    echo ""
    echo "Display Options"
    echo "-c, --cwd             Working Directory"
    echo "-x, --cmd             Executed Command (default: fd --color=never)"
    echo "-g, --git-icons       Git icons [0|1|false|true] (default:false)"
    echo "-f, --file-icons      File icons [0|1|false|true] (default:true)"
    echo "--color               Color icons [0|1|false|true] (default:true)"
}

# saner programming env: these switches turn some bugs into errors
set -o noclobber -o nounset

# -allow a command to fail with !’s side effect on errexit
# -use return value from ${PIPESTATUS[0]}, because ! hosed $?
getopt --test > /dev/null 
if [ $? -ne 4 ]; then
    echo '`getopt --test` failed in this environment.'
    exit 1
fi

OPTIONS=hd:c:x:f:g:
LONGOPTS=help,debug:,cwd:,file-icons:,git-icons:,color:,cmd:

PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [ $? -ne 0 ]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    usage;
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

debug="false"
cwd= cmd=
git_icons="false"
file_icons="true"
color_icons="true"

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -h|--help)
            usage;
            exit 0
            ;;
        -d|--debug)
            case $2 in
                "2"|"v"|"verbose")
                    debug="v"
                    ;;
                "1"|"true")
                    debug="true"
                    ;;
                *)
                    debug="false"
                    ;;
            esac
            shift 2
            ;;
        -c|--cwd)
            cwd="$2"
            shift 2
            ;;
        -x|--cmd)
            cmd="$2"
            shift 2
            ;;
        -f|--file-icons)
            case $2 in
                "0"|"false")
                    file_icons="false"
                    ;;
                *)
                    file_icons="true"
                    ;;
            esac
            shift 2
            ;;
        -g|--git-icons)
            case $2 in
                "0"|"false")
                    git_icons="false"
                    ;;
                *)
                    git_icons="true"
                    ;;
            esac
            shift 2
            ;;
        --color)
            case $2 in
                "0"|"false")
                    color_icons="false"
                    ;;
                *)
                    color_icons="true"
                    ;;
            esac
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            # never get here!
            echo "error: error while parsing command line arguments"
            usage;
            exit 3
            ;;
    esac
done

# handle non-option arguments
if [ $# -gt 0 ]; then
    echo "error: unrecgonized option"
    usage;
    exit 4
fi

VIMRUNTIME=/usr/share/nvim/runtime \
/usr/bin/nvim -u NONE -l ${BASEDIR}/../lua/fzf-lua/spawn.lua "return
  -- opts
  {
    g = {
      --_fzf_lua_server = [[/run/user/1000/fzf-lua.1710687343.12851.1]],
      _devicons_path = [[${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/nvim-web-devicons]],
      _devicons_setup = [[${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lua/plugins/devicons/setup.lua]],
    },
    _base64 = false,
    debug = [[$debug]] == [[v]] and [[v]] or $debug,
    file_icons = ${file_icons},
    git_icons = ${git_icons},
    color_icons = ${color_icons},
    cmd = [[${cmd:-fd --color=never}]],
    cwd = vim.fn.expand([[${cwd:-$BASEDIR}]]),
  },
  -- fn_transform
  [==[
    return require(\"fzf-lua.make_entry\").file
  ]==],
  -- fn_preprocess
  [==[
    return require(\"fzf-lua.make_entry\").preprocess
  ]==]
"
