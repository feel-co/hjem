use jiff::{Timestamp, civil::Date};
use pound::Parse;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use smfh_core::manifest::{File, FileKind, Manifest};
use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::Command as ProcCommand;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Parse, Debug)]
#[pound(name = "hjem", version = "0.1.0")]
/// Hjem standalone CLI.
struct Cli {
    #[pound(subcommand)]
    command: Command,
}

#[derive(Parse, Debug)]
enum Command {
    Standalone {
        #[pound(subcommand)]
        command: StandaloneCommand,
    },
    Internal {
        #[pound(subcommand)]
        command: InternalCommand,
    },
    Manifest {
        #[pound(subcommand)]
        command: ManifestCommand,
    },
    Activate {
        #[pound(long)]
        manifest: PathBuf,
        #[pound(long)]
        state: PathBuf,
        #[pound(long, default = ".backup-")]
        prefix: String,
        #[pound(long)]
        impure: bool,
        #[pound(long)]
        json: bool,
    },
}

#[derive(Parse, Debug)]
enum ManifestCommand {
    Validate {
        #[pound(long)]
        manifest: PathBuf,
        #[pound(long)]
        impure: bool,
        #[pound(long)]
        json: bool,
    },
    Diff {
        #[pound(long = "new")]
        new_manifest: PathBuf,
        #[pound(long = "old")]
        old_manifest: PathBuf,
        #[pound(long)]
        impure: bool,
        #[pound(long)]
        json: bool,
    },
}

#[derive(Parse, Debug)]
enum InternalCommand {
    ValidateManifest {
        #[pound(long)]
        manifest: PathBuf,
        #[pound(long)]
        impure: bool,
        #[pound(long)]
        json: bool,
    },
    Activate {
        #[pound(long)]
        manifest: PathBuf,
        #[pound(long)]
        state: PathBuf,
        #[pound(long)]
        actions_file: Option<PathBuf>,
        #[pound(long, default = ".backup-")]
        prefix: String,
        #[pound(long)]
        impure: bool,
        #[pound(long)]
        external_linker: Option<PathBuf>,
        #[pound(long = "linker-arg")]
        linker_args: Vec<String>,
        #[pound(long)]
        json: bool,
    },
    ReloadActions {
        #[pound(long)]
        actions_file: PathBuf,
        #[pound(long)]
        user: String,
        #[pound(long)]
        require_running_systemd: bool,
        #[pound(long)]
        json: bool,
    },
    CleanupState {
        #[pound(long)]
        state_dir: PathBuf,
        #[pound(long = "enabled-user")]
        enabled_users: Vec<String>,
        #[pound(long)]
        json: bool,
    },
}

#[derive(Parse, Debug)]
enum StandaloneCommand {
    Init {
        #[pound(long)]
        dir: Option<PathBuf>,
        #[pound(long)]
        no_flake: bool,
        #[pound(long)]
        switch: bool,
    },
    Switch {
        #[pound(long)]
        manifest: Option<PathBuf>,
        #[pound(long)]
        config: Option<PathBuf>,
        #[pound(long)]
        flake: Option<String>,
        #[pound(long)]
        flake_attr: Option<String>,
        #[pound(long)]
        state_dir: Option<PathBuf>,
        #[pound(long)]
        rollback: bool,
        #[pound(long)]
        external_linker: Option<PathBuf>,
        #[pound(long = "linker-arg")]
        linker_args: Vec<String>,
        #[pound(long, default = ".backup-")]
        prefix: String,
        #[pound(long)]
        impure: bool,
    },
    Build {
        #[pound(long)]
        manifest: Option<PathBuf>,
        #[pound(long)]
        config: Option<PathBuf>,
        #[pound(long)]
        flake: Option<String>,
        #[pound(long)]
        flake_attr: Option<String>,
        #[pound(long)]
        state_dir: Option<PathBuf>,
        #[pound(long)]
        impure: bool,
    },
    Generations {
        #[pound(long)]
        state_dir: Option<PathBuf>,
    },
    RemoveGenerations {
        ids: Vec<String>,
        #[pound(long)]
        state_dir: Option<PathBuf>,
    },
    Rollback {
        #[pound(long)]
        state_dir: Option<PathBuf>,
        #[pound(long)]
        generation: Option<String>,
        #[pound(long)]
        external_linker: Option<PathBuf>,
        #[pound(long = "linker-arg")]
        linker_args: Vec<String>,
        #[pound(long, default = ".backup-")]
        prefix: String,
        #[pound(long)]
        impure: bool,
    },
    ExpireGenerations {
        timestamp: Option<String>,
        #[pound(long)]
        keep_last: Option<usize>,
        #[pound(long)]
        state_dir: Option<PathBuf>,
    },
}

#[derive(Serialize, Deserialize, Clone)]
struct TriggerAction {
    action: String,
    unit: String,
    reason: String,
}

#[derive(Serialize, Deserialize)]
struct ActivateResult {
    mode: String,
    actions: Vec<TriggerAction>,
}

#[derive(Serialize)]
struct ValidateResult {
    ok: bool,
    file_count: usize,
    version: u64,
}

#[derive(Serialize)]
struct DiffResult {
    ok: bool,
    changed: bool,
}

#[derive(Serialize)]
struct CleanupResult {
    removed: Vec<String>,
}

#[derive(Serialize)]
struct ReloadResult {
    skipped: bool,
    reason: Option<String>,
    applied: usize,
}

