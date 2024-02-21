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

### live_grep_native

When using `live_grep_native` we are sending the `rg` command directly
to fzf (without the fzf-lua wrapper) and are therefore bound by fzf's escaping
requirements.

For example, `^` is a special escape character on windows and also a regex special
character. Say we wanted to search for all lines that start with "local", we would
run:
```lua
-- we use `no_esc` to tell rg we're using a regex
:FzfLua live_grep no_esc=true search=^local
```

However, when using the native version we need to escape the caret twice:
```lua
:FzfLua live_grep no_esc=true search=^^local
```

More so, I couldn't find a way to send special regex chars `[(|.*^$` as the backslash
is always doubled by fzf's `{q}`<sub><sup>&ast; see bottom note</sup></sub>.

For example, if we run:
```cmd
break | fzf --ansi --disabled --bind="change:reload:rg --line-number --column --color=always {q}"
```

And try to search for the literal `[` by typing `\[`, we get the error:
```
[Command failed: rg --line-number --column --color=always ^"\\[^"]
```

If we double the blackslashes by typing `\\[` we get the error:
```
[Command failed: rg --line-number --column --color=always ^"\\\\[^"]
```

<sub><sup>&ast; upstream issue: https://github.com/junegunn/fzf/issues/3626</sup></sub>
