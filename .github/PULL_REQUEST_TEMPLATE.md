<!--
^ Please include a clear and concise description of the aim of your Pull Request above this line ^

If your pull request aims to fix an open issue or a  bug, please also link the relevant issue below
this line. You may attach an issue to your pull request with `Fixes #<issue number>` outside this
comment, and it will be closed when your pull request is merged.
-->

## Sanity Checking

<!--
Please check all that apply. As before, this section is not a hard requirement but checklists with more checked
items are likely to be merged faster. You may save some time in maintainer reviews by performing self-reviews
here before submitting your pull request.

If your pull request includes any change or unexpected behaviour not covered below, please do make sure to include
it above in your description.
-->

[CONTRIBUTING]: ../CONTRIBUTING.md
[unit tests]: ../tests

- [ ] My changes fit the guidelines found in [CONTRIBUTING] guide
- [ ] I have tested, and self-reviewed my code
- [ ] The [unit tests] for Hjem pass (`nix flake check`/`nix-build -A checks`)
- Style and consistency
  - [ ] I formatted all relevant code (`nix fmt`/`nix run -f . formatter`)
  - [ ] My changes are consistent with the rest of the codebase
  - [ ] My commit messages fit the guidelines found in [CONTRIBUTING]
- If new changes are particularly complex:
  - [ ] My code includes comments in particularly complex areas
  - [ ] I have included a section in the documentation
- Tested on platform(s)
  - [ ] `x86_64-linux`
  - [ ] `aarch64-linux`
  - [ ] `x86_64-darwin`
  - [ ] `aarch64-darwin`

<!--
If your changes touch upon a portion of the codebase that you do not understand well, please make sure to consult
the maintainers on your changes. In most cases, making an issue before creating your PR will help you avoid duplicate
efforts in the long run. `git blame` might help you find out who is the "author" or the "maintainer" of a current
module by showing who worked on it the most.
-->

---

Add a :+1: [reaction] to [pull requests you find important].

[reaction]: https://github.blog/2016-03-10-add-reactions-to-pull-requests-issues-and-comments/
[pull requests you find important]: https://github.com/feel-co/hjem/pulls?q=is%3Aopen+sort%3Areactions-%2B1-desc