pub fn run() -> Result<(), String> {
    let cli = parse_multicall_cli();
    match cli.command {
        Command::Manifest { command } => run_manifest(command),
        Command::Activate {
            manifest,
            state,
            prefix,
            impure,
            json,
        } => run_activate_internal(ActivateArgs {
            manifest,
            state,
            actions_file: None,
            prefix,
            impure,
            external_linker: None,
            linker_args: Vec::new(),
            json,
        }),
        Command::Internal { command } => run_internal(command),
        Command::Standalone { command } => run_standalone(command),
    }
}

fn parse_multicall_cli() -> Cli {
    match parse_multicall_args(std::env::args()) {
        Ok(cli) => cli,
        Err(error) => error.exit(),
    }
}

fn parse_multicall_args(args: impl IntoIterator<Item = String>) -> Result<Cli, pound::Error> {
    let mut args = args.into_iter();
    let program = args.next();
    let prog_name = program
        .as_deref()
        .and_then(|prog| Path::new(prog).file_name())
        .and_then(|name| name.to_str())
        .unwrap_or_default();
    let mut remapped = args.collect::<Vec<_>>();

    match prog_name {
        "hjem-internal" => remapped.insert(0, "internal".to_string()),
        "hjem-standalone" => remapped.insert(0, "standalone".to_string()),
        _ => {}
    }
    normalize_expire_timestamp(&mut remapped);
    Cli::try_parse_from(remapped.iter().map(String::as_str))
}

fn normalize_expire_timestamp(args: &mut Vec<String>) {
    let Some(command_index) = args
        .windows(2)
        .position(|args| args == ["standalone", "expire-generations"])
    else {
        return;
    };

    let Some(timestamp_index) = args[command_index + 2..]
        .iter()
        .position(|arg| {
            arg.starts_with('-') && arg.as_bytes().get(1).is_some_and(u8::is_ascii_digit)
        })
        .map(|index| command_index + 2 + index)
    else {
        return;
    };
    args.insert(timestamp_index, "--".to_string());
}

fn run_manifest(command: ManifestCommand) -> Result<(), String> {
    match command {
        ManifestCommand::Validate {
            manifest,
            impure,
            json,
        } => {
            let m = read_verified(&manifest, impure)?;
            if json {
                print_json(&ValidateResult {
                    ok: true,
                    file_count: m.files.len(),
                    version: m.version,
                })?;
            } else {
                println!("ok");
            }
            Ok(())
        }
        ManifestCommand::Diff {
            new_manifest,
            old_manifest,
            impure,
            json,
        } => {
            let current = read_verified(&new_manifest, impure)?;
            let changed = !manifests_equivalent(&current, &old_manifest, impure)?;
            if json {
                print_json(&DiffResult { ok: true, changed })?;
            } else if changed {
                println!("changed");
            } else {
                println!("unchanged");
            }
            Ok(())
        }
    }
}

fn run_internal(command: InternalCommand) -> Result<(), String> {
    match command {
        InternalCommand::ValidateManifest {
            manifest,
            impure,
            json,
        } => {
            let m = read_verified(&manifest, impure)?;
            if json {
                print_json(&ValidateResult {
                    ok: true,
                    file_count: m.files.len(),
                    version: m.version,
                })?;
            }
            Ok(())
        }
        InternalCommand::Activate {
            manifest,
            state,
            actions_file,
            prefix,
            impure,
            external_linker,
            linker_args,
            json,
        } => run_activate_internal(ActivateArgs {
            manifest,
            state,
            actions_file,
            prefix,
            impure,
            external_linker,
            linker_args,
            json,
        }),
        InternalCommand::ReloadActions {
            actions_file,
            user,
            require_running_systemd,
            json,
        } => run_reload_actions(&actions_file, &user, require_running_systemd, json),
        InternalCommand::CleanupState {
            state_dir,
            enabled_users,
            json,
        } => run_cleanup_state(&state_dir, &enabled_users, json),
    }
}

