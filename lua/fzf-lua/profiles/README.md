## FzfLua Profiles

This folder contains preconfigured fzf-lua profiles which can be activated using
`:FzfLua profiles` or used as a `string` argument at the first index of the table
sent to the `setup` function:
```lua
require("fzf-lua").setup({ "fzf-native" })
```
> **Note:** `setup` can be called multiple times for profile "live" switching

You can also start with a profile as "baseline" and customize it, for example,
telescope defaults with `bat` previewer:
```lua
:lua require"fzf-lua".setup({"telescope",winopts={preview={default="bat"}}})
```

### Current profiles list

| Profile          | Details                                    |
| ---------------- | ------------------------------------------ |
| `default`          | fzf-lua defaults, uses neovim "builtin" previewer and devicons (if available) for git/files/buffers |
| `default-title`    | fzf-lua defaults, using title instead of prompt |
| `fzf-native`       | utilizes fzf's native previewing ability in the terminal where possible using `bat` for previews |
| `fzf-tmux`         | similar to `fzf-native` and opens in a tmux popup (requires tmux > 3.2) |
| `fzf-vim`          | closest to `fzf.vim`'s defaults (+icons), also sets up user commands (`:Files`, `:Rg`, etc) |
| `max-perf`         | similar to `fzf-native` and disables icons globally for max performance |
| `telescope`        | closest match to telescope defaults in look and feel and keybinds |
| `skim`             | uses [`skim`](https://github.com/skim-rs/skim) as an fzf alternative, (requires the `sk` binary) |
| `borderless`       | borderless and minimalistic seamless look &amp; feel |
| `borderless_full`  | borderless with description in window title (instead of prompt)  |


**Custom user settings which make sense and aren't mere duplications with minimal modifications
are more than welcome**

<sup><sub>&ast;&ast;Please be sure to update this README and add your name to the table for credit
when submitting a user-profile.</sub></sup>
