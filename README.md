# nvim-jenkinsfile-linter

A small plugin for Neovim that utilizes the [Jenkins pipeline
linter](https://www.jenkins.io/doc/book/pipeline/development/) to ensure your
Jenkinsfiles are valid before using them.

https://user-images.githubusercontent.com/13974112/147474213-b4a0cfdb-e7c5-420d-89b2-293deb312a27.mov

## Prerequisites

- Neovim >= 0.6
- curl available
- [Plenary.nvim](https://github.com/nvim-lua/plenary.nvim) installed
- Ensure you have `JENKINS_USERNAME`, `JENKINS_HOST`, and also either `JENKINS_TOKEN`
    or `JENKINS_PASSWORD` set.

## Installation

```lua
use({'ckipp01/nvim-jenkinsfile-linter', requires = { "nvim-lua/plenary.nvim" } })
```

## Docs

[`:h nvim-jenkinsfile-linter`](https://github.com/ckipp01/nvim-jenkinsfile-linter/blob/main/doc/jenkinsfile-linter.txt)