fn run_standalone(command: StandaloneCommand) -> Result<(), String> {
    match command {
        StandaloneCommand::Init {
            dir,
            no_flake,
            switch,
        } => {
            let conf_dir = standalone_config_dir(dir)?;
            fs::create_dir_all(&conf_dir).map_err(|e| e.to_string())?;

            let home_nix = conf_dir.join("hjem.nix");
            let mut created_files = Vec::new();
            if !home_nix.exists() {
                let example = conf_dir.join("dotfiles/example");
                let example_parent = example
                    .parent()
                    .ok_or_else(|| format!("invalid example path: {}", example.display()))?;
                fs::create_dir_all(example_parent).map_err(|e| e.to_string())?;
                if !example.exists() {
                    fs::write(&example, "Example Hjem standalone configuration.\n")
                        .map_err(|e| e.to_string())?;
                    created_files.push(example);
                }
                fs::write(
                    &home_nix,
                    format!(
                        "{{\n  version = 3;\n  files = [\n    {{\n      type = \"symlink\";\n      source = ./dotfiles/example;\n      target = \"{}/.config/example\";\n    }}\n  ];\n}}\n",
                        home_dir()?.display()
                    ),
                )
                .map_err(|e| e.to_string())?;
                created_files.push(home_nix.clone());
            }

            if !no_flake {
                let flake_nix = conf_dir.join("flake.nix");
                if !flake_nix.exists() {
                    let user = std::env::var("USER").unwrap_or_else(|_| "user".to_string());
                    fs::write(
                        &flake_nix,
                        format!(
                            "{{\n  description = \"Hjem standalone configuration\";\n\n  outputs = {{ self }}: {{\n    hjemConfigurations.\"{user}\".manifest = import ./hjem.nix;\n  }};\n}}\n"
                        ),
                    )
                    .map_err(|e| e.to_string())?;
                    created_files.push(flake_nix);
                }
            }

            println!(
                "Initialized Hjem standalone config in {}",
                conf_dir.display()
            );
            if created_files.is_empty() {
                println!("No new files were created (existing config kept as-is).");
            } else {
                for path in created_files {
                    println!("Created {}", path.display());
                }
            }
            if no_flake {
                println!(
                    "Next step: hjem standalone switch --config {}",
                    home_nix.display()
                );
            } else {
                println!(
                    "Next step: hjem standalone switch --flake {}",
                    conf_dir.display()
                );
            }

            if switch {
                println!("Applying initial generation...");
                let source = if no_flake {
                    StandaloneSource::Config(home_nix)
                } else {
                    StandaloneSource::Flake(conf_dir)
                };
                standalone_switch_from_source(
                    source,
                    None,
                    None,
                    Vec::new(),
                    ".backup-".to_string(),
                    false,
                )?;
                println!("Initial generation applied.");
            }

            Ok(())
        }
        StandaloneCommand::Switch {
            manifest,
            config,
            flake,
            flake_attr,
            state_dir,
            rollback,
            external_linker,
            linker_args,
            prefix,
            impure,
        } => {
            if rollback {
                let set_count = usize::from(manifest.is_some())
                    + usize::from(config.is_some())
                    + usize::from(flake.is_some())
                    + usize::from(flake_attr.is_some());
                if set_count != 0 {
                    return Err(
                        "--rollback cannot be combined with --manifest/--config/--flake/--flake-attr"
                            .to_string(),
                    );
                }
                standalone_switch_rollback(
                    state_dir,
                    external_linker,
                    linker_args,
                    prefix,
                    impure,
                )?;
            } else {
                let source = standalone_source(manifest, config, flake, flake_attr)?;
                standalone_switch_from_source(
                    source,
                    state_dir,
                    external_linker,
                    linker_args,
                    prefix,
                    impure,
                )?;
            }
            Ok(())
        }
        StandaloneCommand::Build {
            manifest,
            config,
            flake,
            flake_attr,
            state_dir,
            impure,
        } => {
            let manifest = resolve_manifest_input(manifest, config, flake, flake_attr, impure)?;
            let _ = read_verified(&manifest.path, impure)?;
            let base = standalone_state_dir(state_dir)?;
            let builds = base.join("builds");
            fs::create_dir_all(&builds).map_err(|e| e.to_string())?;
            let build_id = now_id("build");
            atomic_copy(&manifest.path, &builds.join(format!("{build_id}.json")))?;
            println!("Build recorded: {build_id}");
            Ok(())
        }
        StandaloneCommand::Generations { state_dir } => {
            let base = standalone_state_dir(state_dir)?;
            let gens = list_generations(&base)?;
            if gens.is_empty() {
                println!(
                    "No generations found in {}",
                    base.join("generations").display()
                );
                return Ok(());
            }
            for g in gens {
                println!("{}", g.display());
            }
            Ok(())
        }
        StandaloneCommand::RemoveGenerations { ids, state_dir } => {
            if ids.is_empty() {
                return Err("remove-generations expects at least one generation id".to_string());
            }
            let base = standalone_state_dir(state_dir)?;
            let current = read_current_generation_id(&base)?;
            let mut removed = 0usize;
            for id in ids {
                if current.as_deref() == Some(id.as_str()) {
                    return Err(format!(
                        "Refusing to remove current generation {id}; roll back first"
                    ));
                }
                let path = base.join("generations").join(&id);
                if path.exists() {
                    fs::remove_dir_all(&path).map_err(|e| e.to_string())?;
                    removed += 1;
                }
            }
            println!("Removed {removed} generation(s).");
            Ok(())
        }
        StandaloneCommand::Rollback {
            state_dir,
            generation,
            external_linker,
            linker_args,
            prefix,
            impure,
        } => {
            let base = standalone_state_dir(state_dir)?;
            let target_id = if let Some(generation) = generation {
                generation
            } else {
                previous_generation_id(&base)?
            };
            let target = generation_manifest_path(&base, &target_id)?;
            let state = base.join("current").join("manifest.json");
            run_activate_internal(ActivateArgs {
                manifest: target,
                state,
                actions_file: Some(base.join("current").join("actions.json")),
                prefix,
                impure,
                external_linker,
                linker_args,
                json: false,
            })?;
            set_current_generation_id(&base, &target_id)?;
            println!("Rolled back to generation {target_id}");
            Ok(())
        }
        StandaloneCommand::ExpireGenerations {
            timestamp,
            keep_last,
            state_dir,
        } => {
            let base = standalone_state_dir(state_dir)?;
            let mut gens = list_generations(&base)?;
            if timestamp.is_none() && keep_last.is_none() {
                return Err(
                    "expire-generations expects a timestamp and/or --keep-last N".to_string(),
                );
            }
            let cutoff = timestamp
                .as_deref()
                .map(parse_expire_timestamp)
                .transpose()?;
            let current = read_current_generation_id(&base)?;
            let protected_by_keep_last = keep_last
                .map(|keep_last| newest_generation_ids(&gens, keep_last))
                .unwrap_or_default();
            let mut removed = 0usize;

            for path in gens.drain(..) {
                let Some(id) = generation_id_from_path(&path) else {
                    continue;
                };
                if current.as_deref() == Some(id.as_str()) {
                    continue;
                }
                if protected_by_keep_last.contains(&id) {
                    continue;
                }
                let Some(gen_ts) = generation_timestamp_from_id(&id) else {
                    continue;
                };
                if cutoff.is_none_or(|cutoff| gen_ts <= cutoff) {
                    fs::remove_dir_all(path).map_err(|e| e.to_string())?;
                    removed += 1;
                }
            }
            println!("Expired {removed} generation(s).");
            Ok(())
        }
    }
}

