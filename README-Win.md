## NOTE: RECOMMENDED FZF VERSION >= 0.52.1

**To avoid issues with `live_grep|live_grep_native` and special characters upgrade your fzf
binary at the minimum to version 0.52.1**

- Any version <= 0.50 will work but have issues with `live_grep_native`
([junegunn/fzf#3626](https://github.com/junegunn/fzf/issues/3626)).

- Versions 0.51.0/0.52.0 should be avoided due to
[junegunn/fzf#3789](https://github.com/junegunn/fzf/issues/3789).

## Windows Known Issues and Limitations

As fzf-lua is bound by the same constraints, please read
[fzf's Windows Wiki page](https://github.com/junegunn/fzf/wiki/Windows).

It took a lot of work to make everything work exactly as it does on *NIX/OSX.
Fzf-lua attempts to overcome inherent fzf Windows woes (escaping, etc) by using
our command proxy wrapper and working around the issues using lua code.

### Single quotes in commands / options

On Windows, single quotes `'` in command arguments are treated as a string literal,
that means that wrapping arguments with single quotes does not translate into a single
string the same way a double quoted argument is treated, i.e. `'foo bar' != "foo bar"`.

To avoid issues, make sure none of your `cmd`'s `rg_opts`, `fd_opts`, `preview`, etc
contains single hyphens that should be treated as quotes, this is probably the case
if you copied old fzf-lua defaults into your `setup` options.
