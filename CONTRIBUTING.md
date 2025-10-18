# Contribution Guidelines

<!--toc:start-->

- [Contribution Guidelines](#contribution-guidelines)
  - [Preface](#preface)
  - [Contributing](#contributing)
    - [General Guidelines](#general-guidelines)
    - [Formatting Code](#formatting-code)
      - [Treewide](#treewide)
      - [Nix](#nix)
      - [Markdown](#markdown)
    - [Commit Format](#commit-format)
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

### General Guidelines

There are several guidelines we expect you to adhere to while making a pull
request to Hjem. Namely, we expect you to:

1. Write clean Nix code
2. Self-test your changes, and write integration tests where applicable
3. Document your changes

### Formatting Code

#### Treewide

Please try to keep lines at a reasonable length, ideally 120 characters or less.
For string literals, module descriptions and documentation, 80 is a good middle
point.

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