struct ResolvedManifest {
    path: PathBuf,
    _temp_dir: Option<PathBuf>,
}

enum StandaloneSource {
    Manifest(PathBuf),
    Config(PathBuf),
    Flake(PathBuf),
    FlakeWithAttr(String, Option<String>),
}

fn standalone_source(
    manifest: Option<PathBuf>,
    config: Option<PathBuf>,
    flake: Option<String>,
    flake_attr: Option<String>,
) -> Result<StandaloneSource, String> {
    if flake_attr.is_some() && flake.is_none() {
        return Err("--flake-attr requires --flake".to_string());
    }

    match (manifest, config, flake) {
        (Some(path), None, None) => Ok(StandaloneSource::Manifest(path)),
        (None, Some(path), None) => Ok(StandaloneSource::Config(path)),
        (None, None, Some(flake)) => Ok(StandaloneSource::FlakeWithAttr(flake, flake_attr)),
        _ => Err(
            "Provide exactly one of --manifest, --config, or --flake for standalone commands"
                .to_string(),
        ),
    }
}

fn resolve_manifest_input(
    manifest: Option<PathBuf>,
    config: Option<PathBuf>,
    flake: Option<String>,
    flake_attr: Option<String>,
    impure: bool,
) -> Result<ResolvedManifest, String> {
    if flake_attr.is_some() && flake.is_none() {
        return Err("--flake-attr requires --flake".to_string());
    }

    let set_count = usize::from(manifest.is_some())
        + usize::from(config.is_some())
        + usize::from(flake.is_some());
    if set_count != 1 {
        return Err(
            "Provide exactly one of --manifest, --config, or --flake for standalone commands"
                .to_string(),
        );
    }

    if let Some(path) = manifest {
        return Ok(ResolvedManifest {
            path,
            _temp_dir: None,
        });
    }

    let json = if let Some(config_path) = config.as_ref() {
        eval_nix_config(config_path, impure)?
    } else if let Some(flake_ref) = flake.as_ref() {
        eval_nix_flake(flake_ref, flake_attr.as_deref(), impure)?
    } else {
        return Err("No manifest source was provided".to_string());
    };

    let manifest_json = extract_manifest_json(json)?;
    let temp_dir = mk_temp_dir("hjem-manifest-eval")?;
    let manifest_path = temp_dir.join("manifest.json");
    fs::write(
        &manifest_path,
        serde_json::to_vec_pretty(&manifest_json).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;

    Ok(ResolvedManifest {
        path: manifest_path,
        _temp_dir: Some(temp_dir),
    })
}

fn standalone_switch_from_source(
    source: StandaloneSource,
    state_dir: Option<PathBuf>,
    external_linker: Option<PathBuf>,
    linker_args: Vec<String>,
    prefix: String,
    impure: bool,
) -> Result<(), String> {
    println!("Evaluating standalone input...");
    let (manifest, source_ref) = match source {
        StandaloneSource::Manifest(path) => (
            resolve_manifest_input(Some(path.clone()), None, None, None, impure)?,
            StandaloneSource::Manifest(path),
        ),
        StandaloneSource::Config(path) => (
            resolve_manifest_input(None, Some(path.clone()), None, None, impure)?,
            StandaloneSource::Config(path),
        ),
        StandaloneSource::Flake(path) => {
            let flake_ref = path
                .to_str()
                .ok_or_else(|| "Invalid flake path".to_string())?
                .to_string();
            (
                resolve_manifest_input(None, None, Some(flake_ref.clone()), None, impure)?,
                StandaloneSource::Flake(path),
            )
        }
        StandaloneSource::FlakeWithAttr(flake_ref, flake_attr) => (
            resolve_manifest_input(
                None,
                None,
                Some(flake_ref.clone()),
                flake_attr.clone(),
                impure,
            )?,
            StandaloneSource::FlakeWithAttr(flake_ref, flake_attr),
        ),
    };

    let base = standalone_state_dir(state_dir)?;
    println!("Applying manifest...");
    let state = base.join("current").join("manifest.json");
    let actions_file = base.join("current").join("actions.json");
    run_activate_internal(ActivateArgs {
        manifest: manifest.path.clone(),
        state,
        actions_file: Some(actions_file),
        prefix,
        impure,
        external_linker,
        linker_args,
        json: false,
    })?;

    let generation_id = record_generation(&base, &manifest.path)?;
    write_last_source(&base, &source_ref)?;
    set_current_generation_id(&base, &generation_id)?;
    println!("Activated generation {generation_id}");
    Ok(())
}

fn standalone_switch_rollback(
    state_dir: Option<PathBuf>,
    external_linker: Option<PathBuf>,
    linker_args: Vec<String>,
    prefix: String,
    impure: bool,
) -> Result<(), String> {
    let base = standalone_state_dir(state_dir)?;
    let target_id = previous_generation_id(&base)?;
    println!("Rolling back to generation {target_id}...");
    let target_manifest = base
        .join("generations")
        .join(&target_id)
        .join("manifest.json");
    if !target_manifest.exists() {
        return Err(format!(
            "Generation manifest missing: {}",
            target_manifest.display()
        ));
    }

    let state = base.join("current").join("manifest.json");
    run_activate_internal(ActivateArgs {
        manifest: target_manifest,
        state,
        actions_file: Some(base.join("current").join("actions.json")),
        prefix,
        impure,
        external_linker,
        linker_args,
        json: false,
    })?;
    set_current_generation_id(&base, &target_id)?;
    Ok(())
}

fn eval_nix_config(config_path: &Path, impure: bool) -> Result<Value, String> {
    let mut cmd = ProcCommand::new("nix");
    cmd.arg("eval").arg("--json").arg("--file").arg(config_path);
    if impure {
        cmd.arg("--impure");
    }
    let output = cmd.output().map_err(|e| {
        format!(
            "failed to execute 'nix eval' for config '{}': {e}. Ensure Nix is installed and available in PATH",
            config_path.display()
        )
    })?;
    if !output.status.success() {
        return Err(format!(
            "nix eval failed for config '{}': {}\nHint: ensure the file evaluates to a manifest value or {{ manifest = ...; }} and pass --impure if your expression needs impure builtins",
            config_path.display(),
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    serde_json::from_slice(&output.stdout).map_err(|e| e.to_string())
}

fn eval_nix_flake(
    flake_ref: &str,
    flake_attr: Option<&str>,
    impure: bool,
) -> Result<Value, String> {
    let user = std::env::var("USER").unwrap_or_else(|_| "default".to_string());
    let attr = flake_attr
        .map(str::to_string)
        .unwrap_or_else(|| format!("hjemConfigurations.\"{user}\".manifest"));
    let full_ref = format!("{flake_ref}#{attr}");
    let mut cmd = ProcCommand::new("nix");
    cmd.arg("eval").arg("--json").arg(full_ref);
    if impure {
        cmd.arg("--impure");
    }
    let output = cmd.output().map_err(|e| {
        format!(
            "failed to execute 'nix eval' for flake '{flake_ref}': {e}. Ensure Nix is installed and available in PATH"
        )
    })?;
    if !output.status.success() {
        return Err(format!(
            "nix eval failed for flake '{}': {}\nHint: verify the flake output attr '{}' exists and evaluates to a manifest",
            flake_ref,
            String::from_utf8_lossy(&output.stderr),
            attr
        ));
    }
    serde_json::from_slice(&output.stdout).map_err(|e| {
        format!(
            "nix eval output for flake '{}' was not valid JSON: {e}",
            flake_ref
        )
    })
}

fn extract_manifest_json(value: Value) -> Result<Value, String> {
    if value.get("version").is_some() && value.get("files").is_some() {
        return Ok(value);
    }
    if let Some(manifest) = value.get("manifest") {
        return Ok(manifest.clone());
    }
    Err(
        "evaluated Nix value is not a manifest.\nExpected either:\n  1) { version = 3; files = [ ... ]; }\n  2) { manifest = { version = 3; files = [ ... ]; }; }"
            .to_string(),
    )
}

fn mk_temp_dir(prefix: &str) -> Result<PathBuf, String> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("{prefix}-{}-{now}", std::process::id()));
    fs::create_dir_all(&dir).map_err(|e| {
        format!(
            "failed to create temporary directory '{}': {e}",
            dir.display()
        )
    })?;
    Ok(dir)
}

struct ActivateArgs {
    manifest: PathBuf,
    state: PathBuf,
    actions_file: Option<PathBuf>,
    prefix: String,
    impure: bool,
    external_linker: Option<PathBuf>,
    linker_args: Vec<String>,
    json: bool,
}

fn run_activate_internal(args: ActivateArgs) -> Result<(), String> {
    let new_manifest = read_verified(&args.manifest, args.impure)?;
    let had_state = args.state.exists();

    let actions = if had_state {
        let old_manifest = read_verified(&args.state, args.impure)?;
        trigger_actions(&old_manifest, &new_manifest)
    } else {
        Vec::new()
    };

    if let Some(linker) = args.external_linker {
        run_external_linker(
            &linker,
            &args.linker_args,
            &args.manifest,
            &args.state,
            had_state,
        )?;
    } else {
        new_manifest
            .diff(&args.state, &args.prefix, true)
            .map_err(|e| format!("built-in linker activation failed: {e}"))?;
    }

    atomic_copy(&args.manifest, &args.state)?;

    let result = ActivateResult {
        mode: if had_state {
            "incremental".to_string()
        } else {
            "first".to_string()
        },
        actions,
    };

    if let Some(actions_file) = args.actions_file {
        if let Some(parent) = actions_file.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        fs::write(
            actions_file,
            serde_json::to_string_pretty(&result).map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
    }

    if args.json {
        print_json(&result)?;
    } else {
        println!("mode={}", result.mode);
    }

    Ok(())
}

fn run_external_linker(
    linker: &Path,
    linker_args: &[String],
    new_manifest: &Path,
    old_manifest: &Path,
    had_state: bool,
) -> Result<(), String> {
    println!("Using external linker: {}", linker.display());
    let mut cmd = ProcCommand::new(linker);
    for arg in linker_args {
        cmd.arg(arg);
    }

    if had_state {
        cmd.arg("diff").arg(new_manifest).arg(old_manifest);
    } else {
        cmd.arg("activate").arg(new_manifest);
    }

    let status = cmd.status().map_err(|e| {
        format!(
            "failed to execute external linker '{}': {e}",
            linker.display()
        )
    })?;
    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "external linker '{}' failed with status {}",
            linker.display(),
            status
        ))
    }
}

