# Contribution Guidelines

<!--toc:start-->

- [Contribution Guidelines](#contribution-guidelines)
  - [Preface](#preface)
  - [Contributing](#contributing)
    - [Writing Tests](#writing-tests)
    - [Writing Documentation](#writing-documentation)
    - [Formatting Code](#formatting-code)
      - [Treewide](#treewide)
      - [Nix](#nix)
      - [Markdown](#markdown)
    - [Commit Format](#commit-format)
      - [Example Scopes](#example-scopes)
  - [Usage without flakes](#usage-without-flakes)
  - [AI Policy](#ai-policy)
    - [What This Means](#what-this-means)
  - [Code of Conduct](#code-of-conduct)

<!--toc:end-->

## Preface

[LICENSE]: ../LICENSE

We are glad you are thinking about contributing to Hjem! The project is largely
shaped by contributors and user feedback, and all contributions are appreciated.

If you are unsure about anything, whether a change is necessary or if it would
be accepted _were_ you to create a PR, please just ask! Or submit the issue or
pull request anyway, the worst that can happen is that you will be politely
asked to change something. Friendly contributions are _always_ welcome.

Before you contribute, we encourage you to read the rest of this document for
our contributing policy and guidelines, followed by the [LICENSE] to understand
how your contributions are licensed.

If you have any questions regarding those files, or would like to ask a question
that is not covered by any of them, please feel free to open an issue!
Discussions tab is also available for less formal discussions.

## Contributing

Anything that benefits all Hjem users are eligible for inclusion. If you have a
really good idea that you think everyone would appreciate, then let's discuss!

There are several guidelines we expect you to adhere to while making a pull
request to Hjem. Namely, we expect you to:

1. Write clean Nix code
2. Self-test your changes, and write integration tests where applicable
3. Document your changes

### Writing Tests

[NixOS manual]: https://nixos.org/manual/nixos/stable/#sec-nixos-tests
[test framework]: https://github.com/feel-co/hjem/tree/main/tests

Hjem leverages Nixpkgs' VM testing framework for its testing infrastructure. You
may find a technical introduction on the [NixOS manual]. Typically, we expect
you to understand and think about the potential side effects and possible edge
cases while adding new features and flow. Those should be carefully tested in
our existing [test framework] with a VM test by either adding a subtest or a new
test to run.

### Writing Documentation

[rendered documentation]: https://hjem.feel-co.org
[ndg]: https://ndg.feel-co.org
[ndg-commonmark]: https://crates.io/crates/ndg-commonmark
[syntax documentation]: https://github.com/feel-co/ndg/blob/main/ndg-commonmark/docs/SYNTAX.md

The [rendered documentation] is powered by [ndg], our in-house documentation
tooling designed to replace `nixos-render-docs` with a more powerful and stylish
Rust program. Per [ndg-commonmark]'s [syntax documentation], most of
Nixpkgs-flavored CommonMark features and Github Flavored Markdown (GFM) are
fully supported.

Keep documentation clear, concise and user-facing.

### Formatting Code

#### Treewide

Please try to keep lines at a reasonable length, ideally 120 characters or less.
For string literals, module descriptions and Markdown documentation sources, 80
is a good middle point.

#### Nix

In addition to the previous guidelines, you must format all Nix code with
`Alejandra`. There is a wrapper provided by the top-level flake, available as
`nix fmt` to find all available Nix code in the repository.

#### Markdown

There is no official formatter for Markdown code, but you are encouraged to run
your Markdown documents through `deno fmt`.

### Commit Format

For your Git commits, you must strongly adhere to **scoped commits**. We would
like commits to be relatively self contained, which means each and every commit
in a pull request should make sense both on its own, and in general context.
That is, a second commit should not resolve an issue that is introduced in an
earlier commit. In this particular situation, you will be asked to amend or
squash any commit that introduces syntax or similar errors if they are fixed in
a subsequent commit.

We also ask you to include the affected code component or module in the first
line. A commit message ideally, but not necessarily, follow the following
template:

```txt
{component}: {description}

{long description}
```

- `component` refers to the module or file you are editing. This is your
  "scope".
- `description` is a short description of your change
- `long description` is the optional addition that should be appended if the
  short description cannot sufficiently convey the motive for the change

For example:

```txt
modules/systemd: init
```

Where `modules/systemd` is the relevant component, and `init` is the task done.
In a scenario where a more complex task has been performed, long description
would be necessary.

> [!TIP]
> In rare cases where a PR affects multiple unrelated components, then the
> `component` part can be replaced with a generic scope such as `treewide` or
> `various.` Maintainers might also use `meta` as a scope for commits that
> affect the repository or the project itself, without direct changes to the
> codebase. `ci` is reserved for CI/CD workflows.

#### Example Scopes

- **docs** - changes that update documentation only, including project README.
- **ci** - changes that update our GHA workflows or relevant components.
- **flake** - changes to the `flake.nix` or the lockfile.
- **meta** - changes that affect the repo as a whole, e.g., Github issue
  templates.
- **treewide/various** - changes that modify a variety of components with
  multiple scopes.

## Usage without flakes

We support usage without flakes. Specifically, you can use the following shell
commands:

| With flakes        | Without flakes               |
| ------------------ | ---------------------------- |
| `nix flake check`  | `nix-build -A checks`        |
| `nix develop`      | `nix-shell -A shell`         |
| `nix build .#hjem` | `nix-build -A packages.hjem` |
| `nix fmt`          | `nix run -f . formatter`     |

You can also `import` the root of the repo and get all of the same attributes as
the flake (without `system`).

## AI Policy

> [!IMPORTANT]
> Pull requests created or submitted by autonomous or supervised AI agents are
> explicitly prohibited, and will be immediately closed without a review. NH, as
> a codebase, does not welcome AI-generated contributions.

This policy exists for the following reasons:

1. **Quality Assurance**: AI-generated code often lacks the contextual
   understanding required for systems-level software that interfaces with
   critical system components. As Hjem deals with sensitive user files, LLMs
   lack the awareness or accountability that we expect from contributions.

2. **Legal and Licensing**: Hjem requires clear authorship and accountability in
   code. AI-generated contributions create ambiguity around copyright and
   licensing obligations. Not to mention the ethical concerns.

3. **Maintenance Burden**: AI-generated contributions often require
   disproportionate maintainer effort to review, correct, and integrate
   properly. It also becomes a long-term maintenance burden if the contribution
   is a drive-by one.

### What This Means

- **Prohibited**: Submitting PRs where an AI agent (autonomous or supervised)
  generated the code, commit messages, or PR description, regardless of whether
  a human clicked the "submit" button.

- **Prohibited**: Using AI agents to automatically fix issues, respond to review
  comments, or generate follow-up commits.

- **Allowed**: Using AI tools as aids while writing code, provided a human
  author thoroughly reviews, tests, and takes full responsibility for the
  submission. AI-assisted PRs require **FULL DISCLOSURE** and appropriate proof
  that the user thoroughly understands the code generated.

By submitting a pull request, you attest that:

1. You are a human contributor
2. You have personally authored or thoroughly reviewed and tested all changes
3. You take full legal and ethical responsibility for the contribution
4. No autonomous or supervised AI agent was used to create or submit the PR
5. You understand the consequences of violating above guidelines.

Violations of this policy may result in a permanent ban from contributing to the
project.

## Code of Conduct

Hjem does not have a formal Code of Conduct yet, and we are sincerely hoping
that we will ever need one. This project is not expected to be a hotbed of
activity, and you should be perfectly capable of keeping it civil and
respectful.

That said, everyone who partakes around Hjem and Hjem-adjacent communities or
contributes to Hjem must be allowed to feel welcome and safe. As such, any
parties that disrupt the project or engage in negative behaviour will be dealt
with swiftly and appropriately. You are invited to share any concerns that you
have with the projects moderation, be it over public or public spaces.