fn run_reload_actions(
    actions_file: &Path,
    user: &str,
    require_running_systemd: bool,
    json: bool,
) -> Result<(), String> {
    if require_running_systemd {
        let status = ProcCommand::new("systemctl")
            .args(["--user", "is-system-running"])
            .output()
            .map_err(|e| format!("failed to query systemd user status: {e}"))?;

        let running = String::from_utf8_lossy(&status.stdout).trim().to_string();
        if !(running == "running" || running == "degraded") {
            let res = ReloadResult {
                skipped: true,
                reason: Some(format!(
                    "User systemd for {user} is not running (status: {running})"
                )),
                applied: 0,
            };
            if json {
                print_json(&res)?;
            } else if let Some(reason) = res.reason {
                println!("{reason}");
            }
            return Ok(());
        }
    }

    let daemon_reload = ProcCommand::new("systemctl")
        .args(["--user", "daemon-reload"])
        .status()
        .map_err(|e| format!("failed to run systemctl --user daemon-reload: {e}"))?;
    if !daemon_reload.success() {
        return Err("systemctl --user daemon-reload failed".to_string());
    }

    if !actions_file.exists() {
        let res = ReloadResult {
            skipped: true,
            reason: Some(format!("No activation metadata for {user}; skipping.")),
            applied: 0,
        };
        if json {
            print_json(&res)?;
        }
        return Ok(());
    }

    let parsed: ActivateResult = serde_json::from_slice(
        &fs::read(actions_file).map_err(|e| e.to_string())?,
    )
    .map_err(|e| {
        format!(
            "failed to parse actions file '{}': {e}",
            actions_file.display()
        )
    })?;

    let mut applied = 0usize;
    for action in parsed.actions {
        let mut cmd = ProcCommand::new("systemctl");
        cmd.arg("--user");
        match action.action.as_str() {
            "restart" => {
                cmd.arg("try-restart").arg(&action.unit);
            }
            "reload" => {
                cmd.arg("reload-or-try-restart").arg(&action.unit);
            }
            _ => {
                continue;
            }
        }

        let status = cmd.status().map_err(|e| e.to_string())?;
        if !status.success() {
            eprintln!(
                "Warning: action {} failed for {}",
                action.action, action.unit
            );
        }
        applied += 1;
    }

    if json {
        print_json(&ReloadResult {
            skipped: false,
            reason: None,
            applied,
        })?;
    }

    Ok(())
}

fn run_cleanup_state(state_dir: &Path, enabled_users: &[String], json: bool) -> Result<(), String> {
    fs::create_dir_all(state_dir).map_err(|e| e.to_string())?;

    let enabled: BTreeSet<&str> = enabled_users.iter().map(String::as_str).collect();
    let mut removed = Vec::new();

    for entry in fs::read_dir(state_dir).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let file_name = entry.file_name();
        let file_name = file_name.to_string_lossy();

        let user = file_name
            .strip_prefix("manifest-")
            .and_then(|s| s.strip_suffix(".json"))
            .or_else(|| {
                file_name
                    .strip_prefix("actions-")
                    .and_then(|s| s.strip_suffix(".json"))
            });

        if let Some(user) = user
            && !enabled.contains(user)
        {
            fs::remove_file(entry.path()).map_err(|e| e.to_string())?;
            removed.push(file_name.to_string());
        }
    }

    if json {
        print_json(&CleanupResult { removed })?;
    }

    Ok(())
}

fn read_verified(path: &Path, impure: bool) -> Result<Manifest, String> {
    let manifest = Manifest::read(path, impure)
        .map_err(|e| format!("failed to read manifest '{}': {e}", path.display()))?;
    let violations = manifest.verify();
    if violations.is_empty() {
        Ok(manifest)
    } else {
        let errors = violations
            .iter()
            .map(std::string::ToString::to_string)
            .collect::<Vec<_>>()
            .join("\n");
        Err(format!(
            "manifest '{}' failed validation:\n{errors}",
            path.display()
        ))
    }
}

fn manifests_equivalent(
    new_manifest: &Manifest,
    old_path: &Path,
    impure: bool,
) -> Result<bool, String> {
    if !old_path.exists() {
        return Ok(false);
    }
    let old_manifest = read_verified(old_path, impure)?;

    let mut old_files = old_manifest.files.clone();
    let mut new_files = new_manifest.files.clone();

    old_files.sort_by(file_sort_key);
    new_files.sort_by(file_sort_key);

    Ok(old_files == new_files)
}

fn file_sort_key(a: &File, b: &File) -> std::cmp::Ordering {
    a.target
        .cmp(&b.target)
        .then_with(|| a.kind.to_string().cmp(&b.kind.to_string()))
        .then_with(|| a.source.cmp(&b.source))
}

fn trigger_actions(old_manifest: &Manifest, new_manifest: &Manifest) -> Vec<TriggerAction> {
    let old_units = unit_sources(old_manifest);
    let new_units = unit_sources(new_manifest);
    let mut actions = Vec::new();

    for (unit, new_source) in &new_units {
        let Some(old_source) = old_units.get(unit) else {
            continue;
        };

        let old_restart = trigger_value(old_source, "X-Restart-Triggers");
        let new_restart = trigger_value(new_source, "X-Restart-Triggers");
        let old_reload = trigger_value(old_source, "X-Reload-Triggers");
        let new_reload = trigger_value(new_source, "X-Reload-Triggers");

        if !new_restart.is_empty() && old_restart != new_restart {
            actions.push(TriggerAction {
                action: "restart".to_string(),
                unit: unit.clone(),
                reason: "restart trigger changed".to_string(),
            });
            continue;
        }

        if !new_reload.is_empty() && old_reload != new_reload {
            actions.push(TriggerAction {
                action: "reload".to_string(),
                unit: unit.clone(),
                reason: "reload trigger changed".to_string(),
            });
        }
    }

    actions
}

fn unit_sources(manifest: &Manifest) -> HashMap<String, PathBuf> {
    let mut sources = HashMap::new();

    for file in &manifest.files {
        if file.kind != FileKind::Symlink {
            continue;
        }
        let Some(source) = &file.source else {
            continue;
        };
        let target = file.target.to_string_lossy();
        if !target.contains("/systemd/user/") {
            continue;
        }
        let Some(name) = file.target.file_name() else {
            continue;
        };
        let unit = name.to_string_lossy();
        if !(unit.ends_with(".service") || unit.ends_with(".timer") || unit.ends_with(".socket")) {
            continue;
        }

        sources.insert(unit.to_string(), source.clone());
    }

    sources
}

fn trigger_value(path: &Path, key: &str) -> String {
    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(_) => return String::new(),
    };

    let prefix = format!("{key}=");
    let reader = BufReader::new(file);
    for line in reader.lines() {
        let Ok(line) = line else {
            continue;
        };
        if let Some(value) = line.strip_prefix(&prefix) {
            return value.to_string();
        }
    }

    String::new()
}

fn atomic_copy(src: &Path, dst: &Path) -> Result<(), String> {
    let parent = dst
        .parent()
        .ok_or_else(|| format!("state path has no parent: {}", dst.display()))?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;

    let tmp = parent.join(format!(".hjem-manifest-{}.tmp", std::process::id()));
    fs::copy(src, &tmp).map_err(|e| {
        format!(
            "failed to copy '{}' to '{}': {e}",
            src.display(),
            tmp.display()
        )
    })?;
    fs::rename(&tmp, dst).map_err(|e| {
        format!(
            "failed to replace state manifest '{}' with '{}': {e}",
            dst.display(),
            src.display()
        )
    })?;

    Ok(())
}

fn print_json<T: Serialize>(value: &T) -> Result<(), String> {
    let output = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    println!("{output}");
    Ok(())
}

fn standalone_state_dir(override_dir: Option<PathBuf>) -> Result<PathBuf, String> {
    if let Some(path) = override_dir {
        return Ok(path);
    }

    if let Ok(xdg) = std::env::var("XDG_STATE_HOME") {
        return Ok(PathBuf::from(xdg).join("hjem").join("standalone"));
    }

    let home = std::env::var("HOME").map_err(|_| "HOME is not set".to_string())?;
    Ok(PathBuf::from(home)
        .join(".local")
        .join("state")
        .join("hjem")
        .join("standalone"))
}

fn record_generation(base: &Path, manifest: &Path) -> Result<String, String> {
    let generation_id = now_id("generation");
    let generation_dir = base.join("generations").join(&generation_id);
    fs::create_dir_all(&generation_dir).map_err(|e| e.to_string())?;
    atomic_copy(manifest, &generation_dir.join("manifest.json"))?;
    Ok(generation_id)
}

fn list_generations(base: &Path) -> Result<Vec<PathBuf>, String> {
    let generations_dir = base.join("generations");
    if !generations_dir.exists() {
        return Ok(Vec::new());
    }

    let mut out = Vec::new();
    for entry in fs::read_dir(&generations_dir).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        if entry.path().is_dir() {
            out.push(entry.path());
        }
    }
    out.sort();
    Ok(out)
}

fn generation_manifest_path(base: &Path, generation: &str) -> Result<PathBuf, String> {
    if generation_order_key(generation).is_none() {
        return Err(format!("invalid generation id: {generation}"));
    }

    let manifest = base
        .join("generations")
        .join(generation)
        .join("manifest.json");
    if !manifest.exists() {
        return Err(format!(
            "Generation manifest missing: {}",
            manifest.display()
        ));
    }
    Ok(manifest)
}

fn generation_id_from_path(path: &Path) -> Option<String> {
    path.file_name().map(|x| x.to_string_lossy().to_string())
}

fn generation_timestamp_from_id(id: &str) -> Option<u64> {
    generation_order_key(id).map(|(ts, _)| ts)
}

fn generation_order_key(id: &str) -> Option<(u64, u32)> {
    let mut parts = id.split('-');
    let (Some("generation"), Some(seconds), Some(nanoseconds), None) =
        (parts.next(), parts.next(), parts.next(), parts.next())
    else {
        return None;
    };
    let ts = seconds.parse::<u64>().ok()?;
    let nanos = nanoseconds.parse::<u32>().ok()?;
    Some((ts, nanos))
}

fn parse_expire_timestamp(input: &str) -> Result<u64, String> {
    let trimmed = input.trim();

    if let Ok(unix) = trimmed.parse::<u64>() {
        return Ok(unix);
    }

    if let Some(days_str) = trimmed
        .strip_prefix('-')
        .and_then(|s| s.strip_suffix(" days").or_else(|| s.strip_suffix('d')))
    {
        let days = days_str
            .trim()
            .parse::<u64>()
            .map_err(|_| format!("Invalid relative day count: {input}"))?;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| e.to_string())?
            .as_secs();
        return Ok(now.saturating_sub(days.saturating_mul(24 * 60 * 60)));
    }

    if let Ok(timestamp) = trimmed.parse::<Timestamp>() {
        return timestamp_to_seconds(timestamp.as_second(), input);
    }

    if let Ok(date) = Date::strptime("%F", trimmed) {
        return timestamp_to_seconds(
            date.in_tz("UTC")
                .map_err(|error| format!("Invalid date: {input}: {error}"))?
                .timestamp()
                .as_second(),
            input,
        );
    }

    Err(format!(
        "Unsupported timestamp format '{input}'. Use unix seconds, YYYY-MM-DD, RFC3339, or -N days"
    ))
}

fn timestamp_to_seconds(timestamp: i64, input: &str) -> Result<u64, String> {
    u64::try_from(timestamp).map_err(|_| format!("Timestamp is before epoch: {input}"))
}

fn read_current_generation_id(base: &Path) -> Result<Option<String>, String> {
    let file = base.join("current-generation");
    if !file.exists() {
        return Ok(None);
    }
    let content = fs::read_to_string(file).map_err(|e| e.to_string())?;
    let id = content.trim().to_string();
    if id.is_empty() {
        Ok(None)
    } else {
        Ok(Some(id))
    }
}

fn set_current_generation_id(base: &Path, id: &str) -> Result<(), String> {
    fs::create_dir_all(base).map_err(|e| e.to_string())?;
    let current = base.join("current-generation");
    let current_tmp = base.join(format!(".current-generation-{}", std::process::id()));
    fs::write(&current_tmp, format!("{id}\n")).map_err(|e| e.to_string())?;
    fs::rename(&current_tmp, &current).map_err(|e| e.to_string())?;
    Ok(())
}

fn previous_generation_id(base: &Path) -> Result<String, String> {
    let mut ids = list_generations(base)?
        .into_iter()
        .filter_map(|p| generation_id_from_path(&p))
        .collect::<Vec<_>>();
    sort_generation_ids(&mut ids);
    if ids.len() < 2 {
        return Err("No previous generation available for rollback".to_string());
    }

    if let Some(current) = read_current_generation_id(base)?
        && let Some(idx) = ids.iter().position(|id| id == &current)
    {
        if idx == 0 {
            return Err("No previous generation available for rollback".to_string());
        }
        return Ok(ids[idx - 1].clone());
    }

    Ok(ids[ids.len() - 2].clone())
}

fn newest_generation_ids(generations: &[PathBuf], keep_last: usize) -> BTreeSet<String> {
    let mut ids = generations
        .iter()
        .filter_map(|path| generation_id_from_path(path))
        .collect::<Vec<_>>();
    sort_generation_ids(&mut ids);
    ids.into_iter().rev().take(keep_last).collect()
}

fn sort_generation_ids(ids: &mut [String]) {
    ids.sort_by(
        |a, b| match (generation_order_key(a), generation_order_key(b)) {
            (Some(a_key), Some(b_key)) => a_key.cmp(&b_key).then_with(|| a.cmp(b)),
            _ => a.cmp(b),
        },
    );
}

fn write_last_source(base: &Path, source: &StandaloneSource) -> Result<(), String> {
    fs::create_dir_all(base).map_err(|e| e.to_string())?;
    let path = base.join("last-source");
    let content = match source {
        StandaloneSource::Manifest(path) => format!("manifest={}\n", path.display()),
        StandaloneSource::Config(path) => format!("config={}\n", path.display()),
        StandaloneSource::Flake(path) => format!("flake={}\n", path.display()),
        StandaloneSource::FlakeWithAttr(flake, attr) => {
            let attr = attr.as_deref().unwrap_or_default();
            format!("flake={flake}\nflakeAttr={attr}\n")
        }
    };
    fs::write(path, content).map_err(|e| e.to_string())
}

fn standalone_config_dir(dir: Option<PathBuf>) -> Result<PathBuf, String> {
    if let Some(dir) = dir {
        return Ok(dir);
    }
    if let Ok(config_home) = std::env::var("XDG_CONFIG_HOME") {
        return Ok(PathBuf::from(config_home).join("hjem"));
    }
    Ok(home_dir()?.join(".config").join("hjem"))
}

fn home_dir() -> Result<PathBuf, String> {
    std::env::var("HOME")
        .map(PathBuf::from)
        .map_err(|_| "HOME is not set".to_string())
}

fn now_id(prefix: &str) -> String {
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    format!(
        "{prefix}-{}-{}",
        duration.as_secs(),
        duration.subsec_nanos()
    )
}

#[cfg(test)]
mod tests {
    use super::{
        Command, StandaloneCommand, generation_manifest_path, generation_order_key,
        parse_expire_timestamp, parse_multicall_args, standalone_source,
    };
    use std::path::Path;

    #[test]
    fn generation_paths_reject_invalid_ids() {
        assert!(generation_manifest_path(Path::new("/state"), "../../outside").is_err());
        assert!(generation_manifest_path(Path::new("/state"), "generation-1-2-extra").is_err());
        assert_eq!(generation_order_key("generation-1-2"), Some((1, 2)));
    }

    #[test]
    fn flake_attr_requires_a_flake_source() {
        assert!(
            standalone_source(
                None,
                Some("hjem.nix".into()),
                None,
                Some("hjemConfigurations.alice.manifest".to_string()),
            )
            .is_err()
        );
    }

    #[test]
    fn multicall_accepts_relative_expiry_timestamps() {
        let cli = parse_multicall_args(
            ["hjem-standalone", "expire-generations", "-30 days"].map(str::to_owned),
        )
        .expect("relative expiry timestamp should parse");
        let Command::Standalone {
            command:
                StandaloneCommand::ExpireGenerations {
                    timestamp: Some(timestamp),
                    ..
                },
        } = cli.command
        else {
            panic!("expected expire-generations command");
        };
        assert_eq!(timestamp, "-30 days");
    }

    #[test]
    fn expiry_timestamps_accept_rfc3339_and_dates() {
        assert_eq!(parse_expire_timestamp("1970-01-01T00:00:01Z"), Ok(1));
        assert_eq!(parse_expire_timestamp("2024-01-02"), Ok(1_704_153_600));
    }
}
